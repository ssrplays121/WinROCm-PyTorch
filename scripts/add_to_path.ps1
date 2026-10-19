<#
.SYNOPSIS
    Adds the WinROCm-PyTorch bin/ directory to the current user's Windows PATH.

.DESCRIPTION
    Appends or prepends <InstallDir>\bin to the Windows User PATH environment variable.
    This makes launcher commands ('run_rocm', 'pip_rocm', 'torchrun_rocm', 'shell_rocm')
    globally accessible from any Command Prompt, PowerShell, or terminal window.
    Only the bin\ directory is added; global python and pip remain undisturbed.
    Does NOT require administrator privileges.
#>

[CmdletBinding()]
param(
    [string]$InstallDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = if ([string]::IsNullOrWhiteSpace($InstallDir)) {
    (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
} else {
    [System.IO.Path]::GetFullPath($InstallDir)
}

$binDir = Join-Path $repoRoot "bin"
if (-not (Test-Path -Path $binDir)) {
    throw "The 'bin' directory was not found at: $binDir. Please run setup first."
}

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$existingPaths = if ([string]::IsNullOrEmpty($userPath)) { @() } else { $userPath -split ';' | Where-Object { $_ -ne '' } }

if ($existingPaths -contains $binDir) {
    Write-Host "WinROCm-PyTorch is already present in your User PATH: $binDir" -ForegroundColor Yellow
    return
}

# Prepend binDir to User PATH
$newPaths = @($binDir) + $existingPaths
$newPathString = $newPaths -join ';'
[Environment]::SetEnvironmentVariable("Path", $newPathString, "User")

Write-Host "Successfully added WinROCm-PyTorch to your Windows User PATH:" -ForegroundColor Green
Write-Host "  + $binDir" -ForegroundColor Cyan
Write-Host "`nYou can now run the following commands from ANY terminal or directory:" -ForegroundColor Green
Write-Host "  - run_rocm script.py" -ForegroundColor Gray
Write-Host "  - pip_rocm install <package>" -ForegroundColor Gray
Write-Host "  - torchrun_rocm --nproc_per_node=1 train.py" -ForegroundColor Gray
Write-Host "  - shell_rocm" -ForegroundColor Gray
Write-Host "`nNote: Please restart any open terminal windows for the PATH changes to take effect." -ForegroundColor Yellow

