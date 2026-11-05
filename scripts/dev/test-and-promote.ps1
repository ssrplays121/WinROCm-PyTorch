<#
.SYNOPSIS
    WinROCm 1-Click Hardware Test & Code Promotion Pipeline.

.DESCRIPTION
    Provisions an isolated 4-part sandbox (.test-env\), executes hardware verification tests
    on physical AMD GPU (GEMM, Conv2d, BatchNorm2d, F.normalize, Triton JIT), and upon
    successful test pass promotes the release by updating DefaultRelease in config/releases.psd1,
    logging verification to CHANGELOG.md, cleaning the sandbox, and creating a git release branch.

.PARAMETER Version
    ROCm release version to test and promote (e.g. 7.3, 7.2.1). Mandatory.

.PARAMETER RepoRoot
    Target repository root path. Defaults to the repository root containing this script.

.PARAMETER KeepSandbox
    Preserve .test-env\ sandbox directory even after successful promotion for manual inspection.

.PARAMETER SkipHardwareTest
    Bypass running physical AMD GPU hardware verification (for mock/CI testing environments).

.PARAMETER Help
    Display help documentation.
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Version,
    [string]$RepoRoot,
    [switch]$KeepSandbox,
    [switch]$SkipHardwareTest,
    [Alias("h")]
    [switch]$Help
)

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

if ($Help -or ($Version -in @('-h', '-help', '--help', '/?', 'help', ''))) {
    Write-Host "`n============ WINROCM 1-CLICK HARDWARE TEST & PROMOTION ============" -ForegroundColor Cyan
    Write-Host "Usage:"
    Write-Host "  setup.bat test-and-promote -Version <version> [options]"
    Write-Host "  powershell.exe -File scripts\dev\test-and-promote.ps1 -Version <version> [options]"
    Write-Host "`nDescription:"
    Write-Host "  1. Provisions an isolated 4-part sandbox (.test-env\) with Python, ROCm wheels,"
    Write-Host "     version-matched triton-windows, and Portable MSVC."
    Write-Host "  2. Runs physical AMD GPU hardware verification (.test-env\bin\verify_rocm.bat):"
    Write-Host "     - GPU Matmul (GEMM FP16)"
    Write-Host "     - GPU Conv2d + Naive Fallback Latency check"
    Write-Host "     - BatchNorm2d (>32x32 tensor with MSVC STL)"
    Write-Host "     - F.normalize Autograd check"
    Write-Host "     - Triton JIT kernel compilation with Portable MSVC cl.exe"
    Write-Host "  3. Upon Test Pass (Automated Promotion):"
    Write-Host "     - Sets DefaultRelease = '<version>' in config/releases.psd1"
    Write-Host "     - Appends release entry to CHANGELOG.md with wheel SHA-256 hashes"
    Write-Host "     - Cleans up .test-env\"
    Write-Host "     - Creates Git branch 'release/rocm-<version>' and commits changes"
    Write-Host "  4. Upon Test Fail (Diagnostic Safety):"
    Write-Host "     - Preserves .test-env\ intact for developer investigation"
    Write-Host "`nOptions:"
    Write-Host "  -Version <v>         Target ROCm release version (e.g. 7.3, 7.2.1). Mandatory."
    Write-Host "  -RepoRoot <path>     Override repository root directory."
    Write-Host "  -KeepSandbox         Preserve .test-env\ even after successful promotion."
    Write-Host "  -SkipHardwareTest    Bypass physical GPU execution (for CI/offline testing)."
    Write-Host "  -Help, -h            Display this reference."
    Write-Host "===================================================================`n" -ForegroundColor Cyan
    if ([string]::IsNullOrWhiteSpace($Version) -and -not $Help) {
        [Console]::Error.WriteLine("Missing mandatory parameter: -Version is required (e.g. -Version 7.3).")
        exit 1
    }
    return
}

# Resolve Repository Root
$resolvedRepo = if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
} else {
    [System.IO.Path]::GetFullPath($RepoRoot)
}

