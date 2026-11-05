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

.PARAMETER Install
    Trigger environment installation (default action).

.PARAMETER NoVision
    Skip installation of torchvision.

.PARAMETER NoAudio
    Skip installation of torchaudio.

.PARAMETER WithTriton
    Download and install version-matched triton-windows wheel from PyPI for torch.compile acceleration.
    If system MSVC is not detected, automatically installs portable MSVC (~130 MB).

.PARAMETER WithMsvc
    Download and install lightweight portable MSVC toolchain (~130 MB) into .\msvc for MIOpen JIT hardware acceleration.

.PARAMETER NoMsvc
    Explicitly prevent installing portable MSVC even if Triton is requested.

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

.PARAMETER Help
    Display this help information.

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
    [switch]$Install,
    [switch]$NoVision,
    [switch]$NoAudio,
    [switch]$WithTriton,
    [switch]$WithMsvc,
    [switch]$NoMsvc,
    [switch]$Reinstall,
    [switch]$SkipGpuCheck,
    [switch]$SkipVerify,
    [switch]$DryRun,
    [switch]$Diagnose,
    [Alias("y")]
    [switch]$Yes,
    [Alias("h")]
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Ensure TLS 1.2 and Utility module
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Import-Module Microsoft.PowerShell.Utility -ErrorAction SilentlyContinue

$Script:Version = "0.3.0"

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

