<#
.SYNOPSIS
    WinROCm-PyTorch: Linux package manager-style update engine (dnf/apt workflow).

.DESCRIPTION
    Checks for updated releases, wheels, and configurations from upstream repository,
    compares against the installed environment, presents an interactive diff table,
    and applies targeted upgrades with confirmation.
#>

[CmdletBinding()]
param(
    [string]$InstallDir,
    [string]$RocmRelease,
    [switch]$CheckOnly,
    [Alias("y")]
    [switch]$Yes,
    [switch]$WithTriton,
    [switch]$WithMsvc,
    [switch]$NoMsvc,
    [Alias("h")]
    [switch]$Help
)

if ($Help -or ($InstallDir -in @('-h', '-help', '--help', '/?', 'help'))) {
    Write-Host "`n================ WINROCM PACKAGE MANAGER: UPDATE HELP ================" -ForegroundColor Cyan
    Write-Host "Usage:"
    Write-Host "  setup.bat update [options]"
    Write-Host "  rocm update [options]"
    Write-Host "  powershell -File scripts\update.ps1 [-InstallDir <path>] [options]"
    Write-Host "`nDescription:"
    Write-Host "  Synchronizes remote package catalog from GitHub, inspects currently installed"
    Write-Host "  Python package versions via pure-Python metadata, compares against upstream"
    Write-Host "  candidates, presents an interactive diff table, and applies targeted upgrades."
    Write-Host "`nOptions:"
    Write-Host "  -CheckOnly        Preview candidate updates without downloading or modifying files."
    Write-Host "  -y, -Yes          Unattended mode: automatically apply updates without prompting."
    Write-Host "  -WithTriton       Include matching triton-windows wheel for torch.compile support."
    Write-Host "  -WithMsvc         Install or verify lightweight portable MSVC in .\msvc (~130 MB)."
    Write-Host "  -NoMsvc           Skip portable MSVC installation even if Triton is requested."
    Write-Host "  -RocmRelease <v>  Target specific release version track (e.g. 7.2, 7.2.1)."
    Write-Host "  -Help, -h         Display this help information."
    Write-Host "======================================================================`n" -ForegroundColor Cyan
    return
}

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Polyfill Import-PowerShellDataFile for Windows PowerShell 5.1 environments where the cmdlet is not built-in
if (-not (Get-Command Import-PowerShellDataFile -ErrorAction SilentlyContinue)) {
    function global:Import-PowerShellDataFile {
        param([string]$Path)
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$parseErrors)
        if ($parseErrors -and $parseErrors.Count -gt 0) {
            throw "Failed to parse data file at $Path : $($parseErrors[0].Message)"
        }
        $data = $ast.Find({ $args[0] -is [System.Management.Automation.Language.HashtableAst] }, $false)
        if ($data) {
            return $data.SafeGetValue()
        }
        throw "No hashtable root found in data file: $Path"
    }
}

# Ensure TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$repoRoot = if ([string]::IsNullOrWhiteSpace($InstallDir)) {
    (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
} else {
    [System.IO.Path]::GetFullPath($InstallDir)
}

$stateFile       = Join-Path $repoRoot ".rocm-portable.json"
$configPath      = Join-Path $repoRoot "config\releases.psd1"
$pythonDir       = Join-Path $repoRoot "python"
$pythonExe       = Join-Path $pythonDir "python.exe"
$constraintsFile = Join-Path $repoRoot "constraints-rocm.txt"
$templateDir     = Join-Path $repoRoot "templates"
$binDir          = Join-Path $repoRoot "bin"
$msvcDir         = Join-Path $repoRoot "msvc"
$tmpDir          = Join-Path $repoRoot ".tmp"
$cacheDir        = Join-Path $repoRoot ".cache"

Write-Host "`n================== WINROCM PACKAGE MANAGER ==================" -ForegroundColor Cyan
Write-Host "Install Directory : $repoRoot"

if (-not (Test-Path -Path $stateFile)) {
    Write-Host "Installation State: NOT DETECTED" -ForegroundColor Yellow
    Write-Host "No active installation found in '$repoRoot'." -ForegroundColor Yellow
    Write-Host "To install WinROCm-PyTorch for the first time, run:" -ForegroundColor Gray
    Write-Host "  .\setup.bat install`n" -ForegroundColor White
    return
}

