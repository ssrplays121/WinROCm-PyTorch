@echo off
rem WinROCm-PyTorch CLI & Bootstrapper
setlocal enabledelayedexpansion
cd /d "%~dp0"

set "CMD=%~1"

rem Check top-level help invocation: setup.bat help [command]
if /i "%CMD%"=="help" goto route_top_help
if /i "%CMD%"=="-help" goto route_top_help
if /i "%CMD%"=="--help" goto route_top_help
if /i "%CMD%"=="-h" goto route_top_help
if /i "%CMD%"=="/?" goto route_top_help

rem If opened without any arguments, launch the interactive window of options
if "%CMD%"=="" goto interactive_menu

shift
set "REST_ARGS="
set "IS_HELP_REQ=0"

:arg_loop
if "%~1"=="" goto arg_done
if /i "%~1"=="help" set "IS_HELP_REQ=1"
if /i "%~1"=="-help" set "IS_HELP_REQ=1"
if /i "%~1"=="--help" set "IS_HELP_REQ=1"
if /i "%~1"=="-h" set "IS_HELP_REQ=1"
if /i "%~1"=="/?" set "IS_HELP_REQ=1"

if /i "%~1"=="-y" (
    set "REST_ARGS=!REST_ARGS! -Yes"
) else (
    set "REST_ARGS=!REST_ARGS! %1"
)
shift
goto arg_loop
:arg_done

rem Route commands with individual help checks
if /i "%CMD%"=="install" (
    if "!IS_HELP_REQ!"=="1" goto help_install
    goto do_install
)
if /i "%CMD%"=="-install" (
    if "!IS_HELP_REQ!"=="1" goto help_install
    goto do_install
)

if /i "%CMD%"=="update" (
    if "!IS_HELP_REQ!"=="1" goto help_update
    goto do_update
)
if /i "%CMD%"=="-update" (
    if "!IS_HELP_REQ!"=="1" goto help_update
    goto do_update
)

if /i "%CMD%"=="check-update" (
    if "!IS_HELP_REQ!"=="1" goto help_check_update
    goto do_check_update
)
if /i "%CMD%"=="check" (
    if "!IS_HELP_REQ!"=="1" goto help_check_update
    goto do_check_update
)
if /i "%CMD%"=="-checkupdate" (
    if "!IS_HELP_REQ!"=="1" goto help_check_update
    goto do_check_update
)
if /i "%CMD%"=="-check" (
    if "!IS_HELP_REQ!"=="1" goto help_check_update
    goto do_check_update
)

if /i "%CMD%"=="status" (
    if "!IS_HELP_REQ!"=="1" goto help_status
    goto do_status
)
if /i "%CMD%"=="info" (
    if "!IS_HELP_REQ!"=="1" goto help_status
    goto do_status
)
if /i "%CMD%"=="-status" (
    if "!IS_HELP_REQ!"=="1" goto help_status
    goto do_status
)
if /i "%CMD%"=="-info" (
    if "!IS_HELP_REQ!"=="1" goto help_status
    goto do_status
)

if /i "%CMD%"=="verify" (
    if "!IS_HELP_REQ!"=="1" goto help_verify
    goto do_verify
)
if /i "%CMD%"=="-verify" (
    if "!IS_HELP_REQ!"=="1" goto help_verify
    goto do_verify
)

if /i "%CMD%"=="reinstall" (
    if "!IS_HELP_REQ!"=="1" goto help_reinstall
    goto do_reinstall
)
if /i "%CMD%"=="-reinstall" (
    if "!IS_HELP_REQ!"=="1" goto help_reinstall
    goto do_reinstall
)

if /i "%CMD%"=="diagnose" (
    if "!IS_HELP_REQ!"=="1" goto help_diagnose
    goto do_diagnose
)
if /i "%CMD%"=="-diagnose" (
    if "!IS_HELP_REQ!"=="1" goto help_diagnose
    goto do_diagnose
)