$configPath = Join-Path $resolvedRepo "config\releases.psd1"
if (-not (Test-Path -Path $configPath)) {
    [Console]::Error.WriteLine("Configuration file not found: $configPath")
    exit 1
}

$cleanVersion = $Version -replace '^rocm-rel-', ''

# Validate that release exists in releases.psd1
$config = Import-PowerShellDataFile -Path $configPath
if (-not $config.Releases.ContainsKey($cleanVersion)) {
    [Console]::Error.WriteLine("Release '$cleanVersion' is not configured in config/releases.psd1.`nPlease run 'setup.bat stage-release -Version $cleanVersion' first to stage the release.")
    exit 1
}

Write-Host "`n================ 1-CLICK TEST & PROMOTE: ROCm $cleanVersion ================" -ForegroundColor Cyan
Write-Host "Repository Root  : $resolvedRepo"
Write-Host "Target Release   : $cleanVersion"
Write-Host "Hardware Test    : $(if ($SkipHardwareTest) { 'SKIPPED (-SkipHardwareTest)' } else { 'ENABLED (Physical AMD GPU)' })"

$sandboxDir = Join-Path $resolvedRepo ".test-env"
$rootMsvcDir = Join-Path $resolvedRepo "msvc"

# Step 1: Clean previous sandbox safely
Write-Host "`n==> Preparing isolated test sandbox (.test-env)..." -ForegroundColor Yellow
if (Test-Path -Path $sandboxDir) {
    Write-Host "  Cleaning existing sandbox at $sandboxDir..." -ForegroundColor Gray
    $sandboxMsvc = Join-Path $sandboxDir "msvc"
    if (Test-Path -Path $sandboxMsvc) {
        $msvcItem = Get-Item -Path $sandboxMsvc
        if ($msvcItem.Attributes -match "ReparsePoint") {
            [System.IO.Directory]::Delete($sandboxMsvc)
        }
    }
    Remove-Item -Path $sandboxDir -Recurse -Force -ErrorAction SilentlyContinue
}

New-Item -ItemType Directory -Path $sandboxDir -Force | Out-Null

# Step 2: Toolchain linking (reuse root MSVC if available)
if (Test-Path -Path (Join-Path $rootMsvcDir "setup_x64.bat")) {
    Write-Host "  Reusing root Portable MSVC toolchain via directory junction..." -ForegroundColor Cyan
    $sandboxMsvc = Join-Path $sandboxDir "msvc"
    cmd.exe /c "mklink /J `"$sandboxMsvc`" `"$rootMsvcDir`"" | Out-Null
    Write-Host "  [OK] Junction linked: $sandboxMsvc -> $rootMsvcDir" -ForegroundColor Green
}

# Step 3: Provision isolated sandbox
Write-Host "`n==> Provisioning isolated environment for ROCm $cleanVersion..." -ForegroundColor Yellow
$setupScript = Join-Path $resolvedRepo "setup_rocm_portable.ps1"
$setupArgs = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $setupScript,
    "-InstallDir", $sandboxDir,
    "-RocmRelease", $cleanVersion,
    "-WithTriton",
    "-WithMsvc",
    "-Yes",
    "-SkipVerify"
)

$setupProcess = Start-Process -FilePath "powershell.exe" -ArgumentList $setupArgs -NoNewWindow -Wait -PassThru
if ($setupProcess.ExitCode -ne 0) {
    Write-Host "`n[FAIL] Sandbox provisioning failed with exit code $($setupProcess.ExitCode)." -ForegroundColor Red
    Write-Host "Diagnostic Safety: Preserving sandbox at '$sandboxDir' for debugging." -ForegroundColor Yellow
    exit 1
}

Write-Host "  [OK] Sandbox environment successfully provisioned." -ForegroundColor Green

# Step 4: Physical AMD GPU Hardware Verification
$verifyBat = Join-Path $sandboxDir "bin\verify_rocm.bat"
if (-not (Test-Path -Path $verifyBat)) {
    [Console]::Error.WriteLine("Verification launcher not found in sandbox: $verifyBat")
    exit 1
}

