$ErrorActionPreference = 'Stop'
$exerciseDir = Split-Path -Parent $PSScriptRoot
$rExecutable = 'C:/Program Files/R/R-4.6.1/bin/x64/Rscript.exe'
$previousLocale = $env:LC_ALL
$previousBytecode = $env:PYTHONDONTWRITEBYTECODE
Push-Location -LiteralPath $exerciseDir
try {
    $env:LC_ALL = 'C'
    $env:PYTHONDONTWRITEBYTECODE = '1'
    & python R/acquire-public.py --verify
    if ($LASTEXITCODE -ne 0) { throw 'Public acquisition verification failed' }
    foreach ($testFile in @('test-data.R','test-public.R','test-model.R','test-scenarios.R','test-cache.R')) {
        & $rExecutable --vanilla (Join-Path 'tests' $testFile)
        if ($LASTEXITCODE -ne 0) { throw "Failed: $testFile" }
    }
    & python tests/test-ridership-download.py
    if ($LASTEXITCODE -ne 0) { throw 'Ridership download tests failed' }
    & python tests/test-ridership-diagnostics.py
    if ($LASTEXITCODE -ne 0) { throw 'Ridership diagnostic tests failed' }
    & python tests/test-ridership-ui.py
    if ($LASTEXITCODE -ne 0) { throw 'Ridership UI feedback tests failed' }
    & python tests/test-public-reproduction.py
    if ($LASTEXITCODE -ne 0) { throw 'Source-only reproduction check failed' }
    $scriptTokens = $null
    $scriptErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $exerciseDir 'download-ridership.ps1'), [ref]$scriptTokens, [ref]$scriptErrors)
    if ($scriptErrors.Count -gt 0) { throw 'PowerShell download wrapper syntax failed' }
    Write-Output 'PASS: scoped offline checks. Real-input analysis and rendering are verified separately.'
} finally {
    $env:LC_ALL = $previousLocale
    $env:PYTHONDONTWRITEBYTECODE = $previousBytecode
    Pop-Location
}
