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
  python tool\protocol_contract_test.py
  if errorlevel 1 exit /b 1
) else (
  where py >nul 2>nul
  if not errorlevel 1 (
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

call dart format lib test tool\prune_stale_legacy.dart
if errorlevel 1 (
  echo ERROR: dart format failed. 1>&2
  exit /b 1
)

call flutter analyze --fatal-warnings --fatal-infos
if errorlevel 1 (
  echo ERROR: flutter analyze failed. 1>&2
  exit /b 1
)

call flutter test --reporter expanded
if errorlevel 1 (
  echo ERROR: flutter test failed. 1>&2
  exit /b 1
)

where python >nul 2>nul
if not errorlevel 1 (
  python tool\validate_release.py --skip-tests
  if errorlevel 1 (
    echo ERROR: Supplemental release-source validation failed. 1>&2
    exit /b 1
  )
  exit /b 0
)

where py >nul 2>nul
if not errorlevel 1 (
  py -3 tool\validate_release.py --skip-tests
  if errorlevel 1 (
    echo ERROR: Supplemental release-source validation failed. 1>&2
    exit /b 1
  )
  exit /b 0
)

echo WARNING: Python 3 is unavailable, so the supplemental source gate was skipped.
echo Flutter formatting, analysis, and tests passed.
exit /b 0
