@echo off
setlocal EnableExtensions
cd /d "%~dp0.."

where flutter >nul 2>nul
if errorlevel 1 (
  echo ERROR: Flutter is required and must be available on PATH. 1>&2
  exit /b 2
)

call flutter --version
if errorlevel 1 exit /b 1

call flutter config --enable-windows-desktop
if errorlevel 1 (
  echo ERROR: Flutter could not enable Windows desktop support. 1>&2
  exit /b 1
)

if not exist "windows\CMakeLists.txt" (
  echo Generating the standard Flutter Windows runner...
  call flutter create --project-name kristin_local_agent --org local.kristin --platforms=windows .
  if errorlevel 1 (
    echo ERROR: Flutter Windows platform bootstrap failed. 1>&2
    exit /b 1
  )
)

call flutter pub get
if errorlevel 1 (
  echo ERROR: Flutter dependency resolution failed. 1>&2
  exit /b 1
)

exit /b 0
