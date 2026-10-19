@echo off
setlocal
call "%~dp0env_rocm.bat"
"%ROCM_ROOT%\python\python.exe" -m pip %*
exit /b %errorlevel%
