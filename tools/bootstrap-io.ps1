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

function Require-Command {
    param([Parameter(Mandatory = $true)][string]$Name)

    $Command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -eq $Command) {
        throw "Required command not found: $Name"
    }

    return $Command
}

if ($Force) {
    Remove-Item -Recurse -Force $SourceRoot -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $BuildRoot -ErrorAction SilentlyContinue
    Remove-Item -Force $IoExe -ErrorAction SilentlyContinue
}

if (Test-Path $IoExe) {
    Write-Host "IO RUNTIME READY: $IoExe"
    exit 0
}

$null = Require-Command "git"
$null = Require-Command "cmake"

New-Item -ItemType Directory -Force $ToolsRoot | Out-Null
New-Item -ItemType Directory -Force $BinRoot | Out-Null

if (-not (Test-Path (Join-Path $SourceRoot ".git"))) {
    Write-Host "CLONE Io $IoRef"
    & git clone --recursive --depth 1 --branch $IoRef `
        https://github.com/IoLanguage/io.git $SourceRoot
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

$GeneratorArguments = @()
if ($null -ne (Get-Command "mingw32-make" -ErrorAction SilentlyContinue)) {
    $GeneratorArguments = @("-G", "MinGW Makefiles")
    Write-Host "GENERATOR: MinGW Makefiles"
}
elseif ($null -ne (Get-Command "ninja" -ErrorAction SilentlyContinue)) {
    $GeneratorArguments = @("-G", "Ninja")
    Write-Host "GENERATOR: Ninja"
}
else {
    Write-Host "GENERATOR: CMake default"
}

Write-Host "CONFIGURE Io"
& cmake -S $SourceRoot -B $BuildRoot @GeneratorArguments `
    "-DCMAKE_BUILD_TYPE=Release" `
    "-DWITHOUT_EERIE=1"
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
