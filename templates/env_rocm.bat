@echo off
rem WinROCm-PyTorch Isolated Environment Configuration
rem Resolves installation root (parent of bin/ if placed inside bin/, or current directory if at root)
if exist "%~dp0..\python\python.exe" (
    for %%I in ("%~dp0..") do set "ROCM_ROOT=%%~fI"
) else (
    for %%I in ("%~dp0.") do set "ROCM_ROOT=%%~fI"
)

rem Idempotently prepend isolated paths to PATH with strict DLL search precedence (ROCm/TheRock#5447)
echo ";%PATH%;" | findstr /i /c:";%ROCM_ROOT%\python;" >nul
if errorlevel 1 (
    set "PATH=%ROCM_ROOT%\bin;%ROCM_ROOT%\python;%ROCM_ROOT%\python\Scripts;%ROCM_ROOT%\python\Lib\site-packages\_rocm_sdk_libraries_custom\bin;%ROCM_ROOT%\python\Lib\site-packages\_rocm_sdk_core\bin;%ROCM_ROOT%\python\Lib\site-packages\_rocm_sdk_devel\bin;%PATH%"
)

set "TORCH_BLAS_PREFER_HIPBLASLT=1"
if exist "%ROCM_ROOT%\python\Lib\site-packages\_rocm_sdk_devel" (
    set "ROCM_PATH=%ROCM_ROOT%\python\Lib\site-packages\_rocm_sdk_devel"
    set "HIP_PATH=%ROCM_ROOT%\python\Lib\site-packages\_rocm_sdk_devel"
)

rem Optional TunableOp auto-tuning configuration
rem set "PYTORCH_TUNABLEOP_ENABLED=1"
rem set "PYTORCH_TUNABLEOP_FILENAME=%ROCM_ROOT%\.cache\tunableop_results.csv"

rem Optional MIOpen bypass toggle (uncomment if experiencing Conv2d workspace=0 slowdowns #3077)
rem set "ROCM_DISABLE_MIOPEN=1"

set "PYTHONNOUSERSITE=1"
set "TEMP=%ROCM_ROOT%\.tmp"
set "TMP=%ROCM_ROOT%\.tmp"
set "XDG_CACHE_HOME=%ROCM_ROOT%\.cache"
set "TORCH_HOME=%ROCM_ROOT%\.cache\torch"
set "HF_HOME=%ROCM_ROOT%\.cache\huggingface"
set "TRITON_CACHE_DIR=%ROCM_ROOT%\.cache\triton"
set "MIOPEN_USER_DB_PATH=%ROCM_ROOT%\.cache\miopen"
set "MIOPEN_CUSTOM_CACHE_DIR=%ROCM_ROOT%\.cache\miopen"
set "PIP_NO_CACHE_DIR=1"
set "PIP_CONFIG_FILE=NUL"
set "PIP_DISABLE_PIP_VERSION_CHECK=1"

if exist "%ROCM_ROOT%\constraints-rocm.txt" (
    set "PIP_CONSTRAINT=%ROCM_ROOT%\constraints-rocm.txt"
) else (
    set "PIP_CONSTRAINT="
)

if not exist "%ROCM_ROOT%\.tmp" mkdir "%ROCM_ROOT%\.tmp"
if not exist "%ROCM_ROOT%\.cache\torch" mkdir "%ROCM_ROOT%\.cache\torch"
if not exist "%ROCM_ROOT%\.cache\huggingface" mkdir "%ROCM_ROOT%\.cache\huggingface"
if not exist "%ROCM_ROOT%\.cache\triton" mkdir "%ROCM_ROOT%\.cache\triton"
if not exist "%ROCM_ROOT%\.cache\miopen" mkdir "%ROCM_ROOT%\.cache\miopen"

rem Optional GPU Architecture Overrides (uncomment for non-flagship or older GPUs):
rem set "HSA_OVERRIDE_GFX_VERSION=11.0.0"
rem set "HSA_OVERRIDE_GFX_VERSION=10.3.0"
