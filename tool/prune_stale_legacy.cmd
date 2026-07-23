@echo off
setlocal EnableExtensions
cd /d "%~dp0.."

where dart >nul 2>nul
if errorlevel 1 (
  echo ERROR: Dart is required and must be available on PATH. 1>&2
  exit /b 2
)

call dart run tool\prune_stale_legacy.dart
if errorlevel 1 exit /b 1
exit /b 0
