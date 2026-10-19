<#
.SYNOPSIS
    WinROCm-PyTorch: Portable AMD ROCm PyTorch installer for Windows (AMD RDNA3/RDNA4 GPUs).

.DESCRIPTION
    Installs embeddable Python 3.12, AMD ROCm SDK wheels, and PyTorch (torch,
    torchvision, torchaudio) into a single isolated directory with zero system changes.
    Nothing is added to PATH, the registry, %APPDATA%, or user pip caches.

.PARAMETER InstallDir
    Target directory for the installation. Defaults to the directory containing this script.

.PARAMETER RocmRelease
    ROCm release to install (e.g. '7.2', '7.2.1'). Defaults to DefaultRelease in config/releases.psd1.

.PARAMETER NoVision
    Skip installation of torchvision.

.PARAMETER NoAudio
    Skip installation of torchaudio.

.PARAMETER Reinstall
    Wipe existing .\python, state file, and constraints file, then reinstall cleanly.

.PARAMETER SkipGpuCheck
    Suppress warning when detected GPU is not on AMD's verified hardware list.

.PARAMETER SkipVerify
    Skip the verify_rocm.py test step after installation.

.PARAMETER DryRun
    Run preflight checks, display the plan, perform HEAD checks on all URLs, and exit without downloading.

.PARAMETER Diagnose
    Collect diagnostic system, environment, GPU, and PyTorch probe information into diagnose.txt and exit.

.PARAMETER Yes
    Bypass the interactive confirmation prompt (for non-interactive and CI use).

.EXAMPLE
    .\setup_rocm_portable.ps1

.EXAMPLE
    .\setup_rocm_portable.ps1 -InstallDir C:\rocm -Yes

.EXAMPLE
    .\setup_rocm_portable.ps1 -DryRun

.EXAMPLE
    .\setup_rocm_portable.ps1 -Diagnose
#>

[CmdletBinding()]
param(
    [string]$InstallDir = $PSScriptRoot,
    [string]$RocmRelease,
    [switch]$NoVision,
    [switch]$NoAudio,
    [switch]$Reinstall,
    [switch]$SkipGpuCheck,
    [switch]$SkipVerify,
    [switch]$DryRun,
    [switch]$Diagnose,
    [switch]$Yes
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Ensure TLS 1.2 and Utility module
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Import-Module Microsoft.PowerShell.Utility -ErrorAction SilentlyContinue

$Script:Version = "0.2.0"

# Custom Exception for mapped exit codes
class SetupException : System.Exception {
    [int]$ExitCode
    SetupException([int]$code, [string]$message) : base($message) {
        $this.ExitCode = $code
    }
}

function Assert-LastExit {
    param(
        [string]$Step,
        [int]$Code = 4
    )
    if ($LASTEXITCODE -ne 0) {
        throw [SetupException]::new($Code, "$Step failed with exit code $LASTEXITCODE")
    }
}

function Get-FileSha256 {
    param([string]$FilePath)
    if (-not (Test-Path -Path $FilePath)) {
        return $null
    }
    return (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash
}

function Test-PythonModule {
    param(
        [string]$PythonExe,
        [string]$Code
    )
    if (-not (Test-Path -Path $PythonExe)) { return $false }
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $PythonExe -c $Code 2>$null | Out-Null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    } finally {
        $ErrorActionPreference = $prevEAP
    }
}

function Invoke-WithRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        [int]$MaxRetries = 3,
        [int]$InitialDelaySec = 2,
        [string]$OperationName = "Download"
    )
    $attempt = 0
    while ($attempt -lt $MaxRetries) {
        $attempt++
        try {
            return (& $ScriptBlock)
        } catch {
            if ($attempt -ge $MaxRetries) {
                throw [SetupException]::new(3, "$OperationName failed after $MaxRetries attempts: $($_.Exception.Message)")
            }
            $delay = $InitialDelaySec * [math]::Pow(2, $attempt - 1)
            Write-Warning "$OperationName failed (attempt $attempt of $MaxRetries): $($_.Exception.Message). Retrying in $delay second(s)..."
            Start-Sleep -Seconds $delay
        }
    }
}

function Get-ReleaseConfig {
    param(
        [hashtable]$Config,
        [string]$RequestedRelease
    )
    $releases = $Config['Releases']
    $defaultRelease = [string]$Config['DefaultRelease']

    $targetRelease = if ([string]::IsNullOrWhiteSpace($RequestedRelease)) {
        $defaultRelease
    } else {
        $RequestedRelease.Trim()
    }

    if (-not $releases.ContainsKey($targetRelease)) {
        $available = ($releases.Keys | Sort-Object) -join ', '
        throw [SetupException]::new(2, "Unknown ROCm release '$targetRelease'. Available releases: $available")
    }

    return @{
        Name   = $targetRelease
        Config = $releases[$targetRelease]
    }
}

