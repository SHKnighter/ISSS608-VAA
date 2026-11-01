# Run locally after receiving your LTA DataMall AccountKey.
$ErrorActionPreference = 'Stop'
$previousKey = $env:LTA_ACCOUNT_KEY
$keyBuffer = [IntPtr]::Zero
$secretInput = $null
Push-Location -LiteralPath $PSScriptRoot
try {
    if ([string]::IsNullOrWhiteSpace($env:LTA_ACCOUNT_KEY)) {
        $secretInput = Read-Host 'LTA DataMall AccountKey (hidden input)' -AsSecureString
        $keyBuffer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secretInput)
        $env:LTA_ACCOUNT_KEY = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($keyBuffer)
    }
    & python 'R/acquire-ridership.py' --download
    if ($LASTEXITCODE -ne 0) { throw 'Download did not finish. Check the safe message above.' }
} finally {
    $env:LTA_ACCOUNT_KEY = $previousKey
    if ($keyBuffer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($keyBuffer) }
    if ($secretInput) { $secretInput.Dispose() }
    Pop-Location
}
