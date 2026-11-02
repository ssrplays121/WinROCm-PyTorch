@echo off
rem WinROCm Unified System CLI & Package Manager
setlocal enabledelayedexpansion
for %%I in ("%~dp0..") do set "ROCM_ROOT=%%~fI"

set "CMD=%~1"

rem Check top-level help invocation: rocm help [command]
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

if /i "%CMD%"=="update" (
    if "!IS_HELP_REQ!"=="1" goto help_update
    goto do_update
)
if /i "%CMD%"=="-update" (
    if "!IS_HELP_REQ!"=="1" goto help_update
    goto do_update
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

if /i "%CMD%"=="install" (
    if "!IS_HELP_REQ!"=="1" goto help_install
    goto do_install
)
if /i "%CMD%"=="-install" (
    if "!IS_HELP_REQ!"=="1" goto help_install
    goto do_install
)

if /i "%CMD%"=="diagnose" (
    if "!IS_HELP_REQ!"=="1" goto help_diagnose
    goto do_diagnose
)
if /i "%CMD%"=="-diagnose" (
    if "!IS_HELP_REQ!"=="1" goto help_diagnose
    goto do_diagnose
)

if /i "%CMD%"=="run" (
    if "!IS_HELP_REQ!"=="1" goto help_run
    goto do_run
)
if /i "%CMD%"=="pip" (
    if "!IS_HELP_REQ!"=="1" goto help_pip
    goto do_pip
)
if /i "%CMD%"=="shell" (
    if "!IS_HELP_REQ!"=="1" goto help_shell
    goto do_shell
)

echo [ERROR] Unknown command '%CMD%'.
echo Run 'rocm help' or 'rocm --help' to see available commands.
exit /b 1

:route_top_help
set "SUB_CMD=%~2"
if /i "%SUB_CMD%"=="status" goto help_status
if /i "%SUB_CMD%"=="info" goto help_status
if /i "%SUB_CMD%"=="check-update" goto help_check_update
if /i "%SUB_CMD%"=="check" goto help_check_update
if /i "%SUB_CMD%"=="update" goto help_update
if /i "%SUB_CMD%"=="verify" goto help_verify
if /i "%SUB_CMD%"=="reinstall" goto help_reinstall
if /i "%SUB_CMD%"=="install" goto help_install
if /i "%SUB_CMD%"=="diagnose" goto help_diagnose
if /i "%SUB_CMD%"=="run" goto help_run
if /i "%SUB_CMD%"=="pip" goto help_pip
if /i "%SUB_CMD%"=="shell" goto help_shell
goto show_help

rem ============================================================================
rem   Interactive Window of Options (Main Menu & Submenus)
rem ============================================================================

:interactive_menu
cls 2>nul
echo ================================================================================
echo   WinROCm-PyTorch: System CLI ^& Package Manager
echo ================================================================================
echo   Install Directory : %ROCM_ROOT%
if exist "%ROCM_ROOT%\.rocm-portable.json" (
    echo   Environment Status: INSTALLED [active .rocm-portable.json found]
) else (
    echo   Environment Status: NOT INSTALLED
)
echo.
echo   Package Manager Options:
echo     1) Status        - View package versions, environment state, and GPU details
echo     2) Check-Update  - Preview candidate updates without modifying files
echo     3) Update        - Check for updates and interactively upgrade packages
echo     4) Verify        - Run GPU validation tests (GEMM, Conv2d, BatchNorm)
echo     5) Shell         - Launch interactive ROCm command prompt
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