echo [ERROR] Unknown command '%CMD%'.
echo Run 'setup.bat -Help' or 'setup.bat help' to see available commands.
exit /b 1

:route_top_help
set "SUB_CMD=%~2"
if /i "%SUB_CMD%"=="install" goto help_install
if /i "%SUB_CMD%"=="update" goto help_update
if /i "%SUB_CMD%"=="check-update" goto help_check_update
if /i "%SUB_CMD%"=="check" goto help_check_update
if /i "%SUB_CMD%"=="status" goto help_status
if /i "%SUB_CMD%"=="info" goto help_status
if /i "%SUB_CMD%"=="verify" goto help_verify
if /i "%SUB_CMD%"=="reinstall" goto help_reinstall
if /i "%SUB_CMD%"=="diagnose" goto help_diagnose
goto show_help

rem ============================================================================
rem   Interactive Window of Options (Main Menu & Submenus)
rem ============================================================================

:interactive_menu
cls 2>nul
echo ================================================================================
echo   WinROCm-PyTorch: Portable AMD ROCm PyTorch Environment ^& Package Manager
echo ================================================================================
if exist "%~dp0.rocm-portable.json" (
    echo   Environment Status : INSTALLED [active .rocm-portable.json found]
) else (
    echo   Environment Status : NOT INSTALLED
)
echo   Working Directory  : %~dp0
echo.
echo   Package Manager Options:
echo     1) Install       - Install isolated Python, ROCm SDK, and PyTorch
echo     2) Update        - Check for updates and interactively upgrade packages
echo     3) Check-Update  - Preview candidate updates without modifying files
echo     4) Status        - Display installation state, package versions, and GPU info
echo     5) Verify        - Run hardware validation tests (GEMM, Conv2d, BatchNorm)
echo     6) Reinstall     - Wipe existing environment and perform a fresh install
echo     7) Diagnose      - Collect diagnostic telemetry into diagnose.txt
echo     8) Help          - Command line reference and individual command help
echo     9) Exit
echo ================================================================================
set "MAIN_CHOICE="
set /p "MAIN_CHOICE=Select an option [1-9] (default 9): "
if not defined MAIN_CHOICE exit /b 0
set "MAIN_CHOICE=!MAIN_CHOICE: =!"
if "!MAIN_CHOICE!"=="" exit /b 0
if "!MAIN_CHOICE!"=="9" exit /b 0
if /i "!MAIN_CHOICE!"=="q" exit /b 0
if /i "!MAIN_CHOICE!"=="exit" exit /b 0

if "!MAIN_CHOICE!"=="1" goto submenu_install
if "!MAIN_CHOICE!"=="2" goto submenu_update
if "!MAIN_CHOICE!"=="3" (
    echo.
    call :do_check_update
    echo.
    echo Press any key to return to the main menu...
    pause >nul
    goto interactive_menu
)
if "!MAIN_CHOICE!"=="4" (
    echo.
    call :do_status
    echo.
    echo Press any key to return to the main menu...
    pause >nul
    goto interactive_menu
)
if "!MAIN_CHOICE!"=="5" (
    echo.
    call :do_verify
    echo.
    echo Press any key to return to the main menu...
    pause >nul
    goto interactive_menu
)
if "!MAIN_CHOICE!"=="6" goto submenu_reinstall
if "!MAIN_CHOICE!"=="7" (
    echo.
    call :do_diagnose
    echo.
    echo Press any key to return to the main menu...
    pause >nul
    goto interactive_menu
)
if "!MAIN_CHOICE!"=="8" goto submenu_help

echo [ERROR] Invalid choice '!MAIN_CHOICE!'. Please select 1 through 9.
ping -n 2 127.0.0.1 >nul 2>&1
goto interactive_menu

