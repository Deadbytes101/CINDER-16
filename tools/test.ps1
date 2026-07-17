[CmdletBinding()]
param(
    [switch]$RebuildRuntime
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$LocalIo = Join-Path $RepoRoot ".tools\bin\io.exe"
$Bootstrap = Join-Path $PSScriptRoot "bootstrap-io.ps1"
$TestFile = Join-Path $RepoRoot "tests\core_test.io"

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
    Write-Host "EXECUTE: tests/core_test.io"
    & $IoExe $TestFile
    $TestExitCode = $LASTEXITCODE
}
finally {
    Pop-Location
}

if ($TestExitCode -ne 0) {
    Write-Error "CINDER-16 core tests failed with exit code $TestExitCode"
    exit $TestExitCode
}

Write-Host "CINDER-16 CORE TESTS PASSED"
exit 0
