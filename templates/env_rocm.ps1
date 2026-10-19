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

# Idempotently update PATH
$existingPaths = $env:PATH -split ';'
$rocmPaths = @("$installDir\bin", "$installDir\python", "$installDir\python\Scripts")
$newPaths = @()
foreach ($p in $rocmPaths) {
    if ($existingPaths -notcontains $p) {
        $newPaths += $p
    }
}
if ($newPaths.Count -gt 0) {
    $env:PATH = ($newPaths -join ';') + ';' + $env:PATH
}

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
