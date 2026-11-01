@echo off
rem WinROCm Unified System CLI
setlocal enabledelayedexpansion
for %%I in ("%~dp0..") do set "ROCM_ROOT=%%~fI"

set "CMD=%~1"

if "%CMD%"=="" goto show_default
if /i "%CMD%"=="help" goto show_help
if /i "%CMD%"=="-help" goto show_help
if /i "%CMD%"=="--help" goto show_help
if /i "%CMD%"=="-h" goto show_help
if /i "%CMD%"=="/?" goto show_help

shift
set "REST_ARGS="
:arg_loop
if "%~1"=="" goto arg_done
if /i "%~1"=="-y" (
    set "REST_ARGS=!REST_ARGS! -Yes"
) else (
    set "REST_ARGS=!REST_ARGS! %1"
)
shift
goto arg_loop
:arg_done

if /i "%CMD%"=="update" goto do_update
if /i "%CMD%"=="-update" goto do_update
if /i "%CMD%"=="check-update" goto do_check_update
if /i "%CMD%"=="check" goto do_check_update
if /i "%CMD%"=="-checkupdate" goto do_check_update
if /i "%CMD%"=="-check" goto do_check_update
if /i "%CMD%"=="status" goto do_status
if /i "%CMD%"=="info" goto do_status
if /i "%CMD%"=="-status" goto do_status
if /i "%CMD%"=="-info" goto do_status
if /i "%CMD%"=="verify" goto do_verify
if /i "%CMD%"=="-verify" goto do_verify
if /i "%CMD%"=="install" goto do_install
if /i "%CMD%"=="-install" goto do_install
if /i "%CMD%"=="reinstall" goto do_reinstall
if /i "%CMD%"=="-reinstall" goto do_reinstall
if /i "%CMD%"=="diagnose" goto do_diagnose
if /i "%CMD%"=="-diagnose" goto do_diagnose
if /i "%CMD%"=="run" goto do_run
if /i "%CMD%"=="pip" goto do_pip
if /i "%CMD%"=="shell" goto do_shell

echo [ERROR] Unknown command '%CMD%'.
echo Run 'rocm help' or 'rocm --help' to see available commands.
exit /b 1

:show_default
echo ================================================================================
echo   WinROCm-PyTorch: Portable AMD ROCm PyTorch Environment ^& Package Manager
echo ================================================================================
echo Install Directory: %ROCM_ROOT%
echo.
echo Run 'rocm help' to see all available commands.
echo.
echo Quick Commands:
echo   rocm status        Display installation state, packages, and GPU details
echo   rocm check-update  Preview available updates without modifying files
echo   rocm update        Check for updates and interactively upgrade
echo   rocm update -y     Upgrade all packages non-interactively
echo   rocm verify        Run verification tests (GEMM, Conv2d, BatchNorm)
echo   rocm shell         Open interactive isolated ROCm environment shell
echo   rocm run ^<script^>  Execute Python script in ROCm environment
echo   rocm pip ^<args^>    Run pip with constraints protection
echo ================================================================================
exit /b 0

:show_help
echo ================================================================================
echo   WinROCm System CLI Reference
echo ================================================================================
echo Usage:
echo   rocm ^<command^> [options]
echo.
echo Commands:
echo   status, info       Display current installation state, package versions, and GPU info
echo   check-update       Preview available candidate updates without modifying files
echo   update             Check for updated configs/wheels and interactively upgrade
echo   verify             Run the verification test suite (verify_rocm.py)
echo   shell              Launch an isolated CMD shell with ROCm environment active
echo   run ^<script.py^>    Run a Python script inside the isolated ROCm container
echo   pip ^<args^>         Run pip with constraints protection to prevent CUDA overwrites
echo   install            Install isolated ROCm PyTorch environment
echo   reinstall          Wipe existing environment and perform a fresh clean install
echo   diagnose           Collect system diagnostic telemetry into diagnose.txt
echo   help               Display this help message
echo.
echo Options:
echo   -y, -Yes           Non-interactive unattended mode (auto-confirm prompts)
echo   -WithTriton        Include triton-windows support
echo   -NoVision          Skip torchvision package
echo   -NoAudio           Skip torchaudio package
echo.
echo Package Manager Examples:
echo   rocm status
echo   rocm check-update
echo   rocm update
echo   rocm update -y
echo ================================================================================
exit /b 0

:do_update
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROCM_ROOT%\scripts\update.ps1" -InstallDir "%ROCM_ROOT%" !REST_ARGS!
exit /b %errorlevel%

:do_check_update
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROCM_ROOT%\scripts\update.ps1" -InstallDir "%ROCM_ROOT%" -CheckOnly !REST_ARGS!
exit /b %errorlevel%

:do_status
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROCM_ROOT%\scripts\status.ps1" -InstallDir "%ROCM_ROOT%" !REST_ARGS!
exit /b %errorlevel%

:do_verify
call "%~dp0env_rocm.bat"
"%ROCM_ROOT%\python\python.exe" "%~dp0verify_rocm.py" !REST_ARGS!
exit /b %errorlevel%

:do_run
call "%~dp0run_rocm.bat" !REST_ARGS!
exit /b %errorlevel%

:do_pip
call "%~dp0pip_rocm.bat" !REST_ARGS!
exit /b %errorlevel%

:do_shell
call "%~dp0shell_rocm.bat" !REST_ARGS!
exit /b %errorlevel%

:do_install
if exist "%ROCM_ROOT%\.rocm-portable.json" (
    echo [INFO] An existing WinROCm installation is already present in %ROCM_ROOT%.
    echo   - To check for and apply updates, run: rocm update
    echo   - To preview available updates, run  : rocm check-update
    echo   - To force a clean re-install, run   : rocm reinstall
    exit /b 0
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROCM_ROOT%\setup_rocm_portable.ps1" -Install -InstallDir "%ROCM_ROOT%" !REST_ARGS!
exit /b %errorlevel%

:do_reinstall
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROCM_ROOT%\setup_rocm_portable.ps1" -Reinstall -InstallDir "%ROCM_ROOT%" !REST_ARGS!
exit /b %errorlevel%

:do_diagnose
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROCM_ROOT%\setup_rocm_portable.ps1" -Diagnose -InstallDir "%ROCM_ROOT%" !REST_ARGS!
exit /b %errorlevel%

