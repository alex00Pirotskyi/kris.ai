@echo off
setlocal
call "%~dp0..\tool\verify.cmd"
exit /b %ERRORLEVEL%