# 1. Read Current State
$stateObj = $null
try {
    $stateObj = Get-Content -Path $stateFile -Raw | ConvertFrom-Json
} catch {
    Write-Warning "Failed to parse state file ($stateFile): $($_.Exception.Message)"
}
$installedRelease = if ($stateObj -and $stateObj.rocmRelease) { [string]$stateObj.rocmRelease } else { "7.2" }

# 2. Synchronize Remote Config (with local fallback)
Write-Host "`n==> Synchronizing package catalog..." -ForegroundColor Yellow
$localConfig = Import-PowerShellDataFile -Path $configPath
$activeConfig = $localConfig
$remoteUrl = "https://raw.githubusercontent.com/ssrplays121/WinROCm-PyTorch/main/config/releases.psd1"

$remoteUpdatedText = $null
try {
    $resp = $null
    $stream = $null
    $reader = $null
    try {
        $webReq = [System.Net.HttpWebRequest]::Create($remoteUrl)
        $webReq.Timeout = 3000
        $webReq.Method = "GET"
        $webReq.UserAgent = "WinROCm-PackageManager"
        $resp = $webReq.GetResponse()
        $stream = $resp.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $remoteText = $reader.ReadToEnd()
        if ($remoteText -match "DefaultRelease" -and $remoteText -match "Releases") {
            $remotePsd1 = Join-Path $tmpDir "remote_releases.psd1"
            if (-not (Test-Path -Path $tmpDir)) { New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null }
            Set-Content -Path $remotePsd1 -Value $remoteText -Encoding UTF8
            $remoteConfig = Import-PowerShellDataFile -Path $remotePsd1
            Remove-Item -Path $remotePsd1 -Force -ErrorAction SilentlyContinue
            $activeConfig = $remoteConfig
            $remoteUpdatedText = $remoteText
            Write-Host "  [Sync] Upstream repository catalog synchronized from GitHub." -ForegroundColor Green
        }
    } finally {
        if ($null -ne $reader) { $reader.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
        if ($null -ne $resp)   { $resp.Dispose() }
    }
} catch {
    Write-Host "  [Sync] Upstream catalog check skipped/offline; using local catalog." -ForegroundColor Gray
}

# 3. Determine Candidate Release
$releases = $activeConfig['Releases']
$allReleaseKeys = @($releases.Keys | Sort-Object {
    try { [version]$_ } catch { [version]"0.0" }
})

$candidateRelease = if (-not [string]::IsNullOrWhiteSpace($RocmRelease)) {
    $RocmRelease.Trim()
} elseif ($allReleaseKeys.Count -gt 0) {
    # Default to newest release available in catalog
    $allReleaseKeys[-1]
} else {
    [string]$activeConfig['DefaultRelease']
}

if (-not $releases.ContainsKey($candidateRelease)) {
    Write-Host "[ERROR] Unknown ROCm release '$candidateRelease'. Available: $($allReleaseKeys -join ', ')" -ForegroundColor Red
    return
}

$candCfg = $releases[$candidateRelease]
$baseUrl = $candCfg['BaseUrl']

# 4. Helper: Extract Wheel Version from filename
function Get-WheelVersion {
    param([string]$Filename)
    $unescaped = [System.Uri]::UnescapeDataString($Filename)
    if ($unescaped -match '^[a-zA-Z0-9_\.]+-([0-9a-zA-Z\.\+]+)-') {
        return $matches[1]
    }
    return $unescaped
}

# 5. Inspect Currently Installed Versions via pure-Python metadata
$installedPackages = @{}
if (Test-Path -Path $pythonExe) {
    $probePy = @"
import sys, importlib.metadata
pkgs = ['rocm', 'torch', 'torchvision', 'torchaudio', 'rocm-sdk-core', 'rocm-sdk-devel', 'rocm-sdk-libraries-custom', 'triton-windows', 'pip']
for p in pkgs:
    try:
        print(f'{p}={importlib.metadata.version(p)}')
    except:
        print(f'{p}=None')
"@
    try {
        $out = & $pythonExe -c $probePy 2>$null
        foreach ($line in $out) {
            $p = $line -split '=', 2
            if ($p.Count -eq 2) {
                $installedPackages[$p[0].Trim()] = $p[1].Trim()
            }
        }
    } catch {
        $null = $_
    }
}

# 6. Build Package Comparison Items
$diffItems = @()

# ROCm Release Track
$diffItems += [PSCustomObject]@{
    Package   = "ROCm Release Track"
    Current   = $installedRelease
    Candidate = $candidateRelease
    IsUpgrade = ($installedRelease -ne $candidateRelease)
    Type      = "Release"
}

# Pip
$curPip = if ($installedPackages.ContainsKey('pip')) { $installedPackages['pip'] } else { "None" }
$candPip = [string]$activeConfig['PipVersion']
$diffItems += [PSCustomObject]@{
    Package   = "pip"
    Current   = $curPip
    Candidate = $candPip
    IsUpgrade = ($curPip -ne "None" -and $curPip -ne $candPip)
    Type      = "Tool"
}

# Core PyTorch packages
$torchMap = @(
    @{ Name = "torch"; Wheel = $candCfg['Torch'] },
    @{ Name = "torchvision"; Wheel = $candCfg['Vision'] },
    @{ Name = "torchaudio"; Wheel = $candCfg['Audio'] }
)

foreach ($tp in $torchMap) {
    $curVer = if ($installedPackages.ContainsKey($tp.Name)) { $installedPackages[$tp.Name] } else { "None" }
    $candVer = Get-WheelVersion -Filename $tp.Wheel
    $diffItems += [PSCustomObject]@{
        Package   = $tp.Name
        Current   = $curVer
        Candidate = $candVer
        IsUpgrade = ($curVer -ne "None" -and $curVer -ne $candVer)
        Type      = "PyTorch"
        WheelUrl  = "$baseUrl/$($tp.Wheel)"
    }
}

# ROCm SDK Packages & Metapackage
foreach ($sdkFile in $candCfg['SdkFiles']) {
    $candVer = ""
    $pkgKey = ""

    if ($sdkFile.EndsWith(".whl")) {
        $candVer = Get-WheelVersion -Filename $sdkFile
        if ($sdkFile -match "^rocm_sdk_core") { $pkgKey = "rocm-sdk-core" }
        elseif ($sdkFile -match "^rocm_sdk_devel") { $pkgKey = "rocm-sdk-devel" }
        elseif ($sdkFile -match "^rocm_sdk_libraries_custom") { $pkgKey = "rocm-sdk-libraries-custom" }
    } elseif ($sdkFile -match '^rocm-([0-9a-zA-Z\.\+]+)\.tar\.gz') {
        $pkgKey = "rocm"
        $candVer = $matches[1]
    }

    if ($pkgKey) {
        $curVer = if ($installedPackages.ContainsKey($pkgKey)) { $installedPackages[$pkgKey] } else { "None" }
        $diffItems += [PSCustomObject]@{
            Package   = $pkgKey
            Current   = $curVer
            Candidate = $candVer
            IsUpgrade = ($curVer -ne "None" -and $curVer -ne $candVer)
            Type      = "ROCm SDK"
            WheelUrl  = "$baseUrl/$sdkFile"
        }
    }
}

# Triton (if installed or requested)
$curTriton = if ($installedPackages.ContainsKey('triton-windows')) { $installedPackages['triton-windows'] } else { "None" }
if ($curTriton -ne "None" -or $WithTriton) {
    $diffItems += [PSCustomObject]@{
        Package   = "triton-windows"
        Current   = if ($curTriton -ne "None") { $curTriton } else { "[Not Installed]" }
        Candidate = "latest matching wheel"
        IsUpgrade = $true
        Type      = "Triton"
    }
}

# Portable MSVC Toolchain detection
$hasPortableMsvc = Test-Path -Path (Join-Path $msvcDir "setup_x64.bat")
$hasSystemMsvc = $false
$progRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432) | Where-Object { -not [string]::IsNullOrEmpty($_) } | Select-Object -Unique
foreach ($r in $progRoots) {
    $msvcMatches = Get-ChildItem -Path (Join-Path $r "Microsoft Visual Studio\*\*\VC\Tools\MSVC\*\include\type_traits") -ErrorAction SilentlyContinue
    if ($msvcMatches) {
        $hasSystemMsvc = $true
        break
    }
}
$hasAnyMsvc = $hasPortableMsvc -or $hasSystemMsvc

