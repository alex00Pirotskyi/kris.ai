@echo off
setlocal EnableExtensions
cd /d "%~dp0.."
where py >nul 2>nul
if not errorlevel 1 (
  py -3 dev.py run windows
  exit /b %ERRORLEVEL%
)
python dev.py run windows
exit /b %ERRORLEVEL%
