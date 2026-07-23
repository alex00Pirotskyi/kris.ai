param(
  [ValidateSet("windows")]
  [string]$Platform = "windows"
)

$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw "Flutter is required and must be available on PATH."
}

flutter --version
if ($LASTEXITCODE -ne 0) { throw "Flutter is unavailable." }
flutter config --enable-windows-desktop
if ($LASTEXITCODE -ne 0) { throw "Flutter could not enable Windows desktop support." }

if (-not (Test-Path (Join-Path $Platform "CMakeLists.txt"))) {
  flutter create --project-name kristin_local_agent --org local.kristin --platforms=$Platform .
  if ($LASTEXITCODE -ne 0) { throw "Flutter platform bootstrap failed." }
}

flutter pub get
if ($LASTEXITCODE -ne 0) { throw "Flutter dependency resolution failed." }