:submenu_install
cls 2>nul
echo ================================================================================
echo   WinROCm-PyTorch: Installation Options
echo ================================================================================
echo.
echo     1) Standard Installation (PyTorch + ROCm SDK + Vision + Audio)
echo     2) Install with Triton (Include triton-windows for torch.compile)
echo     3) Dry-Run (Simulate installation plan and test URLs without downloading)
echo     4) Install Help (View detailed options and parameter reference)
echo     5) Return to Main Menu
echo ================================================================================
set "INS_CHOICE="
set /p "INS_CHOICE=Select install option [1-5] (default 5): "
if not defined INS_CHOICE goto interactive_menu
set "INS_CHOICE=!INS_CHOICE: =!"
if "!INS_CHOICE!"=="" goto interactive_menu
if "!INS_CHOICE!"=="5" goto interactive_menu
if /i "!INS_CHOICE!"=="q" goto interactive_menu

if "!INS_CHOICE!"=="1" (
    echo.
    set "REST_ARGS="
    call :do_install
    echo.
    echo Press any key to return to the main menu...
    pause >nul
    goto interactive_menu
)
if "!INS_CHOICE!"=="2" (
    echo.
    set "REST_ARGS=-WithTriton"
    call :do_install
    echo.
    echo Press any key to return to the main menu...
    pause >nul
    goto interactive_menu
)
if "!INS_CHOICE!"=="3" (
    echo.
    set "REST_ARGS=-DryRun"
    call :do_install
    echo.
    echo Press any key to return to the main menu...
    pause >nul
    goto interactive_menu
)
if "!INS_CHOICE!"=="4" (
    echo.
    call :help_install
    echo.
    echo Press any key to return to the install menu...
    pause >nul
    goto submenu_install
)
echo [ERROR] Invalid choice '!INS_CHOICE!'.
ping -n 2 127.0.0.1 >nul 2>&1
goto submenu_install

:submenu_update
cls 2>nul
echo ================================================================================
echo   WinROCm-PyTorch: Package Manager Update Options
echo ================================================================================
echo.
echo     1) Interactive Update (Check candidate diffs and prompt before upgrading)
echo     2) Unattended Update (-y / non-interactive upgrade)
echo     3) Check Updates (Preview candidate diff table without modifying files)
echo     4) Update Help (View detailed package manager documentation)
echo     5) Return to Main Menu
echo ================================================================================
set "UPD_CHOICE="
set /p "UPD_CHOICE=Select update option [1-5] (default 5): "
if not defined UPD_CHOICE goto interactive_menu
set "UPD_CHOICE=!UPD_CHOICE: =!"
if "!UPD_CHOICE!"=="" goto interactive_menu
if "!UPD_CHOICE!"=="5" goto interactive_menu
if /i "!UPD_CHOICE!"=="q" goto interactive_menu

if "!UPD_CHOICE!"=="1" (
    echo.
    set "REST_ARGS="
    call :do_update
    echo.
    echo Press any key to return to the main menu...
    pause >nul
    goto interactive_menu
)
if "!UPD_CHOICE!"=="2" (
    echo.
    set "REST_ARGS=-Yes"
    call :do_update
    echo.
    echo Press any key to return to the main menu...
    pause >nul
    goto interactive_menu
)
if "!UPD_CHOICE!"=="3" (
    echo.
    set "REST_ARGS="
    call :do_check_update
    echo.
    echo Press any key to return to the main menu...
    pause >nul
    goto interactive_menu
)
if "!UPD_CHOICE!"=="4" (
    echo.
    call :help_update
    echo.
    echo Press any key to return to the update menu...
    pause >nul
    goto submenu_update
)
echo [ERROR] Invalid choice '!UPD_CHOICE!'.
ping -n 2 127.0.0.1 >nul 2>&1
goto submenu_update

