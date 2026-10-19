<#
.SYNOPSIS
    Removes the WinROCm-PyTorch bin/ directory from the current user's Windows PATH.

.DESCRIPTION
    Safely removes <InstallDir>\bin and any legacy WinROCm directories from the
    Windows User PATH environment variable.
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
$pyDir = Join-Path $repoRoot "python"
$scriptsDir = Join-Path $repoRoot "python\Scripts"

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ([string]::IsNullOrEmpty($userPath)) {
    Write-Host "User PATH is empty. Nothing to remove." -ForegroundColor Yellow
    return
}

$paths = $userPath -split ';' | Where-Object { $_ -ne '' }
$cleanedPaths = $paths | Where-Object {
    $item = $_.TrimEnd('\')
    $item -ne $binDir.TrimEnd('\') -and $item -ne $pyDir.TrimEnd('\') -and $item -ne $scriptsDir.TrimEnd('\')
}

if ($cleanedPaths.Count -eq $paths.Count) {
    Write-Host "WinROCm-PyTorch entries were not found in your User PATH." -ForegroundColor Yellow
    return
}

$newPathString = $cleanedPaths -join ';'
[Environment]::SetEnvironmentVariable("Path", $newPathString, "User")

Write-Host "Successfully removed WinROCm-PyTorch from your Windows User PATH." -ForegroundColor Green
Write-Host "Note: Please restart any open terminal windows for changes to take effect." -ForegroundColor Yellow

