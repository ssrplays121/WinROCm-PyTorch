@echo off
rem WinROCm Status Shortcut
setlocal
call "%~dp0rocm.bat" status %*
exit /b %errorlevel%

