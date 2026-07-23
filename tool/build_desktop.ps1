$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
& "$PSScriptRoot/bootstrap_platforms.ps1"
if ($LASTEXITCODE -ne 0) { throw "Desktop platform bootstrap failed." }
& "$PSScriptRoot/verify.ps1"
if ($LASTEXITCODE -ne 0) { throw "Verification failed." }
flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw "Windows release build failed." }