:submenu_reinstall
cls 2>nul
echo ================================================================================
echo   WinROCm-PyTorch: Reinstall Environment
echo ================================================================================
echo   WARNING: Reinstall will wipe the existing .\python folder, state file,
echo   and package locks, then perform a fresh installation from verified packages.
echo.
echo     1) Confirm and Reinstall (Standard)
echo     2) Confirm and Reinstall with Triton
echo     3) Reinstall Help (View detailed documentation)
echo     4) Cancel and Return to Main Menu
echo ================================================================================
set "RE_CHOICE="
set /p "RE_CHOICE=Select reinstall option [1-4] (default 4): "
if not defined RE_CHOICE goto interactive_menu
set "RE_CHOICE=!RE_CHOICE: =!"
if "!RE_CHOICE!"=="" goto interactive_menu
if "!RE_CHOICE!"=="4" goto interactive_menu
if /i "!RE_CHOICE!"=="q" goto interactive_menu

if "!RE_CHOICE!"=="1" (
    echo.
    set "REST_ARGS="
    call :do_reinstall
    echo.
    echo Press any key to return to the main menu...
    pause >nul
    goto interactive_menu
)
if "!RE_CHOICE!"=="2" (
    echo.
    set "REST_ARGS=-WithTriton"
    call :do_reinstall
    echo.
    echo Press any key to return to the main menu...
    pause >nul
    goto interactive_menu
)
if "!RE_CHOICE!"=="3" (
    echo.
    call :help_reinstall
    echo.
    echo Press any key to return to the reinstall menu...
    pause >nul
    goto submenu_reinstall
)
echo [ERROR] Invalid choice '!RE_CHOICE!'.
ping -n 2 127.0.0.1 >nul 2>&1
goto submenu_reinstall

:submenu_help
cls 2>nul
echo ================================================================================
echo   WinROCm-PyTorch: Documentation ^& Command Help
echo ================================================================================
echo.
echo     1) General Command Line Reference
echo     2) Install Help
echo     3) Update Help
echo     4) Check-Update Help
echo     5) Status Help
echo     6) Verify Help
echo     7) Reinstall Help
echo     8) Diagnose Help
echo     9) Return to Main Menu
echo ================================================================================
set "HLP_CHOICE="
set /p "HLP_CHOICE=Select help topic [1-9] (default 9): "
if not defined HLP_CHOICE goto interactive_menu
set "HLP_CHOICE=!HLP_CHOICE: =!"
if "!HLP_CHOICE!"=="" goto interactive_menu
if "!HLP_CHOICE!"=="9" goto interactive_menu
if /i "!HLP_CHOICE!"=="q" goto interactive_menu

if "!HLP_CHOICE!"=="1" call :show_help
if "!HLP_CHOICE!"=="2" call :help_install
if "!HLP_CHOICE!"=="3" call :help_update
if "!HLP_CHOICE!"=="4" call :help_check_update
if "!HLP_CHOICE!"=="5" call :help_status
if "!HLP_CHOICE!"=="6" call :help_verify
if "!HLP_CHOICE!"=="7" call :help_reinstall
if "!HLP_CHOICE!"=="8" call :help_diagnose

echo.
echo Press any key to return to the help menu...
pause >nul
goto submenu_help

rem ============================================================================
rem   Individual Command Help Screens
rem ============================================================================

:show_help
echo ================================================================================
echo   WinROCm-PyTorch Command Line Reference
echo ================================================================================
echo Usage:
echo   setup.bat ^<command^> [options]
echo   setup.bat help ^<command^>
echo.
echo Commands:
echo   install       Install isolated Python, ROCm SDK, and PyTorch
echo   update        Check for updated configs/wheels and interactively upgrade
echo   check-update  Preview available candidate updates without modifying files
echo   status        Display current installation state, package versions, and GPU info
echo   verify        Run the verification test suite (verify_rocm.py)
echo   reinstall     Wipe existing environment and perform a fresh clean install
echo   diagnose      Collect system diagnostic telemetry into diagnose.txt
echo   help          Display this reference, or run 'setup.bat help ^<cmd^>' for topic help
echo.
echo Options:
echo   -y, -Yes      Non-interactive unattended mode (auto-confirm prompts)
echo   -WithTriton   Include triton-windows support for torch.compile
echo   -NoVision     Skip torchvision package
echo   -NoAudio      Skip torchaudio package
echo   -DryRun       Simulate installation plan and test URLs without downloading
echo.
echo Individual Help:
echo   Run 'setup.bat help ^<cmd^>' or 'setup.bat ^<cmd^> help' for detailed subcommand help.
echo   Examples:
echo     setup.bat help install
echo     setup.bat update --help
echo.
echo Global PATH Access:
echo   Run 'powershell -File scripts\add_to_path.ps1' to use 'rocm' globally from ANY
echo   terminal (e.g. 'rocm update', 'rocm status', 'rocm verify').
echo ================================================================================
exit /b 0