# Check if MSVC should be offered or upgraded
$wantMsvc = $false
if (-not $NoMsvc) {
    if ($WithMsvc) {
        $wantMsvc = $true
    } elseif ($curTriton -ne "None" -or $WithTriton) {
        if (-not $hasAnyMsvc) {
            $wantMsvc = $true
        }
    }
}

$curMsvc = if ($hasPortableMsvc) {
    "Installed (.\msvc)"
} elseif ($hasSystemMsvc) {
    "System Visual Studio"
} else {
    "[Not Installed]"
}

if ($hasPortableMsvc -or $wantMsvc -or $WithMsvc) {
    $candMsvc = if ($hasPortableMsvc) { "Installed (.\msvc)" } else { "portable MSVC (~130 MB)" }
    $diffItems += [PSCustomObject]@{
        Package   = "Portable MSVC Toolchain"
        Current   = $curMsvc
        Candidate = $candMsvc
        IsUpgrade = ($wantMsvc -and -not $hasPortableMsvc)
        Type      = "Toolchain"
    }
}

# 7. Render Linux Package Manager Status Table
$upgradableItems = @($diffItems | Where-Object { $_.IsUpgrade })

Write-Host "`n================================================================================" -ForegroundColor Cyan
Write-Host "  WinROCm Package Manager: Package Status & Candidate Updates" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ("  {0,-26} {1,-26} {2,-24}" -f "Package", "Current Version", "Candidate Version")
Write-Host ("  {0,-26} {1,-26} {2,-24}" -f ("-" * 24), ("-" * 24), ("-" * 24))

