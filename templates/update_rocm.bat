@echo off
rem WinROCm Update Shortcut
setlocal
call "%~dp0rocm.bat" update %*
exit /b %errorlevel%

