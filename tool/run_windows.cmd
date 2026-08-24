@echo off
setlocal EnableExtensions
cd /d "%~dp0.."

where flutter >nul 2>nul
if errorlevel 1 (
  echo ERROR: Flutter is required and must be available on PATH. 1>&2
  exit /b 2
)

call "%~dp0prune_stale_legacy.cmd"
if errorlevel 1 exit /b 1

call "%~dp0bootstrap_platforms.cmd"
if errorlevel 1 exit /b 1

if /I "%KRISTIN_VERIFY_BEFORE_RUN%"=="1" (
  call "%~dp0verify.cmd"
  if errorlevel 1 exit /b 1
)

call flutter run -d windows
if errorlevel 1 exit /b 1
exit /b 0
