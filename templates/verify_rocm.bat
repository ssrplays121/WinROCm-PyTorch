@echo off
rem WinROCm Verify Shortcut
setlocal
call "%~dp0rocm.bat" verify %*
exit /b %errorlevel%