function Test-Preflight {
    param(
        [hashtable]$Config,
        [string]$TargetDir,
        [string]$SelectedRelease,
        [switch]$SkipGpu
    )

    Write-Host "`n==> Running Preflight Checks (Release: $SelectedRelease)..." -ForegroundColor Cyan
    $failures = @()
    $warnings = @()

    # 1. 64-bit Windows 11
    if (-not [Environment]::Is64BitOperatingSystem) {
        $failures += "Check 1 [OS Architecture]: 64-bit Windows is required. Detected 32-bit OS."
    } else {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        $buildNumber = 0
        if ($null -ne $os -and $null -ne $os.BuildNumber) {
            $buildNumber = [int]$os.BuildNumber
        }
        if ($buildNumber -lt 22000) {
            $warnings += "Check 1 [OS Version]: Detected Windows build $buildNumber (< 22000 / Windows 11). AMD lists Windows 11 as the officially supported OS."
        } else {
            Write-Host "  [Pass] OS: Windows 11 64-bit (Build $buildNumber)" -ForegroundColor Green
        }
    }

    # 2. PowerShell 5.1 or 7+
    $psMajor = $PSVersionTable.PSVersion.Major
    $psMinor = $PSVersionTable.PSVersion.Minor
    if ($psMajor -lt 5 -or ($psMajor -eq 5 -and $psMinor -lt 1)) {
        $failures += "Check 2 [PowerShell]: PowerShell 5.1 or 7+ required. Detected $($PSVersionTable.PSVersion)."
    } else {
        Write-Host "  [Pass] PowerShell: $($PSVersionTable.PSVersion)" -ForegroundColor Green
    }

    # 3. Path length
    $pathLen = $TargetDir.Length
    if ($pathLen -gt 100) {
        $failures += "Check 3 [Path Length]: Target directory length ($pathLen chars) exceeds 100 characters. Deep PyTorch packages may exceed MAX_PATH (260). Please use a shorter path (e.g. C:\rocm)."
    } elseif ($pathLen -gt 60) {
        $warnings += "Check 3 [Path Length]: Target directory length ($pathLen chars) is long (> 60 chars). Consider a shorter path like C:\rocm."
    } else {
        Write-Host "  [Pass] Path length: $pathLen chars" -ForegroundColor Green
    }

    # 4. Path ASCII & special chars
    if ($TargetDir -match '[^\x00-\x7F]') {
        $failures += "Check 4 [Path Chars]: Target directory contains non-ASCII characters, which breaks embeddable Python and batch files."
    } else {
        $specialChars = @('%', '^', '&', '!')
        $foundSpecial = @($specialChars | Where-Object { $TargetDir.Contains($_) })
        if ($foundSpecial.Count -gt 0) {
            $warnings += "Check 4 [Path Chars]: Target directory contains special characters ($($foundSpecial -join ' ')), which may cause batch script escaping issues."
        } else {
            Write-Host "  [Pass] Path characters: ASCII-only, clean" -ForegroundColor Green
        }
    }

    # 5. Free disk space (15 GB requirement)
    $reqSpaceGB = 15.0
    try {
        $root = [System.IO.Path]::GetPathRoot($TargetDir)
        $driveLetter = $root.TrimEnd('\')
        $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$driveLetter'" -ErrorAction Stop
        $freeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
        if ($freeGB -lt $reqSpaceGB) {
            $failures += "Check 5 [Disk Space]: Drive $driveLetter has only $freeGB GB free. At least $reqSpaceGB GB is required for download + extraction footprint."
        } else {
            Write-Host "  [Pass] Free disk space: $freeGB GB on $driveLetter (minimum $reqSpaceGB GB)" -ForegroundColor Green
        }
    } catch {
        $warnings += "Check 5 [Disk Space]: Could not check free disk space on '$TargetDir': $($_.Exception.Message)"
    }

    # 6. Folder writable
    try {
        $checkDir = $TargetDir
        while (-not (Test-Path -Path $checkDir) -and -not [string]::IsNullOrEmpty($checkDir)) {
            $parent = [System.IO.Path]::GetDirectoryName($checkDir)
            if ($parent -eq $checkDir -or [string]::IsNullOrEmpty($parent)) { break }
            $checkDir = $parent
        }
        if (-not (Test-Path -Path $checkDir)) {
            $failures += "Check 6 [Permissions]: Target drive or parent directory for '$TargetDir' does not exist."
        } else {
            $testFile = Join-Path $checkDir ".write_test_$([Guid]::NewGuid().ToString('N'))"
            [System.IO.File]::WriteAllText($testFile, "ok")
            Remove-Item -Path $testFile -Force
            Write-Host "  [Pass] Target location is writable" -ForegroundColor Green
        }
    } catch {
        $failures += "Check 6 [Permissions]: Target folder is not writable: $($_.Exception.Message)"
    }

    # 7. Network reachability
    $networkHosts = @('www.python.org', 'bootstrap.pypa.io', 'repo.radeon.com', 'pypi.org')
    foreach ($nh in $networkHosts) {
        try {
            $resp = Invoke-WebRequest -Uri "https://$nh" -Method Head -TimeoutSec 6 -UseBasicParsing -ErrorAction Stop
            if ($resp.StatusCode -ge 400) {
                $failures += "Check 7 [Network]: Host https://$nh returned HTTP $($resp.StatusCode)"
            }
        } catch {
            $failures += "Check 7 [Network]: Host https://$nh is unreachable ($($_.Exception.Message))"
        }
    }
    if ($failures | Where-Object { $_ -like "Check 7*" }) {
        # Already captured in failures
    } else {
        Write-Host "  [Pass] Network reachability: All hosts reachable (python.org, pypa.io, radeon.com, pypi.org)" -ForegroundColor Green
    }

    # 8. GPU detection
    if (-not $SkipGpu) {
        $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)
        $gpuPatterns = @($Config['SupportedGpuPatterns'])
        $matchedGpu = $false
        $detectedGpus = @()

        foreach ($g in $gpus) {
            $gName = [string]$g.Name
            $gDriver = [string]$g.DriverVersion
            $detectedGpus += "$gName (Driver: $gDriver)"
            foreach ($pattern in $gpuPatterns) {
                if ($gName -like "*$pattern*") {
                    $matchedGpu = $true
                    break
                }
            }
        }

        if ($matchedGpu) {
            Write-Host "  [Pass] Supported AMD GPU detected: $($detectedGpus -join '; ')" -ForegroundColor Green
        } else {
            $warnings += "Check 8 [GPU Compatibility]: Detected GPU(s): '$($detectedGpus -join '; ')'. None matched officially verified models ($($gpuPatterns -join ', ')). PyTorch official wheels may not detect this GPU."
        }
    }

    # 9. Admin elevation check
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]$identity
        if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            $warnings += "Check 9 [Privileges]: Running as Administrator. This installer is fully isolated and does not require elevated rights."
        } else {
            Write-Host "  [Pass] Running un-elevated (recommended)" -ForegroundColor Green
        }
    } catch {
        $null = $_
    }

    # 10. Mark-of-the-Web
    if ($PSCommandPath -and (Test-Path -Path $PSCommandPath)) {
        $zone = Get-Item -LiteralPath $PSCommandPath -Stream "Zone.Identifier" -ErrorAction SilentlyContinue
        if ($null -ne $zone) {
            $warnings += "Check 10 [Mark-of-the-Web]: Script has Zone.Identifier (downloaded from internet). If issues arise, unblock with: Unblock-File '$PSCommandPath'"
        }
    }

    # 11. Existing install state
    $stateFile = Join-Path $TargetDir ".rocm-portable.json"
    if (Test-Path -Path $stateFile) {
        try {
            $stateObj = Get-Content -Path $stateFile -Raw | ConvertFrom-Json
            Write-Host "  [Info] Existing installation detected: ROCm $($stateObj.rocmRelease), PyTorch $($stateObj.torchVersion) (installed at $($stateObj.installedAtUtc))" -ForegroundColor Cyan
        } catch {
            $null = $_
        }
    }

    # Output warnings and failures
    foreach ($w in $warnings) {
        Write-Warning $w
    }

    if ($failures.Count -gt 0) {
        Write-Host "`n[ERROR] Preflight checks failed:" -ForegroundColor Red
        foreach ($f in $failures) {
            Write-Host "  - $f" -ForegroundColor Red
        }
        throw [SetupException]::new(2, "Preflight checks failed ($($failures.Count) critical error(s)).")
    }

    Write-Host "==> All preflight checks passed!`n" -ForegroundColor Green
}

