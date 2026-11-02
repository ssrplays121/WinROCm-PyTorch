<#
.SYNOPSIS
    WinROCm-PyTorch: Inspects and displays the current installation status and GPU details.

.DESCRIPTION
    Queries the isolated Python environment for installed package versions using fast
    pure-Python metadata inspection (avoiding slow GPU driver/runtime initialization),
    reads .rocm-portable.json, and inspects the host AMD GPU hardware.
#>

[CmdletBinding()]
param(
    [string]$InstallDir,
    [Alias("h")]
    [switch]$Help
)

if ($Help -or ($InstallDir -in @('-h', '-help', '--help', '/?', 'help'))) {
    Write-Host "`n==================== WINROCM: STATUS HELP ====================" -ForegroundColor Cyan
    Write-Host "Usage:"
    Write-Host "  setup.bat status"
    Write-Host "  rocm status"
    Write-Host "  powershell -File scripts\status.ps1 [-InstallDir <path>]"
    Write-Host "`nDescription:"
    Write-Host "  Inspects installation state (.rocm-portable.json), package versions via fast"
    Write-Host "  pure-Python metadata (importlib.metadata), AMD GPU display adapters, and"
    Write-Host "  constraints-rocm.txt package lock status."
    Write-Host "`nOptions:"
    Write-Host "  -InstallDir <path> Path to WinROCm installation directory."
    Write-Host "  -Help, -h          Display this help information."
    Write-Host "==============================================================`n" -ForegroundColor Cyan
    return
}

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = if ([string]::IsNullOrWhiteSpace($InstallDir)) {
    (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
} else {
    [System.IO.Path]::GetFullPath($InstallDir)
}

$stateFile = Join-Path $repoRoot ".rocm-portable.json"
$pythonDir = Join-Path $repoRoot "python"
$pythonExe = Join-Path $pythonDir "python.exe"
$constraintsFile = Join-Path $repoRoot "constraints-rocm.txt"

Write-Host "`n================== WINROCM STATUS ==================" -ForegroundColor Cyan
Write-Host "Install Directory : $repoRoot"

if (-not (Test-Path -Path $stateFile)) {
    Write-Host "Installation State: NOT DETECTED (No .rocm-portable.json found)" -ForegroundColor Yellow
    Write-Host "`nTo install WinROCm-PyTorch, run:" -ForegroundColor Gray
    Write-Host "  .\setup.bat install" -ForegroundColor White
    Write-Host "====================================================`n" -ForegroundColor Cyan
    return
}

$stateObj = $null
try {
    $stateObj = Get-Content -Path $stateFile -Raw | ConvertFrom-Json
} catch {
    Write-Warning "Failed to parse state file ($stateFile): $($_.Exception.Message)"
}

if ($stateObj) {
    Write-Host "State File        : Present (.rocm-portable.json)" -ForegroundColor Green
    Write-Host "Installer Version : $($stateObj.scriptVersion)"
    Write-Host "Configured Release: $($stateObj.rocmRelease)"
    Write-Host "Installed At (UTC): $($stateObj.installedAtUtc)"
}

# Python & Package Inspection via pure-Python importlib.metadata
if (Test-Path -Path $pythonExe) {
    Write-Host "`n--- Installed Components ---" -ForegroundColor Cyan

    $probePy = @"
import sys, importlib.metadata

packages = [
    'torch', 'torchvision', 'torchaudio',
    'rocm-sdk-core', 'rocm-sdk-devel', 'rocm-sdk-libraries-custom',
    'triton-windows', 'triton', 'pip'
]

print(f'python_version={sys.version.split()[0]}')
for p in packages:
    try:
        ver = importlib.metadata.version(p)
        print(f'{p}={ver}')
    except importlib.metadata.PackageNotFoundError:
        print(f'{p}=None')
"@
    try {
        $output = & $pythonExe -c $probePy 2>$null
        $pkgMap = @{}
        foreach ($line in $output) {
            $parts = $line -split '=', 2
            if ($parts.Count -eq 2) {
                $pkgMap[$parts[0].Trim()] = $parts[1].Trim()
            }
        }

        if ($pkgMap.ContainsKey('python_version')) {
            Write-Host ("  {0,-26} : {1}" -f "Python", $pkgMap['python_version'])
        }

        $displayList = @(
            @{ Label = "PyTorch (torch)"; Key = "torch" },
            @{ Label = "Torchvision"; Key = "torchvision" },
            @{ Label = "Torchaudio"; Key = "torchaudio" },
            @{ Label = "ROCm SDK Core"; Key = "rocm-sdk-core" },
            @{ Label = "ROCm SDK Devel"; Key = "rocm-sdk-devel" },
            @{ Label = "ROCm SDK Custom Libs"; Key = "rocm-sdk-libraries-custom" },
            @{ Label = "Triton Windows"; Key = "triton-windows" },
            @{ Label = "Pip"; Key = "pip" }
        )

        foreach ($item in $displayList) {
            $k = $item.Key
            $lbl = $item.Label
            $val = if ($pkgMap.ContainsKey($k)) { $pkgMap[$k] } else { "None" }
            if ($val -eq "None") {
                if ($k -eq "triton-windows" -and $pkgMap.ContainsKey("triton") -and $pkgMap["triton"] -ne "None") {
                    $val = $pkgMap["triton"]
                } else {
                    $val = "[Not Installed]"
                }
            }
            Write-Host ("  {0,-26} : {1}" -f $lbl, $val)
        }
    } catch {
        Write-Warning "Unable to query Python package metadata: $($_.Exception.Message)"
    }
} else {
    Write-Host "Python Executable : NOT FOUND at $pythonExe" -ForegroundColor Red
}

# GPU Hardware Detection
Write-Host "`n--- Detected Display Adapters ---" -ForegroundColor Cyan
try {
    $gpus = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
    if ($gpus) {
        foreach ($g in $gpus) {
            $isAmd = $g.Name -match 'AMD|Radeon'
            $color = if ($isAmd) { [ConsoleColor]::Green } else { [ConsoleColor]::Gray }
            Write-Host "  - $($g.Name)" -ForegroundColor $color
            if ($g.DriverVersion) {
                Write-Host "    Driver Version: $($g.DriverVersion)" -ForegroundColor Gray
            }
        }
    } else {
        Write-Host "  No display adapters detected via CIM." -ForegroundColor Gray
    }
} catch {
    Write-Host "  Unable to query video controllers: $($_.Exception.Message)" -ForegroundColor Gray
}

# Constraints check
if (Test-Path -Path $constraintsFile) {
    Write-Host "`nPackage Locks     : Active (constraints-rocm.txt present)" -ForegroundColor Green
} else {
    Write-Host "`nPackage Locks     : None (constraints-rocm.txt missing)" -ForegroundColor Yellow
}

Write-Host "====================================================`n" -ForegroundColor Cyan