:help_install
echo ================================================================================
echo   WinROCm Command Help: INSTALL
echo ================================================================================
echo Purpose:
echo   Installs a self-contained, isolated Python 3.12 ROCm PyTorch runtime, official
echo   ROCm SDK libraries, MSVC C development headers (Python.h), and launcher scripts.
echo.
echo Usage:
echo   setup.bat install [options]
echo.
echo Options:
echo   -WithTriton         Download and install matching triton-windows wheel for torch.compile.
echo   -NoVision           Skip torchvision installation.
echo   -NoAudio            Skip torchaudio installation.
echo   -DryRun             Validate prerequisites and download URLs without downloading.
echo   -SkipGpuCheck       Bypass GPU hardware compatibility check.
echo   -SkipVerify         Skip post-installation hardware verification tests.
echo   -RocmRelease ^<ver^>  Target explicit ROCm release version (default: 7.2).
echo   -y, -Yes            Run unattended without interactive confirmation prompts.
echo   help, -h, --help    Display this help message.
echo.
echo Examples:
echo   setup.bat install
echo   setup.bat install -WithTriton
echo   setup.bat install -DryRun
echo ================================================================================
exit /b 0

:help_update
echo ================================================================================
echo   WinROCm Command Help: UPDATE (Linux Package Manager Workflow)
echo ================================================================================
echo Purpose:
echo   Checks for updated releases, wheels, and configurations from the upstream GitHub
echo   repository, compares installed packages against candidates, presents an interactive
echo   diff table, and applies targeted upgrades with confirmation (like 'dnf update').
echo.
echo Usage:
echo   setup.bat update [options]
echo.
echo Options:
echo   -y, -Yes            Non-interactive mode: automatically apply all available upgrades.
echo   -CheckOnly          Preview available updates without applying (same as check-update).
echo   -WithTriton         Ensure triton-windows is included during the upgrade.
echo   -RocmRelease ^<ver^>  Target explicit ROCm release version track.
echo   help, -h, --help    Display this help message.
echo.
echo Examples:
echo   setup.bat update             (interactively review package diffs and confirm)
echo   setup.bat update -y          (unattended, automated upgrade in CI/scripts)
echo ================================================================================
exit /b 0

:help_check_update
echo ================================================================================
echo   WinROCm Command Help: CHECK-UPDATE
echo ================================================================================
echo Purpose:
echo   Strictly non-destructive inspection comparing currently installed packages
echo   against the upstream repository catalog (like 'dnf check-update' / 'apt list').
echo   Outputs a formatted package status table showing current vs candidate versions.
echo   Does not download wheels or modify any files on disk.
echo.
echo Usage:
echo   setup.bat check-update
echo.
echo Aliases:
echo   setup.bat check
echo ================================================================================
exit /b 0

:help_status
echo ================================================================================
echo   WinROCm Command Help: STATUS
echo ================================================================================
echo Purpose:
echo   Inspects and displays current environment state, installed package versions,
echo   detected AMD display adapters, driver versions, and constraints locking status.
echo   Uses pure-Python metadata probing (importlib.metadata) for sub-second execution
echo   without slow GPU runtime initialization.
echo.
echo Usage:
echo   setup.bat status
echo.
echo Aliases:
echo   setup.bat info
echo ================================================================================
exit /b 0