function Invoke-DryRun {
    param(
        [hashtable]$Config,
        [hashtable]$ReleaseInfo,
        [string]$TargetDir,
        [bool]$IncludeVision,
        [bool]$IncludeAudio
    )

    $rName = $ReleaseInfo['Name']
    $rCfg = $ReleaseInfo['Config']
    $baseUrl = $rCfg['BaseUrl']

    Write-Host "================== DRY RUN PLAN ==================" -ForegroundColor Cyan
    Write-Host "ROCm Release        : $rName"
    Write-Host "Install Directory   : $TargetDir"
    Write-Host "Python Version      : $($Config['PythonVersion'])"
    Write-Host "Components          : torch$(if ($IncludeVision) { ', torchvision' })$(if ($IncludeAudio) { ', torchaudio' })"
    Write-Host "Download Size (est) : ~3.5 GB"
    Write-Host "Disk Required (est) : ~11 GB installed, 15 GB peak"
    Write-Host "==================================================" -ForegroundColor Cyan

    Write-Host "`n==> Checking all download URLs (HEAD requests)..." -ForegroundColor Yellow

    $urlsToCheck = @(
        [PSCustomObject]@{ Name = "Python 3.12 Embed"; Url = $Config['PythonZipUrl'] },
        [PSCustomObject]@{ Name = "Python C-Headers (dev.msi)"; Url = $Config['PythonDevMsiUrl'] },
        [PSCustomObject]@{ Name = "get-pip.py"; Url = $Config['GetPipUrl'] }
    )

    foreach ($sdkFile in $rCfg['SdkFiles']) {
        $urlsToCheck += [PSCustomObject]@{ Name = "ROCm SDK: $sdkFile"; Url = "$baseUrl/$sdkFile" }
    }

    $urlsToCheck += [PSCustomObject]@{ Name = "PyTorch Wheel"; Url = "$baseUrl/$($rCfg['Torch'])" }

    if ($IncludeVision) {
        $urlsToCheck += [PSCustomObject]@{ Name = "Torchvision Wheel"; Url = "$baseUrl/$($rCfg['Vision'])" }
    }
    if ($IncludeAudio) {
        $urlsToCheck += [PSCustomObject]@{ Name = "Torchaudio Wheel"; Url = "$baseUrl/$($rCfg['Audio'])" }
    }

    $failedUrls = 0
    foreach ($item in $urlsToCheck) {
        try {
            $resp = Invoke-WebRequest -Uri $item.Url -Method Head -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
            $sizeMB = if ($resp.Headers.ContainsKey('Content-Length')) {
                $rawLen = $resp.Headers['Content-Length'] | Select-Object -First 1
                [math]::Round([long]$rawLen / 1MB, 2)
            } else { 0 }
            Write-Host ("  [OK {0}] {1} ({2} MB)" -f $resp.StatusCode, $item.Name, $sizeMB) -ForegroundColor Green
        } catch {
            Write-Host ("  [FAILED] {0} -> {1}" -f $item.Name, $_.Exception.Message) -ForegroundColor Red
            $failedUrls++
        }
    }

    if ($failedUrls -gt 0) {
        throw [SetupException]::new(3, "Dry run encountered $failedUrls unreachable URL(s).")
    }

    Write-Host "`nDry run completed successfully. All URLs verified. No files were downloaded or modified." -ForegroundColor Green
}

function Install-Python {
    param(
        [hashtable]$Config,
        [string]$TargetDir
    )

    $pythonDir = Join-Path $TargetDir "python"
    $pythonExe = Join-Path $pythonDir "python.exe"
    $pythonZip = Join-Path $TargetDir "python-embed.zip"
    $expectedVer = [string]$Config['PythonVersion']
    $expectedSha = [string]$Config['PythonSha256']

    if (Test-Path -Path $pythonExe) {
        # Check existing version
        try {
            $installedVer = (& $pythonExe -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}')").Trim()
            if ($installedVer -eq $expectedVer) {
                Write-Host "`n[1/5] Python $expectedVer already installed in .\python. Skipping download." -ForegroundColor Green
                return
            }
        } catch {
            $null = $_
        }
    }

    Write-Host "`n[1/5] Downloading embeddable Python $expectedVer..." -ForegroundColor Yellow
    Invoke-WithRetry -OperationName "Python zip download" -ScriptBlock {
        Invoke-WebRequest -Uri $Config['PythonZipUrl'] -OutFile $pythonZip -UseBasicParsing
    }

    # Verify SHA256
    $actualSha = Get-FileSha256 -FilePath $pythonZip
    if ($actualSha -ne $expectedSha) {
        Remove-Item -Path $pythonZip -Force -ErrorAction SilentlyContinue
        throw [SetupException]::new(3, "Python download SHA256 mismatch! Expected: $expectedSha, Actual: $actualSha")
    }
    Write-Host "  Python SHA256 verified: $actualSha" -ForegroundColor Green

    Write-Host "Extracting Python binaries..." -ForegroundColor Yellow
    if (Test-Path -Path $pythonDir) {
        Remove-Item -Path $pythonDir -Recurse -Force
    }
    Expand-Archive -Path $pythonZip -DestinationPath $pythonDir -Force
    Remove-Item -Path $pythonZip -Force
}

function Initialize-PythonPath {
    param([string]$TargetDir)

    Write-Host "`n[2/5] Configuring Python path file (*._pth)..." -ForegroundColor Yellow
    $pythonDir = Join-Path $TargetDir "python"
    $pthFile = Get-ChildItem -Path $pythonDir -Filter "*._pth" | Select-Object -First 1
    if (-not $pthFile) {
        throw [SetupException]::new(1, "Could not find *._pth file in $pythonDir")
    }

    $sitePackages = Join-Path $pythonDir "Lib\site-packages"
    if (-not (Test-Path -Path $sitePackages)) {
        New-Item -ItemType Directory -Force -Path $sitePackages | Out-Null
    }

    # Dynamically derive stdlib zip name from ._pth base name (e.g. python312._pth -> python312.zip)
    # Exclude '..' to prevent injecting parent directory into sys.path
    $stdlibZip = "$($pthFile.BaseName).zip"
    $pthContent = "$stdlibZip`r`n.`r`nLib\site-packages`r`nimport site"
    Set-Content -Path $pthFile.FullName -Value $pthContent -Encoding ASCII
    Write-Host "  Configured $($pthFile.Name) for site-packages and isolated imports." -ForegroundColor Green
}

