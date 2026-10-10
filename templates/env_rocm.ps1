# Sourced in current PowerShell session: . .\env_rocm.ps1
# Sets isolated process-level environment variables for the portable ROCm installation.

$installDir = $PSScriptRoot
if (-not $installDir) {
    $installDir = (Get-Location).Path
}

$env:PATH = "$installDir\python;$installDir\python\Scripts;$env:PATH"
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
}

foreach ($d in @("$installDir\.tmp", "$installDir\.cache\torch", "$installDir\.cache\huggingface", "$installDir\.cache\triton", "$installDir\.cache\miopen")) {
    if (-not (Test-Path -Path $d)) {
        New-Item -ItemType Directory -Force -Path $d | Out-Null
    }
}

Write-Host "Portable ROCm environment active. Python: $(Join-Path $installDir 'python\python.exe')" -ForegroundColor Green

