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

if /i "%CMD%"=="triton" goto help_triton
if /i "%CMD%"=="-triton" goto help_triton
if /i "%CMD%"=="--triton" goto help_triton

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
if /i "%SUB_CMD%"=="triton" goto help_triton
goto show_help

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
echo   triton        Display guide on Triton ^& torch.compile acceleration
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
echo     setup.bat help triton
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
echo   -WithMsvc           Install or verify lightweight portable MSVC in .\msvc (~130 MB).
echo   -NoMsvc             Skip portable MSVC installation even if Triton is requested.
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

:help_triton
echo ================================================================================
echo   WinROCm Guide: TRITON ^& TORCH.COMPILE ACCELERATION
echo ================================================================================
echo What is Triton?
echo   Triton is an open-source compiler language and backend for deep learning.
echo   In PyTorch 2.0+, Triton is the default backend used by 'torch.compile()'
echo   to fuse GPU operations and generate optimized GPU kernels on the fly.
echo.
echo Why use Triton?
echo   - Speed: Yields 15%% to 50%%+ performance improvements in model inference and
echo     training for modern architectures (ComfyUI, Stable Diffusion, LLMs).
echo   - Without Triton, calling 'torch.compile(model)' will fail with an error
echo     indicating that Triton is not installed on Windows.
echo.
echo Do you need it?
echo   - NO if you only run standard PyTorch models in "eager mode" (default execution).
echo   - YES if you plan to run workloads utilizing 'torch.compile' acceleration.
echo.
echo System Requirements:
echo   - Microsoft Visual Studio 2022 or Build Tools with 'Desktop development with C++'
echo     workload installed (for MSVC C++ runtime JIT compilation).
echo   - Supported AMD GPU (RDNA3 / RDNA4 architecture, e.g. RX 7000 / 9000 series).
echo.
echo How to Install:
echo   - During initial install : setup.bat install -WithTriton (or choose [Y] in menu)
echo   - On existing install   : setup.bat update -WithTriton (or choose [Y] in menu)
echo   - Clean reinstall        : setup.bat reinstall -WithTriton
echo   - Via isolated pip       : bin\pip_rocm.bat install triton-windows
echo.
echo Verification:
echo   Run 'setup.bat verify' to run the verification suite, which includes a
echo   Triton JIT test if Triton is installed.
echo ================================================================================
exit /b 0

rem ============================================================================
rem   Interactive Action Menu
rem ============================================================================

:interactive_menu
set "EMPTY_COUNT=0"

:menu_loop
cls 2>nul
set "HAS_INSTALL=0"
set "HAS_TRITON=0"
set "HAS_MSVC=0"
set "ENV_STATUS=NOT INSTALLED"
set "TRITON_STATUS=NOT INSTALLED [torch.compile disabled]"
set "MSVC_STATUS=NOT DETECTED [safe eager ATen fallback]"
if exist "%~dp0.rocm-portable.json" (
    set "HAS_INSTALL=1"
    set "ENV_STATUS=INSTALLED [active .rocm-portable.json found]"
)
if exist "%~dp0python\Lib\site-packages\triton" (
    set "HAS_TRITON=1"
    set "TRITON_STATUS=INSTALLED [torch.compile active]"
)
if exist "%~dp0python\Lib\site-packages\triton_windows" (
    set "HAS_TRITON=1"
    set "TRITON_STATUS=INSTALLED [torch.compile active]"
)
for /d %%D in ("%~dp0python\Lib\site-packages\triton_windows-*") do (
    set "HAS_TRITON=1"
    set "TRITON_STATUS=INSTALLED [torch.compile active]"
)
if exist "%~dp0msvc\setup_x64.bat" (
    set "HAS_MSVC=1"
    set "MSVC_STATUS=INSTALLED [portable .\msvc]"
) else (
    for %%P in ("%ProgramFiles%" "%ProgramFiles(x86)%" "%ProgramW6432%") do (
        if exist "%%~P\Microsoft Visual Studio" (
            for /d %%V in ("%%~P\Microsoft Visual Studio\*\*\VC\Tools\MSVC\*") do (
                set "HAS_MSVC=1"
                set "MSVC_STATUS=INSTALLED [system Visual Studio]"
            )
        )
    )
)