function Install-PythonDevHeaders {
    param(
        [hashtable]$Config,
        [string]$TargetDir
    )

    $pythonDir = Join-Path $TargetDir "python"
    $includeDir = Join-Path $pythonDir "include"
    $libsDir = Join-Path $pythonDir "libs"
    $pythonH = Join-Path $includeDir "Python.h"
    $pythonLib = Join-Path $libsDir "python312.lib"

    if ((Test-Path -Path $pythonH) -and (Test-Path -Path $pythonLib)) {
        Write-Host "  Python C/C++ development headers (include/ and libs/) already present. Skipping." -ForegroundColor Green
        return
    }

    Write-Host "  Installing Python C/C++ development headers and libraries (include/ and libs/)..." -ForegroundColor Yellow
    $devMsiUrl = $Config['PythonDevMsiUrl']
    $devMsiSha = $Config['PythonDevMsiSha256']
    $tmpDir = Join-Path $TargetDir ".tmp"
    if (-not (Test-Path -Path $tmpDir)) {
        New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
    }
    $devMsi = Join-Path $tmpDir "dev.msi"
    $extractTmp = Join-Path $tmpDir "dev_msi_extract"

    Invoke-WithRetry -OperationName "Python dev.msi download" -ScriptBlock {
        Invoke-WebRequest -Uri $devMsiUrl -OutFile $devMsi -UseBasicParsing
    }

    if (-not [string]::IsNullOrEmpty($devMsiSha)) {
        $actualSha = Get-FileSha256 -FilePath $devMsi
        if ($actualSha -ne $devMsiSha) {
            Remove-Item -Path $devMsi -Force -ErrorAction SilentlyContinue
            throw [SetupException]::new(3, "dev.msi SHA256 mismatch! Expected: $devMsiSha, Actual: $actualSha")
        }
    }

    if (Test-Path -Path $extractTmp) {
        Remove-Item -Path $extractTmp -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $extractTmp | Out-Null

    # Administrative image unpack via msiexec (requires no admin privileges)
    $targetArg = "TARGETDIR=" + $extractTmp.TrimEnd('\') + "\"
    $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList @('/a', $devMsi, '/qn', $targetArg) -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        throw [SetupException]::new(1, "msiexec extraction of dev.msi failed with exit code $($proc.ExitCode)")
    }

    # Copy include and libs to pythonDir
    $srcInclude = Join-Path $extractTmp "include"
    $srcLibs = Join-Path $extractTmp "libs"

    if (Test-Path -Path $srcInclude) {
        Copy-Item -Path $srcInclude -Destination $pythonDir -Recurse -Force
    }
    if (Test-Path -Path $srcLibs) {
        Copy-Item -Path $srcLibs -Destination $pythonDir -Recurse -Force
    }

    # Clean up temp
    Remove-Item -Path $devMsi -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $extractTmp -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "  Successfully installed Python headers (Python.h) and import libraries." -ForegroundColor Green
}

function Install-Pip {
    param(
        [hashtable]$Config,
        [string]$TargetDir
    )

    $pythonDir = Join-Path $TargetDir "python"
    $pythonExe = Join-Path $pythonDir "python.exe"
    $getPipPy  = Join-Path $TargetDir "get-pip.py"

    $pipVer = [string]$Config['PipVersion']
    $setuptoolsVer = [string]$Config['SetuptoolsVersion']
    $wheelVer = [string]$Config['WheelVersion']
    $expectedSha = [string]$Config['GetPipSha256']

    # Check if pip is already working
    $pipWorks = $false
    try {
        & $pythonExe -m pip --version 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { $pipWorks = $true }
    } catch {
        $null = $_
    }

    if (-not $pipWorks) {
        Write-Host "`n[3/5] Bootstrapping pip and core packaging tools..." -ForegroundColor Yellow
        Invoke-WithRetry -OperationName "get-pip.py download" -ScriptBlock {
            Invoke-WebRequest -Uri $Config['GetPipUrl'] -OutFile $getPipPy -UseBasicParsing
        }

        # Check hash
        $actualSha = Get-FileSha256 -FilePath $getPipPy
        if ($actualSha -ne $expectedSha) {
            Remove-Item -Path $getPipPy -Force -ErrorAction SilentlyContinue
            throw [SetupException]::new(3, "get-pip.py SHA256 mismatch! Expected: $expectedSha, Actual: $actualSha")
        }

        & $pythonExe $getPipPy --no-warn-script-location
        Assert-LastExit "get-pip bootstrap" 4
        Remove-Item -Path $getPipPy -Force -ErrorAction SilentlyContinue
    } else {
        Write-Host "`n[3/5] Pip is already bootstrapped. Verifying pinned packaging tools..." -ForegroundColor Green
    }

    # Pin pip, setuptools, wheel
    Write-Host "  Pinning packaging tools (pip==$pipVer, setuptools==$setuptoolsVer, wheel==$wheelVer)..." -ForegroundColor Yellow
    & $pythonExe -m pip install --no-warn-script-location --retries 5 --timeout 60 "pip==$pipVer" "setuptools==$setuptoolsVer" "wheel==$wheelVer"
    Assert-LastExit "Pinning pip/setuptools/wheel" 4
}

function Install-RocmSdk {
    param(
        [hashtable]$ReleaseInfo,
        [string]$TargetDir,
        [hashtable]$State
    )

    $pythonDir = Join-Path $TargetDir "python"
    $pythonExe = Join-Path $pythonDir "python.exe"
    $rName = $ReleaseInfo['Name']
    $rCfg = $ReleaseInfo['Config']
    $baseUrl = $rCfg['BaseUrl']

    # Check if already installed
    $matchRelease = (-not $State.ContainsKey('rocmRelease')) -or ($State['rocmRelease'] -eq $rName)
    if ($matchRelease -and (Test-Path -Path $pythonExe)) {
        $sdkValid = $true
        foreach ($pkg in @("rocm-sdk-core", "rocm-sdk-devel", "rocm-sdk-libraries-custom")) {
            if (-not (Test-PythonModule -PythonExe $pythonExe -Code "import importlib.metadata; importlib.metadata.version('$pkg')")) {
                $sdkValid = $false
                break
            }
        }
        if ($sdkValid) {
            Write-Host "`n[4a/5] ROCm SDK $rName is already installed. Skipping." -ForegroundColor Green
            return
        }
    }

    Write-Host "`n[4a/5] Installing ROCm SDK $rName packages (large download)..." -ForegroundColor Yellow
    $sdkPackages = @()
    foreach ($f in $rCfg['SdkFiles']) {
        $sdkPackages += "$baseUrl/$f"
    }

    & $pythonExe -m pip install --no-warn-script-location --retries 5 --timeout 60 @sdkPackages
    Assert-LastExit "ROCm SDK installation" 4
}

function Install-Torch {
    param(
        [hashtable]$ReleaseInfo,
        [string]$TargetDir,
        [bool]$IncludeVision,
        [bool]$IncludeAudio,
        [hashtable]$State
    )

    $pythonDir = Join-Path $TargetDir "python"
    $pythonExe = Join-Path $pythonDir "python.exe"
    $rName = $ReleaseInfo['Name']
    $rCfg = $ReleaseInfo['Config']
    $baseUrl = $rCfg['BaseUrl']

    # Check if all requested torch components are already installed
    $matchRelease = (-not $State.ContainsKey('rocmRelease')) -or ($State['rocmRelease'] -eq $rName)
    if ($matchRelease -and (Test-Path -Path $pythonExe)) {
        $torchPresent = Test-PythonModule -PythonExe $pythonExe -Code "import torch"
        $visionPresent = (-not $IncludeVision) -or (Test-PythonModule -PythonExe $pythonExe -Code "import torchvision")
        $audioPresent = (-not $IncludeAudio) -or (Test-PythonModule -PythonExe $pythonExe -Code "import torchaudio")

        if ($torchPresent -and $visionPresent -and $audioPresent) {
            Write-Host "`n[4b/5] PyTorch and requested components for ROCm $rName are already installed. Skipping." -ForegroundColor Green
            return
        }
    }

    Write-Host "`n[4b/5] Installing AMD ROCm PyTorch wheels..." -ForegroundColor Yellow
    $torchPackages = @()

    $needTorch = -not (Test-PythonModule -PythonExe $pythonExe -Code "import torch")
    if ($needTorch) {
        $torchPackages += "$baseUrl/$($rCfg['Torch'])"
    }

    if ($IncludeAudio -and -not (Test-PythonModule -PythonExe $pythonExe -Code "import torchaudio")) {
        $torchPackages += "$baseUrl/$($rCfg['Audio'])"
    }
    if ($IncludeVision -and -not (Test-PythonModule -PythonExe $pythonExe -Code "import torchvision")) {
        $torchPackages += "$baseUrl/$($rCfg['Vision'])"
    }

    if ($torchPackages.Count -gt 0) {
        & $pythonExe -m pip install --no-warn-script-location --retries 5 --timeout 60 @torchPackages
        Assert-LastExit "PyTorch ROCm installation" 4
    }
}

function Write-Launchers {
    param(
        [string]$TemplateDir,
        [string]$TargetDir
    )

    Write-Host "`n[5/5] Refreshing launcher scripts from templates into bin/..." -ForegroundColor Yellow
    $binDir = Join-Path $TargetDir "bin"
    if (-not (Test-Path -Path $binDir)) {
        New-Item -ItemType Directory -Force -Path $binDir | Out-Null
    }

    $launcherFiles = @("env_rocm.bat", "run_rocm.bat", "pip_rocm.bat", "shell_rocm.bat", "torchrun_rocm.bat", "env_rocm.ps1")

    foreach ($f in $launcherFiles) {
        $src = Join-Path $TemplateDir $f
        $dst = Join-Path $binDir $f
        if (Test-Path -Path $src) {
            Copy-Item -Path $src -Destination $dst -Force
        } else {
            throw [SetupException]::new(1, "Required launcher template not found: $src")
        }
    }

    # Also copy verify_rocm.py into bin/ for easy user access
    $verifySrc = Join-Path $TemplateDir "verify_rocm.py"
    if (Test-Path -Path $verifySrc) {
        Copy-Item -Path $verifySrc -Destination (Join-Path $binDir "verify_rocm.py") -Force
    }

    Write-Host "  Launchers and verify test written to $binDir." -ForegroundColor Green
}

function Write-Constraints {
    param([string]$TargetDir)

    Write-Host "Generating constraints-rocm.txt to prevent accidental torch replacement..." -ForegroundColor Yellow
    $pythonExe = Join-Path $TargetDir "python\python.exe"
    $constraintsFile = Join-Path $TargetDir "constraints-rocm.txt"

    $pyCode = @'
from importlib.metadata import distributions
want = {"torch", "torchvision", "torchaudio", "rocm", "rocm-sdk-core", "rocm-sdk-devel", "rocm-sdk-libraries-custom"}
lines = []
for d in sorted(distributions(), key=lambda d: d.metadata["Name"].lower()):
    name = d.metadata["Name"]
    if name.lower().replace("_", "-") in want:
        lines.append(f"{name}=={d.version}")
print("\n".join(lines))
'@

    $output = $pyCode | & $pythonExe -
    Assert-LastExit "Constraints generation" 1

    Set-Content -Path $constraintsFile -Value $output -Encoding ASCII
    Write-Host "  Saved exact package pins to constraints-rocm.txt" -ForegroundColor Green
}

function Save-State {
    param(
        [string]$TargetDir,
        [string]$ScriptVer,
        [string]$RocmRel,
        [string]$PyVer,
        [string]$TorchVer,
        [string[]]$Components
    )

    $stateFile = Join-Path $TargetDir ".rocm-portable.json"
    $stateObj = [ordered]@{
        scriptVersion  = $ScriptVer
        rocmRelease    = $RocmRel
        pythonVersion  = $PyVer
        torchVersion   = $TorchVer
        components     = $Components
        installedAtUtc = [DateTime]::UtcNow.ToString("o")
    }

    $json = $stateObj | ConvertTo-Json -Depth 4
    Set-Content -Path $stateFile -Value $json -Encoding UTF8
}

function Invoke-Verify {
    param(
        [string]$TargetDir,
        [string]$TemplateDir
    )

    Write-Host "`n==> Running ROCm PyTorch verification test..." -ForegroundColor Cyan
    $pythonExe = Join-Path $TargetDir "python\python.exe"
    $verifyPy = Join-Path $TemplateDir "verify_rocm.py"

    if (-not (Test-Path -Path $verifyPy)) {
        throw [SetupException]::new(1, "verify_rocm.py template not found at $verifyPy")
    }

    & $pythonExe $verifyPy
    if ($LASTEXITCODE -ne 0) {
        throw [SetupException]::new(5, "Verification failed (GPU not detected or matmul failed). Review the output above.")
    }
}

function Invoke-Diagnose {
    param(
        [hashtable]$Config,
        [string]$TargetDir,
        [string]$ScriptVer
    )

    Write-Host "Collecting diagnostics..." -ForegroundColor Cyan
    $diagLines = [System.Collections.Generic.List[string]]::new()
    $diagLines.Add("=== ROCm Portable Windows Diagnostics ===")
    $diagLines.Add("Timestamp (UTC)   : $([DateTime]::UtcNow.ToString('u'))")
    $diagLines.Add("Script Version    : $ScriptVer")
    $diagLines.Add("Default Release   : $($Config['DefaultRelease'])")
    $diagLines.Add("PowerShell Version: $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))")

    # OS Info
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $osName = if ($os) { $os.Caption } else { [Environment]::OSVersion.VersionString }
    $osBuild = if ($os) { $os.BuildNumber } else { [Environment]::OSVersion.Version.Build }
    $diagLines.Add("OS Name           : $osName")
    $diagLines.Add("OS Build          : $osBuild")
    $diagLines.Add("64-bit OS         : $([Environment]::Is64BitOperatingSystem)")

    # Target dir
    $diagLines.Add("Install Dir       : $TargetDir")
    $diagLines.Add("Path Length       : $($TargetDir.Length) characters")

    # Disk
    try {
        $root = [System.IO.Path]::GetPathRoot($TargetDir)
        $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($root.TrimEnd('\'))'" -ErrorAction SilentlyContinue
        if ($disk) {
            $diagLines.Add("Free Disk Space   : $([math]::Round($disk.FreeSpace / 1GB, 2)) GB on $root")
        }
    } catch {
        $null = $_
    }

    # GPU Info
    $diagLines.Add("--- Detected Video Controllers ---")
    $gpus = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
    foreach ($g in $gpus) {
        $diagLines.Add("  - $($g.Name) (Driver: $($g.DriverVersion)) [Status: $($g.Status)]")
    }

    # Python info
    $pythonExe = Join-Path $TargetDir "python\python.exe"
    $pythonExists = Test-Path -Path $pythonExe
    $diagLines.Add("--- Python Installation ---")
    $diagLines.Add("Python Executable : $pythonExe (Exists: $pythonExists)")

    if ($pythonExists) {
        try {
            $pyVer = (& $pythonExe --version 2>&1).ToString().Trim()
            $diagLines.Add("Python Version    : $pyVer")
        } catch {
            $null = $_
        }

        $pthFile = Get-ChildItem -Path (Join-Path $TargetDir "python") -Filter "*._pth" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($pthFile) {
            $diagLines.Add("Pth File ($($pthFile.Name)) Content:")
            $pthLines = Get-Content -Path $pthFile.FullName
            foreach ($pl in $pthLines) {
                $diagLines.Add("    $pl")
            }
        }

        # Pip list for rocm/torch
        $diagLines.Add("--- Installed Packages (ROCm & PyTorch) ---")
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            $pkgList = (& $pythonExe -m pip list 2>$null)
            foreach ($line in $pkgList) {
                if ($line -match "torch|rocm|hip") {
                    $diagLines.Add("  $line")
                }
            }
        } catch {
            $diagLines.Add("  Failed to query pip list: $($_.Exception.Message)")
        }

        # Python probe
        $diagLines.Add("--- PyTorch Probe ---")
        $probeCode = @'
import sys
try:
    import torch
    print("torch_version:", torch.__version__)
    print("torch_file:", torch.__file__)
    print("hip_version:", getattr(torch.version, "hip", None))
    print("cuda_available:", torch.cuda.is_available())
    print("device_count:", torch.cuda.device_count())
    if torch.cuda.is_available():
        print("device_name:", torch.cuda.get_device_name(0))
except Exception as e:
    print("probe_error:", e)
'@
        try {
            $probeOutput = ($probeCode | & $pythonExe - 2>$null)
            foreach ($po in $probeOutput) {
                $diagLines.Add("  $po")
            }
        } catch {
            $diagLines.Add("  Probe failed to execute: $($_.Exception.Message)")
        } finally {
            $ErrorActionPreference = $prevEAP
        }
    }

    # Redact user paths and usernames safely
    $userProfile = $env:USERPROFILE
    $currentUser = $env:USERNAME
    $redactedLines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $diagLines) {
        $l = $line
        if (-not [string]::IsNullOrEmpty($userProfile)) {
            $l = $l -ireplace [regex]::Escape($userProfile), "<userprofile>"
        }
        if (-not [string]::IsNullOrEmpty($currentUser) -and $currentUser.Length -ge 2) {
            # Only redact username when in a path segment (surrounded by \ or /) to avoid corrupting GPU/package names
            $userPattern = '([\\/])' + [regex]::Escape($currentUser) + '([\\/''"\s]|$)'
            $l = $l -ireplace $userPattern, '$1<user>$2'
        }
        $redactedLines.Add($l)
    }

    # Write to diagnose.txt
    $diagFile = Join-Path $TargetDir "diagnose.txt"
    Set-Content -Path $diagFile -Value $redactedLines -Encoding UTF8

    # Print to console
    Write-Host "`n"
    foreach ($rl in $redactedLines) {
        Write-Host $rl
    }
    Write-Host "`nDiagnostics written to: $diagFile`n" -ForegroundColor Green

    # Guidance if cuda unavailable
    $hasCuda = $redactedLines | Where-Object { $_ -match "cuda_available:\s*True" }
    if (-not $hasCuda -and $pythonExists) {
        Write-Warning "PyTorch reports that ROCm/CUDA is NOT available on this system."
        Write-Host "Troubleshooting steps:" -ForegroundColor Yellow
        Write-Host "  1. Verify the AMD 'PyTorch on Windows' Adrenalin driver is installed from AMD's website." -ForegroundColor Yellow
        Write-Host "  2. Confirm your GPU is an officially supported model (e.g. RX 9060 XT, RX 9070, RX 7900 XTX, Ryzen AI 9/Max)." -ForegroundColor Yellow
        Write-Host "  3. Ensure you are executing code via .\run_rocm.bat or within .\shell_rocm.bat." -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------------
# Main Execution Entry Point
# ---------------------------------------------------------------------------
function Invoke-Main {
    [CmdletBinding()]
    param(
        [string]$TargetInstallDir,
        [string]$SelectedRelease,
        [switch]$SkipVision,
        [switch]$SkipAudio,
        [switch]$ForceReinstall,
        [switch]$SkipGpu,
        [switch]$NoVerification,
        [switch]$IsDryRun,
        [switch]$IsDiagnose,
        [switch]$Unattended
    )

    # Resolve TargetInstallDir to full absolute path without creating on disk
    $resolvedInstallDir = if ([string]::IsNullOrWhiteSpace($TargetInstallDir)) {
        if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    } else {
        $TargetInstallDir
    }
    $resolvedInstallDir = [System.IO.Path]::GetFullPath($resolvedInstallDir)

    $templateDir = Join-Path $PSScriptRoot "templates"
    if (-not (Test-Path -Path $templateDir)) {
        $templateDir = Join-Path $resolvedInstallDir "templates"
    }

    $configPath = Join-Path $PSScriptRoot "config\releases.psd1"
    if (-not (Test-Path -Path $configPath)) {
        $configPath = Join-Path $resolvedInstallDir "config\releases.psd1"
    }
    if (-not (Test-Path -Path $configPath)) {
        throw [SetupException]::new(1, "Release configuration file not found at: $configPath")
    }

    $config = Import-PowerShellDataFile -Path $configPath
    $releaseInfo = Get-ReleaseConfig -Config $config -RequestedRelease $SelectedRelease

    # Handle -Diagnose
    if ($IsDiagnose) {
        $pythonDir = Join-Path $resolvedInstallDir "python"
        $binDir    = Join-Path $resolvedInstallDir "bin"
        $tmpDir    = Join-Path $resolvedInstallDir ".tmp"
        $cacheDir  = Join-Path $resolvedInstallDir ".cache"

        $env:PATH                          = "$binDir;$pythonDir;$pythonDir\Scripts;$env:PATH"
        $env:PYTHONNOUSERSITE              = "1"
        $env:TEMP                          = $tmpDir
        $env:TMP                           = $tmpDir
        $env:XDG_CACHE_HOME                = $cacheDir
        $env:TORCH_HOME                    = "$cacheDir\torch"
        $env:HF_HOME                       = "$cacheDir\huggingface"
        $env:TRITON_CACHE_DIR              = "$cacheDir\triton"
        $env:MIOPEN_USER_DB_PATH           = "$cacheDir\miopen"
        $env:MIOPEN_CUSTOM_CACHE_DIR       = "$cacheDir\miopen"

        Invoke-Diagnose -Config $config -TargetDir $resolvedInstallDir -ScriptVer $Script:Version
        return
    }

    # Handle Preflight Checks
    Test-Preflight -Config $config -TargetDir $resolvedInstallDir -SelectedRelease $releaseInfo['Name'] -SkipGpu:$SkipGpu

    # Handle -DryRun
    if ($IsDryRun) {
        Invoke-DryRun -Config $config -ReleaseInfo $releaseInfo -TargetDir $resolvedInstallDir -IncludeVision:(-not $SkipVision) -IncludeAudio:(-not $SkipAudio)
        return
    }

    # Confirmation Prompt (unless -Yes)
    $includeVision = -not $SkipVision
    $includeAudio = -not $SkipAudio
    $compList = @("torch")
    if ($includeVision) { $compList += "torchvision" }
    if ($includeAudio) { $compList += "torchaudio" }

    if (-not $Unattended) {
        Write-Host "================== INSTALLATION PLAN ==================" -ForegroundColor Cyan
        Write-Host "Target Directory : $resolvedInstallDir"
        Write-Host "ROCm Release     : $($releaseInfo['Name'])"
        Write-Host "Components       : $($compList -join ', ')"
        Write-Host "Download Size    : ~3.5 GB"
        Write-Host "Peak Disk Space  : ~15 GB"
        Write-Host "=======================================================" -ForegroundColor Cyan

        # Check if running interactively
        $isInteractive = [Environment]::UserInteractive
        if (-not $isInteractive) {
            throw [SetupException]::new(2, "Running in non-interactive environment without -Yes. Aborting.")
        }

        $answer = Read-Host "Proceed with installation? [Y/n]"
        if (-not ([string]::IsNullOrWhiteSpace($answer) -or $answer.Trim().ToLower() -eq 'y')) {
            throw [SetupException]::new(2, "Installation cancelled by user.")
        }
    }

    # Ensure target directory exists on disk only after confirmation
    if (-not (Test-Path -Path $resolvedInstallDir)) {
        New-Item -ItemType Directory -Force -Path $resolvedInstallDir | Out-Null
    }

    # Transcript Logging
    $logDir = Join-Path $resolvedInstallDir "logs"
    if (-not (Test-Path -Path $logDir)) {
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    }
    $timestamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
    $transcriptPath = Join-Path $logDir "setup-$timestamp.log"
    $transcriptActive = $false
    try {
        Start-Transcript -Path $transcriptPath | Out-Null
        $transcriptActive = $true
    } catch {
        Write-Warning "Unable to start transcript logging: $($_.Exception.Message)"
    }

    try {
        # Retention: Keep 5 newest logs, delete older
        $oldLogs = Get-ChildItem -Path $logDir -Filter "setup-*.log" | Sort-Object LastWriteTime -Descending | Select-Object -Skip 5
        foreach ($ol in $oldLogs) {
            Remove-Item -Path $ol.FullName -Force -ErrorAction SilentlyContinue
        }

        # Directories
        $pythonDir = Join-Path $resolvedInstallDir "python"
        $tmpDir    = Join-Path $resolvedInstallDir ".tmp"
        $cacheDir  = Join-Path $resolvedInstallDir ".cache"

        # Handle -Reinstall
        $stateFile = Join-Path $resolvedInstallDir ".rocm-portable.json"
        $constraintsFile = Join-Path $resolvedInstallDir "constraints-rocm.txt"
        if ($ForceReinstall) {
            Write-Host "`n[-Reinstall] Removing existing .\python, state file, and constraints..." -ForegroundColor Yellow
            if (Test-Path -Path $pythonDir) { Remove-Item -Path $pythonDir -Recurse -Force }
            if (Test-Path -Path $stateFile) { Remove-Item -Path $stateFile -Force }
            if (Test-Path -Path $constraintsFile) { Remove-Item -Path $constraintsFile -Force }
        }

        # Read existing state
        $existingState = @{}
        if (Test-Path -Path $stateFile) {
            try {
                $jsonObj = Get-Content -Path $stateFile -Raw | ConvertFrom-Json
                foreach ($prop in $jsonObj.PSObject.Properties) {
                    $existingState[$prop.Name] = $prop.Value
                }
            } catch {
                $null = $_
            }
        }

        # Check if changing release on existing install
        if ($existingState.ContainsKey('rocmRelease') -and $existingState['rocmRelease'] -ne $releaseInfo['Name']) {
            Write-Host "`nSwitching ROCm release from $($existingState['rocmRelease']) to $($releaseInfo['Name'])..." -ForegroundColor Yellow
            if (Test-Path -Path $constraintsFile) { Remove-Item -Path $constraintsFile -Force }
        }

        # Create isolated subdirectories
        foreach ($d in @($tmpDir, "$cacheDir\torch", "$cacheDir\huggingface", "$cacheDir\triton", "$cacheDir\miopen")) {
            if (-not (Test-Path -Path $d)) {
                New-Item -ItemType Directory -Force -Path $d | Out-Null
            }
        }

        # Set process-scoped isolated environment
        $env:PATH                    = "$pythonDir;$pythonDir\Scripts;$env:PATH"
        $env:PYTHONNOUSERSITE        = "1"
        $env:TEMP                    = $tmpDir
        $env:TMP                     = $tmpDir
        $env:XDG_CACHE_HOME          = $cacheDir
        $env:TORCH_HOME              = "$cacheDir\torch"
        $env:HF_HOME                 = "$cacheDir\huggingface"
        $env:TRITON_CACHE_DIR        = "$cacheDir\triton"
        $env:MIOPEN_USER_DB_PATH     = "$cacheDir\miopen"
        $env:MIOPEN_CUSTOM_CACHE_DIR = "$cacheDir\miopen"
        $env:PIP_NO_CACHE_DIR        = "1"
        $env:PIP_CONFIG_FILE         = "NUL"
        $env:PIP_DISABLE_PIP_VERSION_CHECK = "1"
        # Temporarily bypass PIP_CONSTRAINT during installer's own pip runs
        $env:PIP_CONSTRAINT          = $null

        # Step 1: Python
        Install-Python -Config $config -TargetDir $resolvedInstallDir

        # Step 2: Configure _pth
        Initialize-PythonPath -TargetDir $resolvedInstallDir

        # Step 2b: Python C/C++ Headers and Libs (dev.msi)
        Install-PythonDevHeaders -Config $config -TargetDir $resolvedInstallDir

        # Step 3: Bootstrap Pip
        Install-Pip -Config $config -TargetDir $resolvedInstallDir

        # Step 4a: ROCm SDK
        Install-RocmSdk -ReleaseInfo $releaseInfo -TargetDir $resolvedInstallDir -State $existingState

        # Step 4b: PyTorch
        Install-Torch -ReleaseInfo $releaseInfo -TargetDir $resolvedInstallDir -IncludeVision:$includeVision -IncludeAudio:$includeAudio -State $existingState

        # Step 5: Launchers into bin/
        Write-Launchers -TemplateDir $templateDir -TargetDir $resolvedInstallDir

        # Step 6: Constraints
        Write-Constraints -TargetDir $resolvedInstallDir

        # Get installed torch version for state record
        $pythonExe = Join-Path $pythonDir "python.exe"
        $installedTorchVer = ""
        try {
            $installedTorchVer = (& $pythonExe -c "import torch; print(torch.__version__)").Trim()
        } catch {
            $null = $_
        }

        # Save State
        Save-State -TargetDir $resolvedInstallDir -ScriptVer $Script:Version -RocmRel $releaseInfo['Name'] -PyVer $config['PythonVersion'] -TorchVer $installedTorchVer -Components $compList

        # Step 7: Verify
        if (-not $NoVerification) {
            Invoke-Verify -TargetDir $resolvedInstallDir -TemplateDir $templateDir
        } else {
            Write-Host "`nVerification step skipped (-SkipVerify)." -ForegroundColor Yellow
        }

        # Cleanup .tmp
        Get-ChildItem -Path $tmpDir -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

        Write-Host "`n==> ROCm Portable installation completed successfully!" -ForegroundColor Green
        Write-Host "Launchers available in: $(Join-Path $resolvedInstallDir 'bin')" -ForegroundColor Cyan
        Write-Host "  Run Python script: .\bin\run_rocm.bat <script.py>" -ForegroundColor Cyan
        Write-Host "  Install packages : .\bin\pip_rocm.bat install <package>" -ForegroundColor Cyan
        Write-Host "  Distributed train: .\bin\torchrun_rocm.bat <train.py>" -ForegroundColor Cyan
        Write-Host "  Interactive shell: .\bin\shell_rocm.bat" -ForegroundColor Cyan
        Write-Host "  PowerShell env   : . .\bin\env_rocm.ps1`n" -ForegroundColor Cyan
        Write-Host "[TIP] To make these commands globally accessible from ANY directory without prefixing:" -ForegroundColor Yellow
        Write-Host "      Run: .\scripts\add_to_path.ps1" -ForegroundColor Yellow
        Write-Host "      (This adds 'bin\' to your Windows User PATH while keeping global Python undisturbed.)`n" -ForegroundColor Yellow
    } finally {
        if ($transcriptActive) {
            try { Stop-Transcript | Out-Null } catch { $null = $_ }
        }
    }
}

# Only execute Invoke-Main if this script is run directly, not when dot-sourced for testing
if ($MyInvocation.InvocationName -ne '.') {
    $scriptExit = 0
    try {
        Invoke-Main -TargetInstallDir $InstallDir `
            -SelectedRelease $RocmRelease `
            -SkipVision:$NoVision `
            -SkipAudio:$NoAudio `
            -ForceReinstall:$Reinstall `
            -SkipGpu:$SkipGpuCheck `
            -NoVerification:$SkipVerify `
            -IsDryRun:$DryRun `
            -IsDiagnose:$Diagnose `
            -Unattended:$Yes
    } catch [SetupException] {
        $scriptExit = $_.Exception.ExitCode
        Write-Error $_.Exception.Message
    } catch {
        $scriptExit = 1
        Write-Error "Unexpected fatal error: $($_.Exception.Message)"
    }
    if ($scriptExit -ne 0) {
        exit $scriptExit
    }
}