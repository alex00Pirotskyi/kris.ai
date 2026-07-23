$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw "Flutter is required and must be available on PATH."
}

& (Join-Path $PSScriptRoot "prune_stale_legacy.cmd")
if ($LASTEXITCODE -ne 0) { throw "Legacy migration failed." }

if (Get-Command python -ErrorAction SilentlyContinue) {
  python tool/protocol_contract_test.py
} elseif (Get-Command py -ErrorAction SilentlyContinue) {
  py -3 tool/protocol_contract_test.py
} else {
  throw "Python 3 is required for generated protocol validation."
}
if ($LASTEXITCODE -ne 0) { throw "Protocol contract validation failed." }

flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed." }

dart format lib test tool/prune_stale_legacy.dart
if ($LASTEXITCODE -ne 0) { throw "dart format failed." }

flutter analyze --fatal-warnings --fatal-infos
if ($LASTEXITCODE -ne 0) { throw "flutter analyze failed." }

flutter test --reporter expanded
if ($LASTEXITCODE -ne 0) { throw "flutter test failed." }

$validated = $false
if (Get-Command python -ErrorAction SilentlyContinue) {
  python tool/validate_release.py --skip-tests
  $validated = $true
} elseif (Get-Command py -ErrorAction SilentlyContinue) {
  py -3 tool/validate_release.py --skip-tests
  $validated = $true
} else {
  Write-Warning "Python 3 is unavailable, so the supplemental source gate was skipped."
}

if ($validated -and $LASTEXITCODE -ne 0) {
  throw "Release-source validation failed."
}
