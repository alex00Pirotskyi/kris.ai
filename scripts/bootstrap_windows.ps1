$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
& "$PSScriptRoot\..\tool\bootstrap_platforms.ps1"
if ($LASTEXITCODE -ne 0) { throw "Windows platform bootstrap failed." }
& "$PSScriptRoot\..\tool\verify.ps1"
if ($LASTEXITCODE -ne 0) { throw "Verification failed." }
flutter run -d windows
if ($LASTEXITCODE -ne 0) { throw "Flutter Windows run failed." }