foreach ($item in $diffItems) {
    $color = if ($item.IsUpgrade) { [ConsoleColor]::Green } else { [ConsoleColor]::Gray }
    $suffix = if ($item.IsUpgrade) { " -> [Upgrade Available]" } else { "    [Up to date]" }
    Write-Host ("  {0,-26} {1,-26} {2,-24}" -f $item.Package, $item.Current, ($item.Candidate + $suffix)) -ForegroundColor $color
}
Write-Host "================================================================================" -ForegroundColor Cyan

if ($upgradableItems.Count -eq 0) {
    Write-Host "`nAll ROCm packages and runtime components are up to date! Nothing to do." -ForegroundColor Green
    Write-Host "ROCm Release: $candidateRelease | PyTorch: $(Get-WheelVersion $candCfg['Torch'])`n" -ForegroundColor Gray
    return
}

Write-Host "`nSummary: $($upgradableItems.Count) package(s) can be upgraded." -ForegroundColor Yellow

if ($CheckOnly) {
    Write-Host "`n[-CheckOnly] Run 'setup.bat update' or 'rocm update' to apply these updates.`n" -ForegroundColor Gray
    return
}

# 8. Confirmation Prompt
if (-not $Yes) {
    $isInteractive = [Environment]::UserInteractive
    if (-not $isInteractive) {
        Write-Warning "Running in non-interactive environment without -Yes / -y. Aborting update."
        return
    }

    $answer = Read-Host "`nDo you want to apply these updates? [Y/n]"
    if (-not ([string]::IsNullOrWhiteSpace($answer) -or $answer.Trim().ToLower() -eq 'y')) {
        Write-Host "Update cancelled by user. No packages were modified.`n" -ForegroundColor Yellow
        return
    }
} else {
    Write-Host "`nNon-interactive mode (-y / -Yes) specified. Proceeding with upgrade..." -ForegroundColor Green
}

# 9. Perform Targeted Upgrade
Write-Host "`n==> Starting WinROCm upgrade..." -ForegroundColor Cyan

# Set process environment
$rocmCustomLib = Join-Path $repoRoot "python\Lib\site-packages\_rocm_sdk_libraries_custom\bin"
$rocmCoreLib   = Join-Path $repoRoot "python\Lib\site-packages\_rocm_sdk_core\bin"
$rocmDevelLib  = Join-Path $repoRoot "python\Lib\site-packages\_rocm_sdk_devel\bin"
$rocmDevelRoot = Join-Path $repoRoot "python\Lib\site-packages\_rocm_sdk_devel"

$env:PATH                        = "$binDir;$pythonDir;$pythonDir\Scripts;$rocmCustomLib;$rocmCoreLib;$rocmDevelLib;$env:PATH"
$env:TORCH_BLAS_PREFER_HIPBLASLT = "1"
if (Test-Path -Path $rocmDevelRoot) {
    $env:ROCM_PATH = $rocmDevelRoot
    $env:HIP_PATH  = $rocmDevelRoot
}
$env:PYTHONNOUSERSITE            = "1"
$env:TEMP                        = $tmpDir
$env:TMP                         = $tmpDir
$env:XDG_CACHE_HOME              = $cacheDir
$env:PIP_NO_CACHE_DIR            = "1"
$env:PIP_CONFIG_FILE             = "NUL"
$env:PIP_DISABLE_PIP_VERSION_CHECK = "1"
$env:PIP_CONSTRAINT              = $null

