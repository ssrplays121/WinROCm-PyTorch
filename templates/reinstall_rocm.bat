@echo off
rem WinROCm Reinstall Shortcut
setlocal
call "%~dp0rocm.bat" reinstall %*
exit /b %errorlevel%

