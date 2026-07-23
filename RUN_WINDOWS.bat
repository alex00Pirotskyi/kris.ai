@echo off
setlocal EnableExtensions
cd /d "%~dp0"
echo Starting Kristin v1.0 Prompt-to-Task Product Preview...
call "%~dp0tool\run_windows.cmd"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
  echo.
  echo Kristin did not start. Review the first error above.
  pause
)
exit /b %RC%