# Configure Portable MSVC environment if present (ROCm / Triton acceleration)
$msvcSetupBat = Join-Path $msvcDir "setup_x64.bat"
if (Test-Path -Path $msvcSetupBat) {
    try {
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
        }
    } catch {
        Write-Warning "Could not inject existing Portable MSVC environment: $($_.Exception.Message)"
    }
}

# Install Portable MSVC Toolchain if requested or upgrading
$msvcItem = $upgradableItems | Where-Object { $_.Package -eq "Portable MSVC Toolchain" }
if ($msvcItem -or ($WithMsvc -and -not (Test-Path -Path $msvcSetupBat))) {
    Write-Host "`n[1/5] Installing lightweight Portable MSVC toolchain (~130 MB download)..." -ForegroundColor Yellow
    $portableMsvcScript = Join-Path $repoRoot "scripts\portable-msvc.py"
    if (Test-Path -Path $portableMsvcScript) {
        & $pythonExe $portableMsvcScript --accept-license --output $msvcDir --target x64 --host x64
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to install Portable MSVC toolchain."
            return
        }
        # Immediately activate MSVC environment for subsequent steps
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
            }
        }
        Write-Host "  [Pass] Portable MSVC toolchain installed and activated." -ForegroundColor Green
    } else {
        Write-Warning "Could not find scripts\portable-msvc.py in $repoRoot."
    }
}

# Upgrade Pip if required
$pipItem = $upgradableItems | Where-Object { $_.Package -eq "pip" }
if ($pipItem) {
    Write-Host "`n[2/5] Upgrading pip to $($pipItem.Candidate)..." -ForegroundColor Yellow
    & $pythonExe -m pip install --no-warn-script-location --retries 5 --timeout 60 "pip==$($pipItem.Candidate)"
}

# Upgrade ROCm SDK Packages and Metapackage
$sdkItems = @($upgradableItems | Where-Object { $_.Type -eq "ROCm SDK" -and $_.WheelUrl })
if ($sdkItems.Count -gt 0) {
    Write-Host "`n[3/5] Upgrading ROCm SDK packages and metapackage..." -ForegroundColor Yellow
    $sdkUrls = @($sdkItems | ForEach-Object { $_.WheelUrl })
    & $pythonExe -m pip install --no-warn-script-location --retries 5 --timeout 60 --upgrade --no-deps @sdkUrls
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to install ROCm SDK upgrades."
        return
    }

    # Materialize headers if devel was updated
    Write-Host "  Re-materializing ROCm developer headers (rocm-sdk init)..." -ForegroundColor Yellow
    & $pythonExe -m rocm_sdk init
}

# Upgrade PyTorch Wheels
$torchItems = @($upgradableItems | Where-Object { $_.Type -eq "PyTorch" -and $_.WheelUrl })
if ($torchItems.Count -gt 0) {
    Write-Host "`n[4/5] Upgrading PyTorch wheels..." -ForegroundColor Yellow
    $torchUrls = @($torchItems | ForEach-Object { $_.WheelUrl })
    & $pythonExe -m pip install --no-warn-script-location --retries 5 --timeout 60 --upgrade --no-deps @torchUrls
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to install PyTorch upgrades."
        return
    }
}

# Upgrade / Install Triton if requested or upgrading
$tritonItem = $upgradableItems | Where-Object { $_.Package -eq "triton-windows" }
if ($tritonItem -or $WithTriton) {
    Write-Host "`n[5/5] Installing/Upgrading triton-windows..." -ForegroundColor Yellow
    $torchMinor = if ($installedPackages.ContainsKey('torch') -and $installedPackages['torch'] -ne "None") {
        $tv = $installedPackages['torch'].Split('.')
        "$($tv[0]).$($tv[1])"
    } else {
        $candTorch = Get-WheelVersion -Filename $candCfg['Torch']
        $tv = $candTorch.Split('.')
        "$($tv[0]).$($tv[1])"
    }
    $tritonSpec = switch ($torchMinor) {
        "2.6"  { "triton-windows>=3.2,<3.3" }
        "2.7"  { "triton-windows>=3.3,<3.4" }
        "2.8"  { "triton-windows>=3.4,<3.5" }
        "2.9"  { "triton-windows>=3.5,<3.6" }
        "2.10" { "triton-windows>=3.6,<3.7" }
        "2.11" { "triton-windows>=3.6,<3.7" }
        "2.12" { "triton-windows>=3.7,<3.8" }
        "2.13" { "triton-windows>=3.7,<3.8" }
        "2.14" { "triton-windows>=3.8,<3.9" }
        "2.15" { "triton-windows>=3.8,<3.9" }
        default { "triton-windows>=3.8,<3.10" }
    }
    Write-Host "  Resolved triton-windows specification for PyTorch $($torchMinor): $tritonSpec" -ForegroundColor Cyan
    & $pythonExe -m pip install --no-warn-script-location --retries 5 --timeout 60 $tritonSpec
}

