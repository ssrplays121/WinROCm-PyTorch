@echo off
rem WinROCm-PyTorch CLI & Bootstrapper
setlocal enabledelayedexpansion
cd /d "%~dp0"

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

if /i "%CMD%"=="install" goto do_install
if /i "%CMD%"=="-install" goto do_install
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
if /i "%CMD%"=="reinstall" goto do_reinstall
if /i "%CMD%"=="-reinstall" goto do_reinstall
if /i "%CMD%"=="diagnose" goto do_diagnose
if /i "%CMD%"=="-diagnose" goto do_diagnose

echo [ERROR] Unknown command '%CMD%'.
echo Run 'setup.bat -Help' or 'setup.bat help' to see available commands.
exit /b 1

:show_default
echo ================================================================================
echo   WinROCm-PyTorch: Portable AMD ROCm PyTorch Environment ^& Package Manager
echo ================================================================================
echo.
echo Run 'setup.bat -Help' or 'setup.bat help' to see available commands.
echo.
echo Quick Commands:
echo   setup.bat install       Install isolated ROCm PyTorch environment
echo   setup.bat update        Check for updates and interactively upgrade
echo   setup.bat update -y     Upgrade all packages non-interactively
echo   setup.bat check-update  Preview available updates without applying
echo   setup.bat status        Display current installation state and GPU info
echo   setup.bat verify        Run verification tests (GEMM, Conv2d, BatchNorm)
echo   setup.bat reinstall     Wipe and perform a fresh reinstall
echo   setup.bat diagnose      Generate diagnose.txt for troubleshooting
echo.
echo ================================================================================
exit /b 0

:show_help
echo ================================================================================
echo   WinROCm-PyTorch Command Line Reference
echo ================================================================================
echo Usage:
echo   setup.bat ^<command^> [options]
echo.
echo Commands:
echo   install       Install isolated Python, ROCm SDK, and PyTorch
echo   update        Check for updated configs/wheels and interactively upgrade
echo   check-update  Preview available candidate updates without modifying files
echo   status        Display current installation state, package versions, and GPU info
echo   verify        Run the verification test suite (verify_rocm.py)
echo   reinstall     Wipe existing environment and perform a fresh clean install
echo   diagnose      Collect system diagnostic telemetry into diagnose.txt
echo   help          Display this help message
echo.
echo Options:
echo   -y, -Yes      Non-interactive unattended mode (auto-confirm prompts)
echo   -WithTriton   Include triton-windows support for torch.compile
echo   -NoVision     Skip torchvision package
echo   -NoAudio      Skip torchaudio package
echo   -DryRun       Simulate installation plan and test URLs without downloading
echo.
echo Linux Package Manager Workflow Examples:
echo   setup.bat check-update              (like: dnf check-update / apt list --upgradable)
echo   setup.bat update                    (like: dnf update / apt upgrade)
echo   setup.bat update -y                 (like: dnf update -y)
echo   setup.bat install -WithTriton       (install with triton acceleration)
echo.
echo Once installed, run 'powershell -File scripts\add_to_path.ps1' to use 'rocm'
echo globally from ANY directory (e.g. 'rocm update', 'rocm status', 'rocm verify').
echo ================================================================================
exit /b 0

:do_install
if exist "%~dp0.rocm-portable.json" (
    echo [INFO] An existing WinROCm installation is already present in this directory.
    echo   - To check for and apply updates, run: setup.bat update
    echo   - To preview available updates, run  : setup.bat check-update
    echo   - To force a clean re-install, run   : setup.bat reinstall
    exit /b 0
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup_rocm_portable.ps1" -Install !REST_ARGS!
exit /b %errorlevel%

:do_update
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\update.ps1" !REST_ARGS!
exit /b %errorlevel%

:do_check_update
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\update.ps1" -CheckOnly !REST_ARGS!
exit /b %errorlevel%

:do_status
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\status.ps1" !REST_ARGS!
exit /b %errorlevel%

:do_verify
if exist "%~dp0bin\env_rocm.bat" (
    call "%~dp0bin\env_rocm.bat"
    "%~dp0python\python.exe" "%~dp0bin\verify_rocm.py" !REST_ARGS!
    exit /b %errorlevel%
)
echo [ERROR] WinROCm environment not found. Run 'setup.bat install' first.
exit /b 1

:do_reinstall
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup_rocm_portable.ps1" -Reinstall !REST_ARGS!
exit /b %errorlevel%

:do_diagnose
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup_rocm_portable.ps1" -Diagnose !REST_ARGS!
exit /b %errorlevel%