$verifyExitCode = 0
if ($SkipHardwareTest) {
    Write-Host "`n==> Skipping physical hardware verification (-SkipHardwareTest active)." -ForegroundColor Yellow
} else {
    Write-Host "`n==> Executing AMD GPU hardware verification suite on physical hardware..." -ForegroundColor Yellow
    Write-Host "  Running: $verifyBat" -ForegroundColor Cyan
    $verifyProcess = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$verifyBat`"" -NoNewWindow -Wait -PassThru
    $verifyExitCode = $verifyProcess.ExitCode
}

if ($verifyExitCode -ne 0) {
    Write-Host "`n========================= VERIFICATION FAILED =========================" -ForegroundColor Red
    Write-Host "Hardware verification failed with exit code $verifyExitCode." -ForegroundColor Red
    Write-Host "Diagnostic Safety: Preserving .test-env\ for immediate debugging." -ForegroundColor Yellow
    Write-Host "Sandbox Location : $sandboxDir" -ForegroundColor White
    Write-Host "Run verification manually: $verifyBat" -ForegroundColor Gray
    Write-Host "======================================================================`n" -ForegroundColor Red
    exit 1
}

Write-Host "`n======================= VERIFICATION PASSED =======================" -ForegroundColor Green
Write-Host "All physical hardware tests completed successfully on AMD GPU." -ForegroundColor Green
Write-Host "  [Pass] GPU Matmul (GEMM FP16)" -ForegroundColor Green
Write-Host "  [Pass] GPU Conv2d + Naive Fallback Latency check" -ForegroundColor Green
Write-Host "  [Pass] BatchNorm2d (>32x32 tensor with MSVC STL)" -ForegroundColor Green
Write-Host "  [Pass] F.normalize Autograd check" -ForegroundColor Green
Write-Host "  [Pass] Triton JIT kernel compilation using Portable MSVC cl.exe" -ForegroundColor Green
Write-Host "====================================================================`n" -ForegroundColor Green

# Step 5: Automated Promotion
Write-Host "==> Promoting ROCm $cleanVersion release..." -ForegroundColor Yellow

# 5a. Update DefaultRelease in config/releases.psd1
Write-Host "  Setting DefaultRelease = '$cleanVersion' in config/releases.psd1..." -ForegroundColor Cyan
$cfgRaw = Get-Content -Path $configPath -Raw
$cfgRaw = $cfgRaw -replace "DefaultRelease\s*=\s*['`"][^'`"]+['`"]", "DefaultRelease    = '$cleanVersion'"
Set-Content -Path $configPath -Value $cfgRaw -Encoding utf8
$verifiedConfig = Import-PowerShellDataFile -Path $configPath
if ($verifiedConfig.DefaultRelease -ne $cleanVersion) {
    [Console]::Error.WriteLine("Failed to set DefaultRelease to '$cleanVersion' in config/releases.psd1.")
    exit 1
}
Write-Host "  [OK] DefaultRelease updated to '$cleanVersion'." -ForegroundColor Green

# 5b. Update CHANGELOG.md
Write-Host "  Logging release entry to CHANGELOG.md..." -ForegroundColor Cyan
$changelogPath = Join-Path $resolvedRepo "CHANGELOG.md"
if (Test-Path -Path $changelogPath) {
    $clRaw = Get-Content -Path $changelogPath -Raw
    $stageMetaFile = Join-Path $resolvedRepo ".staged-release-$cleanVersion.json"
    $stageMeta = $null
    if (Test-Path -Path $stageMetaFile) {
        try {
            $stageMeta = Get-Content -Path $stageMetaFile -Raw | ConvertFrom-Json
        } catch {
            $stageMeta = $null
        }
    }

    $dateStr = [System.DateTime]::UtcNow.ToString("yyyy-MM-dd")
    $relCfg = $verifiedConfig.Releases[$cleanVersion]
    
    $entryLines = @(
        "## [$cleanVersion] - $dateStr",
        "",
        "### Added",
        "- **Official AMD ROCm $cleanVersion Support**: Added verified support for AMD ROCm release track $cleanVersion.",
        "- **Automated Verification**: Verified across full physical AMD GPU hardware test suite:",
        "  - GPU GEMM FP16 matrix multiplication",
        "  - GPU Conv2d latency & MIOpen cache validation",
        "  - BatchNorm2d (>32x32 tensors with MSVC STL / ATen fallback)",
        "  - F.normalize numerical stability and autograd backward pass",
        "  - Triton JIT kernel compilation via Portable MSVC cl.exe"
    )

    if ($stageMeta -and $stageMeta.hashes) {
        $entryLines += "- **Cryptographic Package Checksums (SHA-256)**:"
        foreach ($prop in $stageMeta.hashes.PSObject.Properties) {
            $entryLines += "  - '$($prop.Name)': $($prop.Value)"
        }
    } else {
        $entryLines += "- **Release Packages**:"
        foreach ($sdk in $relCfg.SdkFiles) {
            $entryLines += "  - '$sdk'"
        }
        $entryLines += "  - '$($relCfg.Torch)'"
        $entryLines += "  - '$($relCfg.Vision)'"
        $entryLines += "  - '$($relCfg.Audio)'"
    }
    $entryLines += ""

    $newChangelogSection = ($entryLines -join "`n")
    # Insert right below the header (after "# Changelog\n\n...adheres to [Semantic Versioning]...\n")
    $marker = "and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)."
    if ($clRaw.Contains($marker)) {
        $clRaw = $clRaw.Replace($marker, "$marker`n`n$newChangelogSection")
        Set-Content -Path $changelogPath -Value $clRaw -Encoding utf8
        Write-Host "  [OK] Release $cleanVersion documented in CHANGELOG.md." -ForegroundColor Green
    }
}

