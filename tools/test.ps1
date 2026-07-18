[CmdletBinding()]
param(
    [switch]$RebuildRuntime
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$LocalIo = Join-Path $RepoRoot ".tools\bin\io.exe"
$Bootstrap = Join-Path $PSScriptRoot "bootstrap-io.ps1"
$TestFiles = @(
    "tests\core_test.io",
    "tests\v0_1_test.io"
)

$Runtime = Get-Command "io" -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1

if ($null -ne $Runtime -and -not $RebuildRuntime) {
    $IoExe = $Runtime.Source
    Write-Host "RUNTIME: $IoExe"
}
else {
    $BootstrapArguments = @()
    if ($RebuildRuntime) {
        $BootstrapArguments += "-Force"
    }

    & $Bootstrap @BootstrapArguments
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    if (-not (Test-Path $LocalIo)) {
        throw "Local Io runtime was not created: $LocalIo"
    }

    $IoExe = $LocalIo
    Write-Host "RUNTIME: $IoExe"
}

Push-Location $RepoRoot
try {
    foreach ($RelativeTestFile in $TestFiles) {
        $TestFile = Join-Path $RepoRoot $RelativeTestFile
        $DisplayPath = $RelativeTestFile.Replace("\", "/")
        Write-Host "EXECUTE: $DisplayPath"
        & $IoExe $TestFile
        $TestExitCode = $LASTEXITCODE

        if ($TestExitCode -ne 0) {
            Write-Error "$DisplayPath failed with exit code $TestExitCode"
            exit $TestExitCode
        }

        Write-Host "PASS: $DisplayPath"
    }
}
finally {
    Pop-Location
}

Write-Host "CINDER-16 V0.1 TEST SUITE PASSED"
exit 0
