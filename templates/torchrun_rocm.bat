@echo off
setlocal
call "%~dp0env_rocm.bat"
"%ROCM_ROOT%\python\python.exe" -m torch.distributed.run %*
exit /b %errorlevel%

