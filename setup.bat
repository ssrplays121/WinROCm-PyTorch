@echo off
rem WinROCm-PyTorch Bootstrapper
rem Usage:
rem   setup.bat                  (Interactive default install)
rem   setup.bat -Yes             (Non-interactive unattended install)
rem   setup.bat -WithTriton      (Install with triton-windows support)
rem   setup.bat -Diagnose        (Generate diagnose.txt)
rem   setup.bat -DryRun          (Check URLs and display plan)
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup_rocm_portable.ps1" %*
exit /b %errorlevel%
