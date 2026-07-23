@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
where py >nul 2>nul
if %ERRORLEVEL% EQU 0 (
  py -3 "%SCRIPT_DIR%tool\kristin_cli.py" %*
) else (
  python "%SCRIPT_DIR%tool\kristin_cli.py" %*
)
exit /b %ERRORLEVEL%
