@echo off
setlocal
call "%~dp0env_rocm.bat"
"%~dp0python\python.exe" %*
exit /b %errorlevel%

