@echo off
setlocal EnableExtensions
cd /d "%~dp0.."

call "%~dp0prune_stale_legacy.cmd"
if errorlevel 1 exit /b 1

call "%~dp0bootstrap_platforms.cmd"
if errorlevel 1 exit /b 1

call "%~dp0verify.cmd"
if errorlevel 1 exit /b 1

call flutter build windows --release
if errorlevel 1 exit /b 1
exit /b 0