# Persist updated catalog to disk now that upgrade is confirmed
if ($null -ne $remoteUpdatedText) {
    Set-Content -Path $configPath -Value $remoteUpdatedText -Encoding UTF8
    Write-Host "  Updated config/releases.psd1 with synchronized catalog." -ForegroundColor Green
}

# Refresh Launchers and Shims
Write-Host "`nRefresh launchers, runtime shims, and environment constraints..." -ForegroundColor Yellow

# Copy templates to bin/
if (Test-Path -Path $templateDir) {
    Get-ChildItem -Path $templateDir -Filter "*.*" | ForEach-Object {
        $dest = Join-Path $binDir $_.Name
        Copy-Item -Path $_.FullName -Destination $dest -Force
    }
    # Copy sitecustomize.py to python/Lib/site-packages
    $sitePkg = Join-Path $pythonDir "Lib\site-packages"
    if (Test-Path -Path $sitePkg) {
        $scSrc = Join-Path $templateDir "sitecustomize.py"
        if (Test-Path -Path $scSrc) {
            Copy-Item -Path $scSrc -Destination (Join-Path $sitePkg "sitecustomize.py") -Force
        }
    }
}

# Regenerate constraints-rocm.txt
$constraintsPy = @"
import importlib.metadata
want = {"torch", "torchvision", "torchaudio", "rocm", "rocm-sdk-core", "rocm-sdk-devel", "rocm-sdk-libraries-custom", "triton", "triton-windows"}
lines = []
for dist in sorted(importlib.metadata.distributions(), key=lambda d: d.metadata['Name'].lower()):
    name = dist.metadata['Name']
    if name.lower().replace('_', '-') in want:
        lines.append(f"{name}=={dist.version}")
print("\n".join(lines))
"@
try {
    $constraintsContent = & $pythonExe -c $constraintsPy
    if ($constraintsContent) {
        Set-Content -Path $constraintsFile -Value $constraintsContent -Encoding ASCII
        Write-Host "  Updated constraints-rocm.txt" -ForegroundColor Green
    }
} catch {
    Write-Warning "Could not update constraints-rocm.txt: $($_.Exception.Message)"
}

# Update .rocm-portable.json
$installedTorchVer = ""
try {
    $installedTorchVer = (& $pythonExe -c "import importlib.metadata; print(importlib.metadata.version('torch'))").Trim()
} catch {
    $installedTorchVer = "Unknown"
}

$components = @("torch")
if ($installedPackages.ContainsKey('torchvision') -and $installedPackages['torchvision'] -ne "None") { $components += "torchvision" }
if ($installedPackages.ContainsKey('torchaudio') -and $installedPackages['torchaudio'] -ne "None") { $components += "torchaudio" }
if (($installedPackages.ContainsKey('triton-windows') -and $installedPackages['triton-windows'] -ne "None") -or $tritonItem -or $WithTriton) { $components += "triton-windows" }
if (Test-Path -Path (Join-Path $msvcDir "setup_x64.bat")) { $components += "msvc" }

$newState = [ordered]@{
    scriptVersion  = "0.4.1"
    rocmRelease    = $candidateRelease
    pythonVersion  = [string]$activeConfig['PythonVersion']
    torchVersion   = $installedTorchVer
    components     = $components
    installedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
}
$newState | ConvertTo-Json -Depth 4 | Set-Content -Path $stateFile -Encoding UTF8

Write-Host "`n================================================================================" -ForegroundColor Green
Write-Host "  Upgrade Completed Successfully! ROCm Release: $candidateRelease" -ForegroundColor Green
Write-Host "================================================================================" -ForegroundColor Green
Write-Host "To verify your upgraded environment, run:" -ForegroundColor Yellow
Write-Host "  setup.bat verify   (or: rocm verify)`n" -ForegroundColor White
