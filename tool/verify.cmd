@echo off
setlocal EnableExtensions
cd /d "%~dp0.."

where flutter >nul 2>nul
if errorlevel 1 (
  echo ERROR: Flutter is required and must be available on PATH. 1>&2
  exit /b 2
)
where dart >nul 2>nul
if errorlevel 1 (
  echo ERROR: Dart is required and must be available on PATH. 1>&2
  exit /b 2
)

call "%~dp0prune_stale_legacy.cmd"
if errorlevel 1 exit /b 1

where python >nul 2>nul
if not errorlevel 1 (
  set "PYTHON_KIND=python"
  python tool\protocol_contract_test.py
  if errorlevel 1 exit /b 1
) else (
  where py >nul 2>nul
  if not errorlevel 1 (
    set "PYTHON_KIND=py"
    py -3 tool\protocol_contract_test.py
    if errorlevel 1 exit /b 1
  ) else (
    echo ERROR: Python 3 is required for generated protocol validation. 1>&2
    exit /b 2
  )
)

call flutter pub get
if errorlevel 1 (
  echo ERROR: flutter pub get failed. 1>&2
  exit /b 1
)

if "%PYTHON_KIND%"=="python" (
  python tool\dart_format_scope.py --check
) else (
  py -3 tool\dart_format_scope.py --check
)
if errorlevel 1 (
  echo ERROR: Dart format scope check failed. 1>&2
  exit /b 1
)

call flutter analyze --no-pub --fatal-warnings --fatal-infos
if errorlevel 1 (
  echo ERROR: flutter analyze failed. 1>&2
  exit /b 1
)

call flutter test --no-pub --concurrency=1 --reporter expanded
if errorlevel 1 (
  echo ERROR: flutter test failed. 1>&2
  exit /b 1
)

if "%PYTHON_KIND%"=="python" (
  python tool\validate_release.py --skip-tests
) else (
  py -3 tool\validate_release.py --skip-tests
)
if errorlevel 1 (
  echo ERROR: Supplemental release-source validation failed. 1>&2
  exit /b 1
)

exit /b 0
