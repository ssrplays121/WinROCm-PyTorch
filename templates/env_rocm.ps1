# Sourced in current PowerShell session: . .\bin\env_rocm.ps1 (or . .\env_rocm.ps1)
# Sets isolated process-level environment variables for the portable ROCm installation.

$scriptDir = $PSScriptRoot
if (-not $scriptDir) {
    $scriptDir = (Get-Location).Path
}

if (Test-Path -Path (Join-Path $scriptDir "..\python\python.exe")) {
    $installDir = (Resolve-Path (Join-Path $scriptDir "..")).Path
} else {
    $installDir = (Resolve-Path $scriptDir).Path
}

# Idempotently update PATH with strict DLL search precedence (ROCm/TheRock#5447)
$existingPaths = $env:PATH -split ';'
$rocmPaths = @(
    "$installDir\bin",
    "$installDir\python",
    "$installDir\python\Scripts",
    "$installDir\python\Lib\site-packages\_rocm_sdk_libraries_custom\bin",
    "$installDir\python\Lib\site-packages\_rocm_sdk_core\bin",
    "$installDir\python\Lib\site-packages\_rocm_sdk_devel\bin"
)
$newPaths = @()
foreach ($p in $rocmPaths) {
    if ($existingPaths -notcontains $p) {
        $newPaths += $p
    }
}
if ($newPaths.Count -gt 0) {
    $env:PATH = ($newPaths -join ';') + ';' + $env:PATH
}

# Configure Portable MSVC environment if present (ROCm / Triton acceleration)
$msvcSetupBat = Join-Path $installDir "msvc\setup_x64.bat"
if (Test-Path -Path $msvcSetupBat) {
    $msvcEnv = cmd.exe /c "call `"$msvcSetupBat`" >nul 2>&1 && set"
    foreach ($line in $msvcEnv) {
        $eqIdx = $line.IndexOf('=')
        if ($eqIdx -gt 0) {
            $k = $line.Substring(0, $eqIdx)
            $v = $line.Substring($eqIdx + 1)
            if ($k -in @("PATH", "INCLUDE", "LIB", "DISTUTILS_USE_SDK", "MSSdk", "VCToolsInstallDir", "WindowsSDKVersion")) {
                [Environment]::SetEnvironmentVariable($k, $v, "Process")
            }
        }
    }
    if ($env:INCLUDE) {
        $env:CPATH = $env:INCLUDE -replace '\\', '/'
        $env:CPLUS_INCLUDE_PATH = $env:INCLUDE -replace '\\', '/'
    }
}

$env:TORCH_BLAS_PREFER_HIPBLASLT = "1"
$rocmDevel = "$installDir\python\Lib\site-packages\_rocm_sdk_devel"
if (Test-Path -Path $rocmDevel) {
    $env:ROCM_PATH = $rocmDevel
    $env:HIP_PATH = $rocmDevel
}

# Optional TunableOp auto-tuning configuration
# $env:PYTORCH_TUNABLEOP_ENABLED = "1"
# $env:PYTORCH_TUNABLEOP_FILENAME = "$installDir\.cache\tunableop_results.csv"

# Optional MIOpen bypass toggle (uncomment if experiencing Conv2d workspace=0 slowdowns #3077)
# $env:ROCM_DISABLE_MIOPEN = "1"

$env:PYTHONNOUSERSITE = "1"
$env:TEMP = "$installDir\.tmp"
$env:TMP = "$installDir\.tmp"
$env:XDG_CACHE_HOME = "$installDir\.cache"
$env:TORCH_HOME = "$installDir\.cache\torch"
$env:HF_HOME = "$installDir\.cache\huggingface"
$env:TRITON_CACHE_DIR = "$installDir\.cache\triton"
$env:MIOPEN_USER_DB_PATH = "$installDir\.cache\miopen"
$env:MIOPEN_CUSTOM_CACHE_DIR = "$installDir\.cache\miopen"
$env:PIP_NO_CACHE_DIR = "1"
$env:PIP_CONFIG_FILE = "NUL"
$env:PIP_DISABLE_PIP_VERSION_CHECK = "1"

$constraintsPath = Join-Path $installDir "constraints-rocm.txt"
if (Test-Path -Path $constraintsPath) {
    $env:PIP_CONSTRAINT = $constraintsPath
} else {
    $env:PIP_CONSTRAINT = $null
}

foreach ($d in @("$installDir\.tmp", "$installDir\.cache\torch", "$installDir\.cache\huggingface", "$installDir\.cache\triton", "$installDir\.cache\miopen")) {
    if (-not (Test-Path -Path $d)) {
        New-Item -ItemType Directory -Force -Path $d | Out-Null
    }
}

# Optional GPU Architecture Overrides (uncomment for non-flagship / older GPUs):
# $env:HSA_OVERRIDE_GFX_VERSION = "11.0.0"  # For RX 7600, RX 7700 XT, RX 7800 XT (RDNA3)
# $env:HSA_OVERRIDE_GFX_VERSION = "10.3.0"  # For RX 6700, RX 6800, RX 6900 XT (RDNA2)

Write-Host "Portable ROCm environment active. Python: $(Join-Path $installDir 'python\python.exe')" -ForegroundColor Green