echo ================================================================================
echo   WinROCm-PyTorch: Portable AMD ROCm PyTorch Environment ^& Package Manager
echo ================================================================================
echo   Environment Status : !ENV_STATUS!
echo   Triton Support     : !TRITON_STATUS!
echo   MSVC Toolchain     : !MSVC_STATUS!
echo   Working Directory  : %~dp0
echo.
echo   Select an action to perform:
echo     [1] Install       - Install isolated Python, ROCm SDK, and PyTorch
echo     [2] Update        - Check for updates and interactively upgrade packages
echo     [3] Check-Update  - Preview candidate updates without modifying files
echo     [4] Status        - Display installation state, package versions, and GPU info
echo     [5] Verify        - Run hardware validation tests (GEMM, Conv2d, BatchNorm)
echo     [6] Reinstall     - Wipe existing environment and perform a fresh clean install
echo     [7] Diagnose      - Collect diagnostic telemetry into diagnose.txt
echo     [8] Triton Info   - What is Triton, torch.compile, and do you need it?
echo     [9] Help          - Display command-line reference ^& documentation
echo     [0] Abort / Exit
echo ================================================================================
set "ACTION="
set /p "ACTION=Enter action [0-9] (0 to abort): "

if not defined ACTION (
    set /a EMPTY_COUNT+=1
    if !EMPTY_COUNT! geq 2 (
        echo [INFO] Exiting.
        exit /b 0
    )
    echo [INFO] No action selected. Enter 0 to abort, or 1 through 9.
    ping -n 2 127.0.0.1 >nul 2>&1
    goto menu_loop
)
set "EMPTY_COUNT=0"
set "ACTION=!ACTION: =!"

if "!ACTION!"=="0" (
    echo [INFO] Aborted by user.
    exit /b 0
)
if /i "!ACTION!"=="q" exit /b 0
if /i "!ACTION!"=="abort" exit /b 0
if /i "!ACTION!"=="exit" exit /b 0

if "!ACTION!"=="1" goto menu_action_install
if "!ACTION!"=="2" goto menu_action_update
if "!ACTION!"=="3" goto menu_action_check_update
if "!ACTION!"=="4" goto menu_action_status
if "!ACTION!"=="5" goto menu_action_verify
if "!ACTION!"=="6" goto menu_action_reinstall
if "!ACTION!"=="7" goto menu_action_diagnose
if "!ACTION!"=="8" goto menu_action_triton
if "!ACTION!"=="9" goto menu_action_help

echo [ERROR] Invalid choice '!ACTION!'. Please select 0 through 9.
ping -n 2 127.0.0.1 >nul 2>&1
goto menu_loop

:menu_action_install
echo.
if "!HAS_INSTALL!"=="0" goto do_first_install

echo [INFO] An existing WinROCm installation is already present in this directory.
if "!HAS_TRITON!"=="1" goto check_install_msvc_prompt

echo.
echo Triton Support is currently NOT INSTALLED [torch.compile disabled].
set "ADD_TRITON="
set /p "ADD_TRITON=Would you like to install Triton (triton-windows) now? [y/N]: "
if /i "!ADD_TRITON!"=="y" (
    echo.
    set "REST_ARGS=-WithTriton"
    call :do_update
    echo.
    echo Press any key to return to the main menu...
    pause >nul
    goto menu_loop
)

:check_install_msvc_prompt
if "!HAS_MSVC!"=="1" goto skip_install_triton_prompt

echo.
echo Portable MSVC is currently NOT INSTALLED [safe eager ATen fallback].
set "ADD_MSVC="
set /p "ADD_MSVC=Would you like to install Portable MSVC (~130 MB) for C++ acceleration? [y/N]: "
if /i "!ADD_MSVC!"=="y" (
    echo.
    set "REST_ARGS=-WithMsvc"
    call :do_update
    echo.
    echo Press any key to return to the main menu...
    pause >nul
    goto menu_loop
)

:skip_install_triton_prompt
echo   - To check for and apply updates, run action [2] Update
echo   - To preview available updates, run action  [3] Check-Update
echo   - To force a clean re-install, run action   [6] Reinstall
echo.
echo Press any key to return to the main menu...
pause >nul
goto menu_loop