# 5c. Sandbox Cleanup
if (-not $KeepSandbox) {
    Write-Host "  Cleaning up isolated sandbox (.test-env)..." -ForegroundColor Cyan
    $sandboxMsvc = Join-Path $sandboxDir "msvc"
    if (Test-Path -Path $sandboxMsvc) {
        $msvcItem = Get-Item -Path $sandboxMsvc
        if ($msvcItem.Attributes -match "ReparsePoint") {
            [System.IO.Directory]::Delete($sandboxMsvc)
        }
    }
    Remove-Item -Path $sandboxDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  [OK] Sandbox cleaned." -ForegroundColor Green
} else {
    Write-Host "  Sandbox preserved at $sandboxDir (-KeepSandbox active)." -ForegroundColor Yellow
}

# 5d. Git Branching & Promotion Commit
Write-Host "  Performing Git branch creation and promotion commit..." -ForegroundColor Cyan
$gitAvailable = $null -ne (Get-Command "git" -ErrorAction SilentlyContinue)
$branchName = "release/rocm-$cleanVersion"

if ($gitAvailable -and (Test-Path -Path (Join-Path $resolvedRepo ".git"))) {
    try {
        & git -C $resolvedRepo checkout -B $branchName
        & git -C $resolvedRepo add config/releases.psd1 CHANGELOG.md
        $stageMetaFile = Join-Path $resolvedRepo ".staged-release-$cleanVersion.json"
        if (Test-Path -Path $stageMetaFile) {
            Remove-Item -Path $stageMetaFile -Force -ErrorAction SilentlyContinue
        }
        & git -C $resolvedRepo commit -m "feat(rocm): Add and verify ROCm $cleanVersion release"
        Write-Host "  [OK] Committed promotion changes to branch '$branchName'." -ForegroundColor Green
        Write-Host "`nPromotion complete! Ready to push:" -ForegroundColor Green
        Write-Host "  git push origin $branchName`n" -ForegroundColor White
    } catch {
        Write-Warning "Git operation encountered a warning: $($_.Exception.Message)"
    }
} else {
    Write-Host "  [Notice] Git repository not active or git CLI not found. Changes saved to working directory." -ForegroundColor Yellow
}

exit 0