function Resolve-OfficialGetPipSha256 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ActualSha,
        [string]$CanonicalCatalogUrl = "https://raw.githubusercontent.com/ssrplays121/WinROCm-PyTorch/main/config/releases.psd1"
    )

    $targetSha = $ActualSha.Trim().ToUpperInvariant()

    # Tier 1: Canonical WinROCm repository remote catalog
    try {
        $remoteText = $null
        if ($CanonicalCatalogUrl -like "file://*") {
            $localFilePath = [System.Uri]::new($CanonicalCatalogUrl).LocalPath
            $remoteText = [System.IO.File]::ReadAllText($localFilePath)
        } else {
            $webReq = [System.Net.HttpWebRequest]::Create($CanonicalCatalogUrl)
            $webReq.Timeout = 4000
            $webReq.Method = "GET"
            $webReq.UserAgent = "WinROCm-Portable"
            $resp = $webReq.GetResponse()
            $reader = [System.IO.StreamReader]::new($resp.GetResponseStream())
            $remoteText = $reader.ReadToEnd()
            $reader.Close()
            $resp.Close()
        }

        if ($remoteText -and ($remoteText -match "GetPipSha256\s*=\s*['\""]([A-Fa-f0-9]{64})['\""]")) {
            $remoteSha = $Matches[1].ToUpperInvariant()
            if ($remoteSha -eq $targetSha) {
                return [PSCustomObject]@{
                    Verified = $true
                    Source   = "Canonical WinROCm Catalog ($CanonicalCatalogUrl)"
                    Sha256   = $remoteSha
                }
            }
        }
    } catch {
        $null = $_
    }

    # Tier 2: Official PyPA GitHub repository commit API for public/get-pip.py
    try {
        $headers = @{
            'User-Agent' = 'WinROCm-Portable'
            'Accept'     = 'application/vnd.github.v3+json'
        }
        $commitResp = Invoke-RestMethod -Uri "https://api.github.com/repos/pypa/get-pip/commits?path=public/get-pip.py&per_page=1" -Headers $headers -TimeoutSec 5 -ErrorAction Stop
        if ($commitResp -and $commitResp.Count -gt 0 -and $commitResp[0].sha) {
            $commitSha = [string]$commitResp[0].sha
            $rawUrl = "https://raw.githubusercontent.com/pypa/get-pip/$commitSha/public/get-pip.py"
            $tempCheck = [System.IO.Path]::GetTempFileName()
            try {
                $null = Invoke-WebRequest -Uri $rawUrl -OutFile $tempCheck -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
                if (Test-Path -Path $tempCheck) {
                    $pypaSha = (Get-FileHash -Path $tempCheck -Algorithm SHA256).Hash.ToUpperInvariant()
                    if ($pypaSha -eq $targetSha) {
                        return [PSCustomObject]@{
                            Verified  = $true
                            Source    = "PyPA Official Git Commit ($commitSha)"
                            Sha256    = $pypaSha
                            CommitSha = $commitSha
                        }
                    }
                }
            } finally {
                Remove-Item -Path $tempCheck -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {
        $null = $_
    }

    return [PSCustomObject]@{
        Verified = $false
        Source   = $null
        Sha256   = $null
    }
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

    # 12. MSVC C++ Build Tools & Windows SDK (Advisory Check)
    $hasPortableMsvc = $false
    $hasSystemMsvc = $false
    $portableMsvcDir = Join-Path $TargetDir "msvc"
    if (Test-Path -Path (Join-Path $portableMsvcDir "VC\Tools\MSVC\*\include\type_traits")) {
        $hasPortableMsvc = $true
    }

    if ($hasPortableMsvc) {
        Write-Host "  [Pass] Portable MSVC toolchain detected (.\msvc)" -ForegroundColor Green
    } else {
        $progRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432) | Where-Object { -not [string]::IsNullOrEmpty($_) } | Select-Object -Unique
        foreach ($r in $progRoots) {
            $msvcMatches = Get-ChildItem -Path (Join-Path $r "Microsoft Visual Studio\*\*\VC\Tools\MSVC\*\include\type_traits") -ErrorAction SilentlyContinue
            if ($msvcMatches) {
                $hasSystemMsvc = $true
                break
            }
        }
        if ($hasSystemMsvc) {
            Write-Host "  [Pass] Visual Studio C++ Build Tools detected (MIOpen JIT & Triton ready)" -ForegroundColor Green
        } else {
            Write-Host "  [Notice] Check 12: Visual Studio C++ Build Tools (MSVC) not detected on your system." -ForegroundColor Yellow
            Write-Host "           * What this is:" -ForegroundColor Gray
            Write-Host "             A C++ compiler needed for maximum performance and AI model acceleration." -ForegroundColor Gray
            Write-Host "           * How it affects your installation:" -ForegroundColor Gray
            Write-Host "             - Triton Acceleration (torch.compile): Requires a C++ compiler to generate fast GPU kernels." -ForegroundColor Gray
            Write-Host "             - MIOpen JIT: Hardware kernel compilation for BatchNorm/Conv2d will fall back to native ATen kernels." -ForegroundColor Gray
            Write-Host "           * What setup can do for you:" -ForegroundColor Gray
            Write-Host "             - You do NOT need to install the heavy Visual Studio IDE (4-60 GB)." -ForegroundColor Gray
            Write-Host "             - Setup can automatically download and unpack a lightweight, portable MSVC toolchain" -ForegroundColor Gray
            Write-Host "               (~130 MB, self-contained in .\msvc, no administrator rights needed)." -ForegroundColor Gray
            $warnings += "Check 12 [Notice - MSVC Build Tools]: Visual Studio C++ Build Tools not detected. Setup can install portable MSVC (~130 MB) automatically."
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
        [bool]$IncludeAudio,
        [bool]$IncludeTriton = $false,
        [bool]$IncludeMsvc = $false
    )

    $rName = $ReleaseInfo['Name']
    $rCfg = $ReleaseInfo['Config']
    $baseUrl = $rCfg['BaseUrl']

    $compNames = @("torch")
    if ($IncludeVision) { $compNames += "torchvision" }
    if ($IncludeAudio) { $compNames += "torchaudio" }
    if ($IncludeTriton) { $compNames += "triton-windows" }
    if ($IncludeMsvc) { $compNames += "msvc" }

    $dlEstimate = if ($IncludeMsvc) { "~3.65 GB" } else { "~3.5 GB" }
    $diskEstimate = if ($IncludeMsvc) { "~11.5 GB installed, 15.5 GB peak" } else { "~11 GB installed, 15 GB peak" }

    Write-Host "================== DRY RUN PLAN ==================" -ForegroundColor Cyan
    Write-Host "ROCm Release        : $rName"
    Write-Host "Install Directory   : $TargetDir"
    Write-Host "Python Version      : $($Config['PythonVersion'])"
    Write-Host "Components          : $($compNames -join ', ')"
    Write-Host "Triton Acceleration : $(if ($IncludeTriton) { 'Enabled (triton-windows for torch.compile)' } else { 'Disabled (eager mode only)' })"
    Write-Host "MSVC Toolchain      : $(if ($IncludeMsvc) { 'Enabled (portable MSVC in .\msvc)' } else { 'System / Safe Eager fallback' })"
    Write-Host "Download Size (est) : $dlEstimate"
    Write-Host "Disk Required (est) : $diskEstimate"
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

        # Strict cryptographic verification against known pin or authoritative upstream sources
        $actualSha = (Get-FileSha256 -FilePath $getPipPy).ToUpperInvariant()
        $expectedShaUpper = $expectedSha.Trim().ToUpperInvariant()

        if ($actualSha -eq $expectedShaUpper) {
            Write-Host "  get-pip.py checksum verified against pinned release ($actualSha)." -ForegroundColor Green
        } else {
            Write-Warning "get-pip.py SHA256 ($actualSha) differs from local pin ($expectedShaUpper)."
            Write-Host "  Resolving official hash from authoritative upstream sources (canonical repo & PyPA Git)..." -ForegroundColor Yellow

            $authResult = Resolve-OfficialGetPipSha256 -ActualSha $actualSha
            if ($authResult.Verified) {
                Write-Host "  [Security Verified] get-pip.py SHA256 cryptographically confirmed via $($authResult.Source)." -ForegroundColor Green
                try {
                    $cfgFile = Join-Path $TargetDir "config\releases.psd1"
                    if (Test-Path -Path $cfgFile) {
                        $rawCfg = [System.IO.File]::ReadAllText($cfgFile)
                        $rawCfg = $rawCfg -replace "GetPipSha256\s*=\s*['\""][^'\""]+['\""]", "GetPipSha256      = '$($authResult.Sha256)'"
                        [System.IO.File]::WriteAllText($cfgFile, $rawCfg, [System.Text.UTF8Encoding]::new($false))
                        Write-Host "  Updated local config\releases.psd1 with verified official checksum." -ForegroundColor Gray
                    }
                } catch {
                    Write-Warning "Could not update local config\releases.psd1: $($_.Exception.Message)"
                }
            } else {
                Remove-Item -Path $getPipPy -Force -ErrorAction SilentlyContinue
                throw [SetupException]::new(3, "CRITICAL: get-pip.py SHA256 ($actualSha) failed cryptographic verification against all official PyPA sources! Expected: $expectedShaUpper. Aborting to protect system integrity.")
            }
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
            $develInc = Join-Path $pythonDir "Lib\site-packages\_rocm_sdk_devel\include\hip\hip_runtime.h"
            if (-not (Test-Path -Path $develInc)) {
                Write-Host "  Expanding ROCm developer headers (rocm-sdk init)..." -ForegroundColor Yellow
                & $pythonExe -m rocm_sdk init
                Assert-LastExit "ROCm SDK init" 4
            }
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

    $develInc = Join-Path $pythonDir "Lib\site-packages\_rocm_sdk_devel\include\hip\hip_runtime.h"
    if (-not (Test-Path -Path $develInc)) {
        Write-Host "  Expanding ROCm developer headers (rocm-sdk init)..." -ForegroundColor Yellow
        & $pythonExe -m rocm_sdk init
        Assert-LastExit "ROCm SDK init" 4
    }
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

function Install-PortableMsvc {
    param(
        [string]$TargetDir
    )

    $pythonDir = Join-Path $TargetDir "python"
    $pythonExe = Join-Path $pythonDir "python.exe"
    $msvcDir   = Join-Path $TargetDir "msvc"
    $scriptSrc = Join-Path $PSScriptRoot "scripts\portable-msvc.py"
    if (-not (Test-Path -Path $scriptSrc)) {
        $scriptSrc = Join-Path $TargetDir "scripts\portable-msvc.py"
    }

    if (-not (Test-Path -Path $scriptSrc)) {
        throw [SetupException]::new(1, "Required portable MSVC installer script not found: $scriptSrc")
    }

    Write-Host "`n[4b/5] Installing lightweight Portable MSVC toolchain (~130 MB download)..." -ForegroundColor Yellow
    Write-Host "  Target directory: $msvcDir" -ForegroundColor Cyan

    & $pythonExe $scriptSrc --accept-license --output $msvcDir --target x64 --host x64
    Assert-LastExit "Portable MSVC toolchain installation" 4

    # Verification: check cl.exe and headers
    $clMatches = Get-ChildItem -Path (Join-Path $msvcDir "VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe") -ErrorAction SilentlyContinue
    $headerMatches = Get-ChildItem -Path (Join-Path $msvcDir "VC\Tools\MSVC\*\include\type_traits") -ErrorAction SilentlyContinue
    if (-not $clMatches -or -not $headerMatches) {
        throw [SetupException]::new(4, "Portable MSVC installation failed: cl.exe or C++ headers missing in $msvcDir")
    }

    Write-Host "  [Pass] Portable MSVC toolchain installed and verified." -ForegroundColor Green
}

function Install-Triton {
    param(
        [string]$TargetDir
    )

    $pythonDir = Join-Path $TargetDir "python"
    $pythonExe = Join-Path $pythonDir "python.exe"

    Write-Host "`n[4c/5] Installing version-matched triton-windows..." -ForegroundColor Yellow
    $torchMinor = (& $pythonExe -c "import torch; v=torch.__version__.split('.'); print(f'{v[0]}.{v[1]}')" 2>$null).Trim()
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
    Assert-LastExit "triton-windows installation" 4
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

    $launcherFiles = @("env_rocm.bat", "run_rocm.bat", "pip_rocm.bat", "shell_rocm.bat", "torchrun_rocm.bat", "env_rocm.ps1", "rocm.bat", "update_rocm.bat", "status_rocm.bat", "verify_rocm.bat", "reinstall_rocm.bat")

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

    # Install sitecustomize.py runtime shim into python\Lib\site-packages\
    $sitePackages = Join-Path $TargetDir "python\Lib\site-packages"
    $siteShimSrc  = Join-Path $TemplateDir "sitecustomize.py"
    if ((Test-Path -Path $siteShimSrc) -and (Test-Path -Path $sitePackages)) {
        Copy-Item -Path $siteShimSrc -Destination (Join-Path $sitePackages "sitecustomize.py") -Force
        Write-Host "  Installed sitecustomize.py runtime shim to site-packages." -ForegroundColor Green
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
want = {"torch", "torchvision", "torchaudio", "rocm", "rocm-sdk-core", "rocm-sdk-devel", "rocm-sdk-libraries-custom", "triton", "triton-windows"}
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
        $probeCmd = "import os, sys, torch; print('torch_version:', torch.__version__); print('torch_file:', torch.__file__); print('hip_version:', getattr(torch.version, 'hip', None)); print('cuda_version:', getattr(torch.version, 'cuda', None)); print('cuda_available:', torch.cuda.is_available()); print('device_count:', torch.cuda.device_count()); print('device_name:', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'None'); print('rocm_path:', os.environ.get('ROCM_PATH', 'None')); print('hipblaslt_prefer:', os.environ.get('TORCH_BLAS_PREFER_HIPBLASLT', 'None')); print('tunable_support:', getattr(torch.cuda, 'tunable', None) is not None); print('cudnn_miopen_enabled:', torch.backends.cudnn.enabled); (lambda: print('triton_version:', __import__('triton').__version__) if __import__('importlib.util').util.find_spec('triton') else print('triton_version: Not installed'))()"
        try {
            $probeOutput = (& $pythonExe -c $probeCmd 2>&1)
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
function Show-SetupHelp {
    Write-Host "`n================ WINROCM-PYTORCH INSTALLER HELP ================" -ForegroundColor Cyan
    Write-Host "Usage:"
    Write-Host "  setup.bat install [options]"
    Write-Host "  powershell -File setup_rocm_portable.ps1 [-InstallDir <path>] [options]"
    Write-Host "`nDescription:"
    Write-Host "  Automates a fully isolated, portable Python 3.12 ROCm PyTorch installation"
    Write-Host "  for modern AMD Radeon and Ryzen AI GPUs on Windows 11."
    Write-Host "`nOptions:"
    Write-Host "  -Install            Trigger environment installation (default action)."
    Write-Host "  -InstallDir <path>  Target directory for installation (default: script root)."
    Write-Host "  -RocmRelease <ver>  Target ROCm release version (e.g. 7.2, 7.2.1)."
    Write-Host "  -WithTriton         Include triton-windows wheel for torch.compile acceleration."
    Write-Host "  -WithMsvc           Install portable MSVC toolchain (~130 MB) into .\msvc for MIOpen/Triton."
    Write-Host "  -NoMsvc             Prevent installing portable MSVC even if Triton is requested."
    Write-Host "  -NoVision           Skip torchvision installation."
    Write-Host "  -NoAudio            Skip torchaudio installation."
    Write-Host "  -Reinstall          Wipe existing python/ environment and reinstall cleanly."
    Write-Host "  -DryRun             Validate prerequisites and download URLs without installing."
    Write-Host "  -Diagnose           Collect diagnostic telemetry into diagnose.txt."
    Write-Host "  -SkipGpuCheck       Bypass GPU hardware compatibility verification."
    Write-Host "  -SkipVerify         Skip post-install verification test suite."
    Write-Host "  -y, -Yes            Unattended mode (skip interactive prompts)."
    Write-Host "  -Help, -h           Display this help information."
    Write-Host "================================================================`n" -ForegroundColor Cyan
}

function Invoke-Main {
    [CmdletBinding()]
    param(
        [string]$TargetInstallDir,
        [string]$SelectedRelease,
        [switch]$InstallMode,
        [switch]$SkipVision,
        [switch]$SkipAudio,
        [switch]$IncludeTriton,
        [switch]$IncludeMsvc,
        [switch]$NoMsvc,
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

        $rocmCustomLib = Join-Path $resolvedInstallDir "python\Lib\site-packages\_rocm_sdk_libraries_custom\bin"
        $rocmCoreLib   = Join-Path $resolvedInstallDir "python\Lib\site-packages\_rocm_sdk_core\bin"
        $rocmDevelLib  = Join-Path $resolvedInstallDir "python\Lib\site-packages\_rocm_sdk_devel\bin"
        $rocmDevelRoot = Join-Path $resolvedInstallDir "python\Lib\site-packages\_rocm_sdk_devel"

        $env:PATH                          = "$binDir;$pythonDir;$pythonDir\Scripts;$rocmCustomLib;$rocmCoreLib;$rocmDevelLib;$env:PATH"
        $env:TORCH_BLAS_PREFER_HIPBLASLT   = "1"
        if (Test-Path -Path $rocmDevelRoot) {
            $env:ROCM_PATH = $rocmDevelRoot
            $env:HIP_PATH  = $rocmDevelRoot
        }
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

    # Check for existing MSVC toolchain on system or in portable directory
    $hasAnyMsvc = (Test-Path -Path (Join-Path $resolvedInstallDir "msvc\VC\Tools\MSVC\*\include\type_traits"))
    if (-not $hasAnyMsvc) {
        $progRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432) | Where-Object { -not [string]::IsNullOrEmpty($_) } | Select-Object -Unique
        foreach ($r in $progRoots) {
            if (Get-ChildItem -Path (Join-Path $r "Microsoft Visual Studio\*\*\VC\Tools\MSVC\*\include\type_traits") -ErrorAction SilentlyContinue) {
                $hasAnyMsvc = $true
                break
            }
        }
    }

    # If Triton is requested and no MSVC exists, automatically include portable MSVC unless explicitly prohibited
    if ($IncludeTriton -and -not $NoMsvc -and -not $hasAnyMsvc) {
        $IncludeMsvc = $true
    }

    # Handle -DryRun
    if ($IsDryRun) {
        Invoke-DryRun -Config $config -ReleaseInfo $releaseInfo -TargetDir $resolvedInstallDir -IncludeVision:(-not $SkipVision) -IncludeAudio:(-not $SkipAudio) -IncludeTriton:$IncludeTriton -IncludeMsvc:$IncludeMsvc
        return
    }

    # Installation mode (default execution or explicit -Install switch)
    if ($InstallMode) {
        Write-Verbose -Message "Installation explicitly requested via -Install."
    }

    # Confirmation Prompt (unless -Yes)
    $includeVision = -not $SkipVision
    $includeAudio = -not $SkipAudio
    $compList = @("torch")
    if ($includeVision) { $compList += "torchvision" }
    if ($includeAudio) { $compList += "torchaudio" }
    if ($IncludeTriton) { $compList += "triton-windows" }
    if ($IncludeMsvc) { $compList += "msvc" }

    if (-not $Unattended) {
        $isInteractive = [Environment]::UserInteractive

        if (-not $isInteractive) {
            throw [SetupException]::new(2, "Running in non-interactive environment without -Yes. Aborting.")
        }

        # If user did not pass -WithTriton or -WithMsvc, present plain-English acceleration options
        if (-not $IncludeTriton -and -not $IncludeMsvc) {
            if (-not $hasAnyMsvc) {
                Write-Host "`n======================= ACCELERATION & TOOLCHAIN SELECTION =======================" -ForegroundColor Cyan
                Write-Host "Choose the acceleration level for your ROCm PyTorch installation:`n" -ForegroundColor Gray
                Write-Host "  [1] Triton + Portable MSVC (Recommended for ComfyUI / SD / LLMs)" -ForegroundColor Green
                Write-Host "      * Up to 2x faster model generation using 'torch.compile'" -ForegroundColor Gray
                Write-Host "      * Automatically installs portable MSVC (~130 MB) into .\msvc" -ForegroundColor Gray
                Write-Host "      * Enables hardware MIOpen JIT compilation (no admin rights needed)`n" -ForegroundColor Gray
                Write-Host "  [2] Portable MSVC Only (Hardware MIOpen JIT, Standard Eager PyTorch)" -ForegroundColor Yellow
                Write-Host "      * Automatically installs portable MSVC (~130 MB) into .\msvc" -ForegroundColor Gray
                Write-Host "      * Enables hardware MIOpen JIT for BatchNorm & Conv2d" -ForegroundColor Gray
                Write-Host "      * Keeps PyTorch in standard eager execution (does not install Triton)`n" -ForegroundColor Gray
                Write-Host "  [3] Standard Minimal (Eager Mode Only, Safe Fallbacks, No MSVC)" -ForegroundColor White
                Write-Host "      * Fastest install and smallest download (~0 MB extra download)" -ForegroundColor Gray
                Write-Host "      * BatchNorm automatically uses safe ATen kernel fallback" -ForegroundColor Gray
                Write-Host "      * 'torch.compile' / Triton acceleration will be disabled`n" -ForegroundColor Gray
                Write-Host "==================================================================================" -ForegroundColor Cyan

                $ans = Read-Host "Please select an option [1-3] (Default: 1)"
                if ([string]::IsNullOrWhiteSpace($ans) -or $ans.Trim() -eq '1') {
                    $IncludeTriton = $true
                    $IncludeMsvc = $true
                    $compList += "triton-windows"
                    $compList += "msvc"
                    Write-Host "  Option 1 selected: Triton acceleration + Portable MSVC enabled." -ForegroundColor Green
                } elseif ($ans.Trim() -eq '2') {
                    $IncludeMsvc = $true
                    $compList += "msvc"
                    Write-Host "  Option 2 selected: Portable MSVC enabled (eager mode PyTorch)." -ForegroundColor Green
                } else {
                    Write-Host "  Option 3 selected: Standard minimal eager mode." -ForegroundColor Gray
                }
            } else {
                Write-Host "`n--- Optional: Triton Acceleration ---" -ForegroundColor Yellow
                Write-Host "Triton enables 'torch.compile' support on AMD ROCm for faster AI models" -ForegroundColor Gray
                Write-Host "(e.g., ComfyUI, Stable Diffusion, LLMs). System MSVC detected." -ForegroundColor Gray
                $ansTriton = Read-Host "Include Triton (triton-windows)? [Y/n]"
                if ([string]::IsNullOrWhiteSpace($ansTriton) -or $ansTriton.Trim().ToLower() -eq 'y') {
                    $IncludeTriton = $true
                    $compList += "triton-windows"
                    Write-Host "  Triton acceleration enabled in plan." -ForegroundColor Green
                }
            }
        }

        $dlEst = if ($IncludeMsvc) { "~3.65 GB" } else { "~3.5 GB" }
        $diskEst = if ($IncludeMsvc) { "~15.5 GB" } else { "~15 GB" }

        Write-Host "================== INSTALLATION PLAN ==================" -ForegroundColor Cyan
        Write-Host "Target Directory : $resolvedInstallDir"
        Write-Host "ROCm Release     : $($releaseInfo['Name'])"
        Write-Host "Components          : $($compList -join ', ')"
        Write-Host "Triton Acceleration : $(if ($IncludeTriton) { 'Enabled (triton-windows for torch.compile)' } else { 'Disabled (eager mode only)' })"
        Write-Host "MSVC Toolchain      : $(if ($IncludeMsvc) { 'Enabled (portable MSVC in .\msvc, ~130 MB)' } elseif ($hasAnyMsvc) { 'System Visual Studio detected' } else { 'Safe Eager ATen fallback' })"
        Write-Host "Download Size    : $dlEst"
        Write-Host "Peak Disk Space  : $diskEst"
        Write-Host "=======================================================" -ForegroundColor Cyan


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
            $msvcDir = Join-Path $resolvedInstallDir "msvc"
            if (Test-Path -Path $msvcDir) {
                Write-Host "[-Reinstall] Removing existing .\msvc..." -ForegroundColor Yellow
                Remove-Item -Path $msvcDir -Recurse -Force
            }
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
        $rocmCustomLib = Join-Path $resolvedInstallDir "python\Lib\site-packages\_rocm_sdk_libraries_custom\bin"
        $rocmCoreLib   = Join-Path $resolvedInstallDir "python\Lib\site-packages\_rocm_sdk_core\bin"
        $rocmDevelLib  = Join-Path $resolvedInstallDir "python\Lib\site-packages\_rocm_sdk_devel\bin"
        $rocmDevelRoot = Join-Path $resolvedInstallDir "python\Lib\site-packages\_rocm_sdk_devel"

        $env:PATH                    = "$pythonDir;$pythonDir\Scripts;$rocmCustomLib;$rocmCoreLib;$rocmDevelLib;$env:PATH"
        $env:TORCH_BLAS_PREFER_HIPBLASLT = "1"
        if (Test-Path -Path $rocmDevelRoot) {
            $env:ROCM_PATH = $rocmDevelRoot
            $env:HIP_PATH  = $rocmDevelRoot
        }
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

        # Step 4b2: Portable MSVC (optional / auto-installed for Triton or MIOpen JIT)
        if ($IncludeMsvc) {
            Install-PortableMsvc -TargetDir $resolvedInstallDir
        }

        # Step 4c: Triton (optional)
        if ($IncludeTriton) {
            Install-Triton -TargetDir $resolvedInstallDir
        }

        # Step 5: Launchers into bin/
        Write-Launchers -TemplateDir $templateDir -TargetDir $resolvedInstallDir

        # Step 6: Constraints
        Write-Constraints -TargetDir $resolvedInstallDir

        # Get installed torch version for state record (using fast metadata check to avoid GPU warnings)
        $pythonExe = Join-Path $pythonDir "python.exe"
        $installedTorchVer = ""
        try {
            $installedTorchVer = (& $pythonExe -c "import importlib.metadata; print(importlib.metadata.version('torch'))").Trim()
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
    if ($Help -or ($InstallDir -in @('-h', '-help', '--help', '/?', 'help'))) {
        Show-SetupHelp
        exit 0
    }
    $scriptExit = 0
    try {
        Invoke-Main -TargetInstallDir $InstallDir `
            -SelectedRelease $RocmRelease `
            -InstallMode:$Install `
            -SkipVision:$NoVision `
            -SkipAudio:$NoAudio `
            -IncludeTriton:$WithTriton `
            -IncludeMsvc:$WithMsvc `
            -NoMsvc:$NoMsvc `
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