:do_first_install
echo ================================================================================
echo   Triton Acceleration for PyTorch (torch.compile)
echo ================================================================================
echo   What is Triton?
echo     Triton is an optional compiler package that enables 'torch.compile' support
echo     for AMD GPUs on Windows. It delivers significant performance speedups
echo     (15%% to 50%%+) in ComfyUI, Stable Diffusion, and LLM inference.
echo.
echo   Do you need it?
echo     - Standard PyTorch runs fine without it in eager mode.
echo     - Choose YES if you plan to use 'torch.compile' acceleration.
echo.
echo   Prerequisite:
echo     Compiling kernels with Triton requires Visual Studio C++ Build Tools (MSVC).
echo ================================================================================
set "WANT_TRITON="
set /p "WANT_TRITON=Install Triton (triton-windows) for torch.compile acceleration? [y/N]: "
set "REST_ARGS="
if /i "!WANT_TRITON!"=="y" set "REST_ARGS=-WithTriton"
echo.
call :do_install
echo.
echo Press any key to return to the main menu...
pause >nul
goto menu_loop

:menu_action_update
echo.
set "REST_ARGS="
call :do_update
echo.
echo Press any key to return to the main menu...
pause >nul
goto menu_loop

:menu_action_check_update
echo.
set "REST_ARGS="
call :do_check_update
echo.
echo Press any key to return to the main menu...
pause >nul
goto menu_loop

:menu_action_status
echo.
set "REST_ARGS="
call :do_status
echo.
echo Press any key to return to the main menu...
pause >nul
goto menu_loop

:menu_action_verify
echo.
set "REST_ARGS="
call :do_verify
echo.
echo Press any key to return to the main menu...
pause >nul
goto menu_loop

:menu_action_reinstall
echo.
echo ================================================================================
echo   WinROCm-PyTorch: Reinstall Environment
echo ================================================================================
echo   WARNING: Reinstall will wipe the existing .\python folder, state file,
echo   and package locks, then perform a fresh installation from verified packages.
echo ================================================================================
set "CONFIRM_RE="
set /p "CONFIRM_RE=Are you sure you want to wipe and perform a clean reinstall? [y/N]: "
if /i not "!CONFIRM_RE!"=="y" (
    echo [INFO] Reinstall cancelled.
    echo.
    echo Press any key to return to the main menu...
    pause >nul
    goto menu_loop
)

echo.
set "WANT_TRITON_RE="
set /p "WANT_TRITON_RE=Include Triton (triton-windows) in the clean reinstall? [y/N]: "
set "REST_ARGS="
if /i "!WANT_TRITON_RE!"=="y" set "REST_ARGS=-WithTriton"
echo.
call :do_reinstall
echo.
echo Press any key to return to the main menu...
pause >nul
goto menu_loop

:menu_action_diagnose
echo.
set "REST_ARGS="
call :do_diagnose
echo.
echo Press any key to return to the main menu...
pause >nul
goto menu_loop

:menu_action_triton
echo.
call :help_triton
if "!HAS_INSTALL!"=="0" goto menu_action_triton_done

if "!HAS_TRITON!"=="0" (
    echo.
    echo --------------------------------------------------------------------------------
    set "INSTALL_TRITON_NOW="
    set /p "INSTALL_TRITON_NOW=Would you like to install Triton (triton-windows) now? [y/N]: "
    if /i "!INSTALL_TRITON_NOW!"=="y" (
        echo.
        set "REST_ARGS=-WithTriton"
        call :do_update
    )
)

if "!HAS_MSVC!"=="0" (
    echo.
    echo --------------------------------------------------------------------------------
    set "INSTALL_MSVC_NOW="
    set /p "INSTALL_MSVC_NOW=Would you like to install Portable MSVC (~130 MB) now? [y/N]: "
    if /i "!INSTALL_MSVC_NOW!"=="y" (
        echo.
        set "REST_ARGS=-WithMsvc"
        call :do_update
    )
)

:menu_action_triton_done
echo.
echo Press any key to return to the main menu...
pause >nul
goto menu_loop

:menu_action_help
echo.
call :show_help
echo.
echo Press any key to return to the main menu...
pause >nul
goto menu_loop

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
