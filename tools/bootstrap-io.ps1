[CmdletBinding()]
param(
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ToolsRoot = Join-Path $RepoRoot ".tools"
$SourceRoot = Join-Path $ToolsRoot "io-native-src"
$BuildRoot = Join-Path $ToolsRoot "io-native-build"
$BinRoot = Join-Path $ToolsRoot "bin"
$IoExe = Join-Path $BinRoot "io.exe"
$IoRef = "2026.04.20-native-final"
$IoCommit = "e5024305c07a7c05d41c0200901678fb0789e029"

function Require-Command {
    param([Parameter(Mandatory = $true)][string]$Name)

    $Command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -eq $Command) {
        throw "Required command not found: $Name"
    }

    return $Command
}

function Replace-TextOnce {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Needle,
        [Parameter(Mandatory = $true)][string]$Replacement,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $Content = [System.IO.File]::ReadAllText($Path)
    if ($Content.Contains($Replacement)) {
        Write-Host "PATCH PRESENT: $Label"
        return
    }

    $Count = ([regex]::Matches(
        $Content,
        [regex]::Escape($Needle)
    )).Count

    if ($Count -ne 1) {
        throw "Patch '$Label' expected one match in $Path, found $Count"
    }

    $Patched = $Content.Replace($Needle, $Replacement)
    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Patched, $Utf8NoBom)
    Write-Host "PATCH APPLIED: $Label"
}

if ($Force) {
    Remove-Item -Recurse -Force $SourceRoot -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $BuildRoot -ErrorAction SilentlyContinue
    Remove-Item -Force $IoExe -ErrorAction SilentlyContinue
}

$null = Require-Command "git"
$null = Require-Command "cmake"

New-Item -ItemType Directory -Force $ToolsRoot | Out-Null
New-Item -ItemType Directory -Force $BinRoot | Out-Null

if (-not (Test-Path (Join-Path $SourceRoot ".git"))) {
    Write-Host "CLONE Io $IoRef"
    & git -c advice.detachedHead=false clone --recursive --depth 1 `
        --branch $IoRef https://github.com/IoLanguage/io.git $SourceRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Io source clone failed with exit code $LASTEXITCODE"
    }
}
else {
    Write-Host "REFRESH Io $IoRef"
    & git -C $SourceRoot fetch --depth 1 origin `
        "refs/tags/${IoRef}:refs/tags/${IoRef}"
    if ($LASTEXITCODE -ne 0) {
        throw "Io tag fetch failed with exit code $LASTEXITCODE"
    }

    & git -C $SourceRoot checkout --detach $IoRef
    if ($LASTEXITCODE -ne 0) {
        throw "Io checkout failed with exit code $LASTEXITCODE"
    }

    & git -C $SourceRoot submodule update --init --recursive
    if ($LASTEXITCODE -ne 0) {
        throw "Io submodule update failed with exit code $LASTEXITCODE"
    }
}

$ActualCommit = (& git -C $SourceRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) {
    throw "Unable to resolve checked-out Io commit"
}
if ($ActualCommit -ne $IoCommit) {
    throw "Io ref resolved to $ActualCommit; expected $IoCommit"
}
Write-Host "Io COMMIT VERIFIED: $ActualCommit"

$CoroutineSource = Join-Path $SourceRoot "libs\iovm\source\IoCoroutine.c"
$ExecInfoGuard = @'
#if !defined(_WIN32)
#include <execinfo.h>
#endif
'@
Replace-TextOnce `
    -Path $CoroutineSource `
    -Needle "#include <execinfo.h>" `
    -Replacement $ExecInfoGuard `
    -Label "guard execinfo.h on Windows"

$StateSource = Join-Path $SourceRoot "libs\iovm\source\IoState.c"
$ProtoLookupNeedle = @'
IoObject *IoState_protoWithId_(IoState *self, const char *v) {
    IoObject *proto = PointerHash_at_(self->primitives, (void *)v);

    // printf("IoState_protoWithId_(self, %s)\n", v);

    if (!proto) {
'@
$ProtoLookupReplacement = @'
IoObject *IoState_protoWithId_(IoState *self, const char *v) {
    IoObject *proto = PointerHash_at_(self->primitives, (void *)v);

    // PointerHash compares key addresses. Identical proto id literals from
    // different translation units are not guaranteed to share an address.
    // Preserve the fast path, then fall back to content comparison.
    if (!proto) {
        POINTERHASH_FOREACH(
            self->primitives, key, candidate,
            if (key && strcmp((const char *)key, v) == 0) {
                proto = candidate;
            });
    }

    if (!proto) {
'@
Replace-TextOnce `
    -Path $StateSource `
    -Needle $ProtoLookupNeedle `
    -Replacement $ProtoLookupReplacement `
    -Label "compare proto ids by content after pointer miss"

$GeneratorArguments = @()
$ConfigureArguments = @("-DCMAKE_BUILD_TYPE=Release")

if ($null -ne (Get-Command "mingw32-make" -ErrorAction SilentlyContinue)) {
    $GeneratorArguments = @("-G", "MinGW Makefiles")
    $ConfigureArguments += `
        "-DCMAKE_C_FLAGS=-Wno-error=incompatible-pointer-types -Wno-error=implicit-function-declaration"
    Write-Host "GENERATOR: MinGW Makefiles"
    Write-Host "COMPAT: GCC pointer diagnostics downgraded to warnings"
}
elseif ($null -ne (Get-Command "ninja" -ErrorAction SilentlyContinue)) {
    $GeneratorArguments = @("-G", "Ninja")
    Write-Host "GENERATOR: Ninja"
}
else {
    Write-Host "GENERATOR: CMake default"
}

Write-Host "CONFIGURE Io"
& cmake -Wno-dev -S $SourceRoot -B $BuildRoot `
    @GeneratorArguments @ConfigureArguments
if ($LASTEXITCODE -ne 0) {
    throw "Io configure failed with exit code $LASTEXITCODE. Install a C compiler toolchain such as MinGW-W64 or Visual Studio Build Tools."
}

Write-Host "BUILD io_static"
& cmake --build $BuildRoot --config Release --target io_static --parallel
if ($LASTEXITCODE -ne 0) {
    throw "Io build failed with exit code $LASTEXITCODE"
}

$BuiltRuntime = Get-ChildItem -Path $BuildRoot -Recurse -File `
    -Filter "io_static.exe" | Select-Object -First 1

if ($null -eq $BuiltRuntime) {
    throw "Build completed but io_static.exe was not found under $BuildRoot"
}

Copy-Item -Force $BuiltRuntime.FullName $IoExe
Write-Host "IO RUNTIME READY: $IoExe"