if "!MAIN_CHOICE!"=="1" (
    echo.
    call :do_status
    echo.
    echo Press any key to return to the main menu...
    pause >nul
    goto interactive_menu
)
if "!MAIN_CHOICE!"=="2" (
    echo.
    call :do_check_update
    echo.
    echo Press any key to return to the main menu...
    pause >nul
    goto interactive_menu
)
if "!MAIN_CHOICE!"=="3" goto submenu_update
if "!MAIN_CHOICE!"=="4" (
    echo.
    call :do_verify
    echo.
    echo Press any key to return to the main menu...
    pause >nul
    goto interactive_menu
)
if "!MAIN_CHOICE!"=="5" (
    echo.
    call :do_shell
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

:submenu_update
cls 2>nul
echo ================================================================================
echo   WinROCm: Package Manager Update Options
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
echo   WinROCm: Reinstall Environment
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
echo   WinROCm: Documentation ^& Command Help
echo ================================================================================
echo.
echo     1) General Command Line Reference
echo     2) Status Help
echo     3) Check-Update Help
echo     4) Update Help
echo     5) Verify Help
echo     6) Reinstall Help
echo     7) Run / Pip / Shell Help
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
if "!HLP_CHOICE!"=="2" call :help_status
if "!HLP_CHOICE!"=="3" call :help_check_update
if "!HLP_CHOICE!"=="4" call :help_update
if "!HLP_CHOICE!"=="5" call :help_verify
if "!HLP_CHOICE!"=="6" call :help_reinstall
if "!HLP_CHOICE!"=="7" (
    call :help_run
    call :help_pip
    call :help_shell
)
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
echo   WinROCm-PyTorch Unified System CLI Reference
echo ================================================================================
echo Usage:
echo   rocm ^<command^> [options]
echo   rocm help ^<command^>
echo.
echo Package Manager Commands:
echo   status, info       Display current installation state, package versions, and GPU info
echo   check-update       Preview available candidate updates without modifying files
echo   update             Check for updated configs/wheels and interactively upgrade
echo   verify             Run the verification test suite (verify_rocm.py)
echo   reinstall          Wipe existing environment and perform a fresh clean install
echo   install            Install isolated ROCm PyTorch environment
echo   diagnose           Collect system diagnostic telemetry into diagnose.txt
echo.
echo Runtime Execution Commands:
echo   shell              Launch an isolated CMD shell with ROCm environment active
echo   run ^<script.py^>    Run a Python script inside the isolated ROCm container
echo   pip ^<args^>         Run pip with constraints protection to prevent CUDA overwrites
echo   help               Display this reference, or run 'rocm help ^<cmd^>' for topic help
echo.
echo Options:
echo   -y, -Yes           Non-interactive unattended mode (auto-confirm prompts)
echo   -WithTriton        Include triton-windows support
echo   -NoVision          Skip torchvision package
echo   -NoAudio           Skip torchaudio package
echo.
echo Individual Help:
echo   Run 'rocm help ^<cmd^>' or 'rocm ^<cmd^> help' for detailed subcommand help.
echo   Examples:
echo     rocm help update
echo     rocm reinstall --help
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
echo   rocm status
echo.
echo Aliases:
echo   rocm info
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
echo   rocm check-update
echo.
echo Aliases:
echo   rocm check
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
echo   rocm update [options]
echo.
echo Options:
echo   -y, -Yes            Non-interactive mode: automatically apply all available upgrades.
echo   -CheckOnly          Preview available updates without applying (same as check-update).
echo   -WithTriton         Ensure triton-windows is included during the upgrade.
echo   -RocmRelease ^<ver^>  Target explicit ROCm release version track.
echo   help, -h, --help    Display this help message.
echo.
echo Examples:
echo   rocm update             (interactively review package diffs and confirm)
echo   rocm update -y          (unattended, automated upgrade in CI/scripts)
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
echo   rocm verify
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
echo   rocm reinstall [options]
echo.
echo Options:
echo   -WithTriton         Include triton-windows in the clean install.
echo   -NoVision           Skip torchvision.
echo   -NoAudio            Skip torchaudio.
echo   -y, -Yes            Non-interactive unattended mode.
echo   help, -h, --help    Display this help message.
echo.
echo Examples:
echo   rocm reinstall
echo   rocm reinstall -WithTriton -y
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
echo   rocm install [options]
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
echo   rocm diagnose
echo ================================================================================
exit /b 0

:help_run
echo ================================================================================
echo   WinROCm Command Help: RUN
echo ================================================================================
echo Purpose:
echo   Executes any Python script within the isolated WinROCm runtime environment.
echo   Ensures AMD ROCm libraries, HIPBLASLt tuning, and isolated Python are active.
echo.
echo Usage:
echo   rocm run ^<script.py^> [arguments]
echo ================================================================================
exit /b 0

:help_pip
echo ================================================================================
echo   WinROCm Command Help: PIP
echo ================================================================================
echo Purpose:
echo   Runs pip package manager within the isolated environment. Automatically enforces
echo   'constraints-rocm.txt' to guarantee PyTorch cannot be accidentally overwritten
echo   by upstream CUDA wheels.
echo.
echo Usage:
echo   rocm pip install ^<package^>
echo   rocm pip list
echo ================================================================================
exit /b 0

:help_shell
echo ================================================================================
echo   WinROCm Command Help: SHELL
echo ================================================================================
echo Purpose:
echo   Launches an interactive Command Prompt session pre-configured with all WinROCm
echo   environment variables, library paths, and compiler discovery shims.
echo.
echo Usage:
echo   rocm shell
echo ================================================================================
exit /b 0

rem ============================================================================
rem   Execution Dispatchers
rem ============================================================================

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