:help_verify
echo ================================================================================
echo   WinROCm Command Help: VERIFY
echo ================================================================================
echo Purpose:
echo   Executes the comprehensive hardware verification test suite (verify_rocm.py)
echo   using the isolated Python environment.
echo.
echo Tests Run:
echo   1. GPU Matmul (GEMM) fp16 matrix multiplication
echo   2. GPU Conv2d latency benchmark and MIOpen workspace=0 cache bypass (#3077)
echo   3. BatchNorm2d on ^>32x32 tensors (MIOpen fallback to ATen kernels)
echo   4. F.normalize numerical stability in fp16
echo   5. Triton JIT compilation for torch.compile (if installed)
echo.
echo Usage:
echo   setup.bat verify
echo ================================================================================
exit /b 0

:help_reinstall
echo ================================================================================
echo   WinROCm Command Help: REINSTALL
echo ================================================================================
echo Purpose:
echo   Wipes the existing isolated 'python\' directory, state file (.rocm-portable.json),
echo   and package constraints (constraints-rocm.txt), then performs a clean, fresh
echo   installation from verified upstream packages (like 'dnf reinstall').
echo.
echo Usage:
echo   setup.bat reinstall [options]
echo.
echo Options:
echo   -WithTriton         Include triton-windows in the clean install.
echo   -NoVision           Skip torchvision.
echo   -NoAudio            Skip torchaudio.
echo   -y, -Yes            Non-interactive unattended mode.
echo   help, -h, --help    Display this help message.
echo.
echo Examples:
echo   setup.bat reinstall
echo   setup.bat reinstall -WithTriton -y
echo ================================================================================
exit /b 0

:help_diagnose
echo ================================================================================
echo   WinROCm Command Help: DIAGNOSE
echo ================================================================================
echo Purpose:
echo   Collects diagnostic system telemetry into 'diagnose.txt' for troubleshooting,
echo   hardware checks, and GitHub issue reports.
echo   Probes Windows build, PowerShell version, AMD GPU, display driver, MSVC C++
echo   tools, CPATH / PATH environment variables, and network connectivity.
echo   All personal paths and usernames are automatically redacted.
echo.
echo Usage:
echo   setup.bat diagnose
echo ================================================================================
exit /b 0

rem ============================================================================
rem   Execution Dispatchers
rem ============================================================================

:help_install
echo ================================================================================
echo   WinROCm Command Help: INSTALL
echo ================================================================================
echo Purpose:
echo   Installs a self-contained, isolated Python 3.12 ROCm PyTorch runtime, official
echo   ROCm SDK libraries, MSVC C development headers (Python.h), and launcher scripts.
echo.
echo Usage:
echo   setup.bat install [options]
echo.
echo Options:
echo   -WithTriton         Download and install matching triton-windows wheel for torch.compile.
echo   -NoVision           Skip torchvision installation.
echo   -NoAudio            Skip torchaudio installation.
echo   -DryRun             Validate prerequisites and download URLs without downloading.
echo   -SkipGpuCheck       Bypass GPU hardware compatibility check.
echo   -SkipVerify         Skip post-installation hardware verification tests.
echo   -RocmRelease ^<ver^>  Target explicit ROCm release version (default: 7.2).
echo   -y, -Yes            Run unattended without interactive confirmation prompts.
echo   help, -h, --help    Display this help message.
echo.
echo Examples:
echo   setup.bat install
echo   setup.bat install -WithTriton
echo   setup.bat install -DryRun
echo ================================================================================
exit /b 0

:help_update
echo ================================================================================
echo   WinROCm Command Help: UPDATE (Linux Package Manager Workflow)
echo ================================================================================
echo Purpose:
echo   Checks for updated releases, wheels, and configurations from the upstream GitHub
echo   repository, compares installed packages against candidates, presents an interactive
echo   diff table, and applies targeted upgrades with confirmation (like 'dnf update').
echo.
echo Usage:
echo   setup.bat update [options]
echo.
echo Options:
echo   -y, -Yes            Non-interactive mode: automatically apply all available upgrades.
echo   -CheckOnly          Preview available updates without applying (same as check-update).
echo   -WithTriton         Ensure triton-windows is included during the upgrade.
echo   -RocmRelease ^<ver^>  Target explicit ROCm release version track.
echo   help, -h, --help    Display this help message.
echo.
echo Examples:
echo   setup.bat update             (interactively review package diffs and confirm)
echo   setup.bat update -y          (unattended, automated upgrade in CI/scripts)
echo ================================================================================
exit /b 0

:help_check_update
echo ================================================================================
echo   WinROCm Command Help: CHECK-UPDATE
echo ================================================================================
echo Purpose:
echo   Strictly non-destructive inspection comparing currently installed packages
echo   against the upstream repository catalog (like 'dnf check-update' / 'apt list').
echo   Outputs a formatted package status table showing current vs candidate versions.
echo   Does not download wheels or modify any files on disk.
echo.
echo Usage:
echo   setup.bat check-update
echo.
echo Aliases:
echo   setup.bat check
echo ================================================================================
exit /b 0

:help_status
echo ================================================================================
echo   WinROCm Command Help: STATUS
echo ================================================================================
echo Purpose:
echo   Inspects and displays current environment state, installed package versions,
echo   detected AMD display adapters, driver versions, and constraints locking status.
echo   Uses pure-Python metadata probing (importlib.metadata) for sub-second execution
echo   without slow GPU runtime initialization.
echo.
echo Usage:
echo   setup.bat status
echo.
echo Aliases:
echo   setup.bat info
echo ================================================================================
exit /b 0

:help_verify
echo ================================================================================
echo   WinROCm Command Help: VERIFY
echo ================================================================================
echo Purpose:
echo   Executes the comprehensive hardware verification test suite (verify_rocm.py)
echo   using the isolated Python environment.
echo.
echo Tests Run:
echo   1. GPU Matmul (GEMM) fp16 matrix multiplication
echo   2. GPU Conv2d latency benchmark and MIOpen workspace=0 cache bypass (#3077)
echo   3. BatchNorm2d on >32x32 tensors (MIOpen fallback to ATen kernels)
echo   4. F.normalize numerical stability in fp16
echo   5. Triton JIT compilation for torch.compile (if installed)
echo.
echo Usage:
echo   setup.bat verify
echo ================================================================================
exit /b 0

:help_reinstall
echo ================================================================================
echo   WinROCm Command Help: REINSTALL
echo ================================================================================
echo Purpose:
echo   Wipes the existing isolated 'python\' directory, state file (.rocm-portable.json),
echo   and package constraints (constraints-rocm.txt), then performs a clean, fresh
echo   installation from verified upstream packages (like 'dnf reinstall').
echo.
echo Usage:
echo   setup.bat reinstall [options]
echo.
echo Options:
echo   -WithTriton         Include triton-windows in the clean install.
echo   -NoVision           Skip torchvision.
echo   -NoAudio            Skip torchaudio.
echo   -y, -Yes            Non-interactive unattended mode.
echo   help, -h, --help    Display this help message.
echo.
echo Examples:
echo   setup.bat reinstall
echo   setup.bat reinstall -WithTriton -y
echo ================================================================================
exit /b 0

:help_diagnose
echo ================================================================================
echo   WinROCm Command Help: DIAGNOSE
echo ================================================================================
echo Purpose:
echo   Collects diagnostic system telemetry into 'diagnose.txt' for troubleshooting,
echo   hardware checks, and GitHub issue reports.
echo   Probes Windows build, PowerShell version, AMD GPU, display driver, MSVC C++
echo   tools, CPATH / PATH environment variables, and network connectivity.
echo   All personal paths and usernames are automatically redacted.
echo.
echo Usage:
echo   setup.bat diagnose
echo ================================================================================
exit /b 0

rem ============================================================================
rem   Execution Dispatchers
rem ============================================================================

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
