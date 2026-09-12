# Builds the FINAL signed production Android artifacts against a real HTTPS API.
# Run from anywhere:
#   release\scripts\build-production.ps1 -ApiUrl https://api.example.com
param(
    [Parameter(Mandatory = $true)]
    [string]$ApiUrl
)

if ($ApiUrl -notlike "https://*") {
    throw "Production API base URL must be HTTPS (got: $ApiUrl)"
}

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
Push-Location $root
try {
    Write-Host "=> Building signed production APK  (API_BASE_URL=$ApiUrl)"
    flutter build apk --release "--dart-define=API_BASE_URL=$ApiUrl"
    if ($LASTEXITCODE -ne 0) { throw "APK build failed" }
    Copy-Item build\app\outputs\flutter-apk\app-release.apk release\CivicIntelligence.apk -Force

    Write-Host "=> Building signed production AAB  (API_BASE_URL=$ApiUrl)"
    flutter build appbundle --release "--dart-define=API_BASE_URL=$ApiUrl"
    if ($LASTEXITCODE -ne 0) { throw "AAB build failed" }
    Copy-Item build\app\outputs\bundle\release\app-release.aab release\CivicIntelligence.aab -Force

    Write-Host "OK: release\CivicIntelligence.apk and release\CivicIntelligence.aab written."
}
finally {
    Pop-Location
}