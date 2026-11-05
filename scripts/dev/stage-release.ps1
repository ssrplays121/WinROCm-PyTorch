<#
.SYNOPSIS
    WinROCm Automated Release Stager & Upstream Scraper.

.DESCRIPTION
    Connects to the official AMD ROCm Windows release repository, scrapes and discovers
    the exact 7 required packages for the targeted release version, downloads and computes
    cryptographic SHA-256 hashes using temporary disk buffering, resolves the matching
    triton-windows wheel from PyPI, and updates config/releases.psd1.

.PARAMETER Version
    ROCm release version to stage (e.g. 7.3, 7.2.1). Mandatory.

.PARAMETER CheckOnly
    Strictly preview scraping, SHA-256 hashing, and Triton matching without modifying files.

.PARAMETER RepoRoot
    Target repository root path. Defaults to the repository root of this script.

.PARAMETER TempDir
    Custom directory for temporary file buffering during hash calculation.

.PARAMETER Help
    Display help documentation.
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Version,
    [switch]$CheckOnly,
    [string]$RepoRoot,
    [string]$TempDir,
    [Alias("h")]
    [switch]$Help
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

if ($Help -or ($Version -in @('-h', '-help', '--help', '/?', 'help', ''))) {
    Write-Host "`n================ WINROCM RELEASE STAGER & SCRAPER ================" -ForegroundColor Cyan
    Write-Host "Usage:"
    Write-Host "  setup.bat stage-release -Version <version> [options]"
    Write-Host "  powershell.exe -File scripts\dev\stage-release.ps1 -Version <version> [options]"
    Write-Host "`nDescription:"
    Write-Host "  Connects to https://repo.radeon.com/rocm/windows/rocm-rel-<version>/,"
    Write-Host "  scrapes and discovers the exact 7 required files, buffers downloads to disk"
    Write-Host "  to compute cryptographic SHA-256 hashes, queries PyPI for the matching"
    Write-Host "  triton-windows wheel, and inserts the release entry into config/releases.psd1."
    Write-Host "`nOptions:"
    Write-Host "  -Version <v>      Target ROCm release version (e.g. 7.3, 7.2.1). Mandatory."
    Write-Host "  -CheckOnly        Preview discovery and hashes without modifying config/releases.psd1."
    Write-Host "  -RepoRoot <path>  Override repository root directory."
    Write-Host "  -TempDir <path>   Override temporary download buffer directory."
    Write-Host "  -Help, -h         Display this reference."
    Write-Host "==================================================================`n" -ForegroundColor Cyan
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

# Sanitize version string (e.g. 'rocm-rel-7.3' -> '7.3')
$cleanVersion = $Version -replace '^rocm-rel-', ''
$baseUrl = "https://repo.radeon.com/rocm/windows/rocm-rel-$cleanVersion"

Write-Host "`n================ STAGING ROCM RELEASE $cleanVersion ================" -ForegroundColor Cyan
Write-Host "Target Endpoint  : $baseUrl/"
Write-Host "Repository Root  : $resolvedRepo"
Write-Host "Check Only Mode  : $(if ($CheckOnly) { 'ENABLED (Read-Only)' } else { 'DISABLED (Will update config)' })"

# 1. Connect and scrape directory listing
Write-Host "`n==> Connecting to AMD release endpoint..." -ForegroundColor Yellow
$indexHtml = $null
try {
    $resp = Invoke-WebRequest -Uri "$baseUrl/" -UseBasicParsing -TimeoutSec 20
    $indexHtml = $resp.Content
    Write-Host "  [OK $($resp.StatusCode)] Successfully retrieved directory index." -ForegroundColor Green
} catch {
    [Console]::Error.WriteLine("Failed to access AMD release endpoint at '$baseUrl/': $($_.Exception.Message)")
    exit 1
}

# 2. Discover required 7 package files
Write-Host "`n==> Discovering required release assets..." -ForegroundColor Yellow
$hrefMatches = [regex]::Matches($indexHtml, 'href="([^"]+)"')
$allHrefs = @($hrefMatches | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -notmatch '^\.\.' -and $_ -notmatch '^/' -and $_ -notmatch '^http' })

$discoveredCore   = $allHrefs | Where-Object { $_ -match '^rocm_sdk_core-.*\.whl$' } | Select-Object -First 1
$discoveredDevel  = $allHrefs | Where-Object { $_ -match '^rocm_sdk_devel-.*\.whl$' } | Select-Object -First 1
$discoveredCustom = $allHrefs | Where-Object { $_ -match '^rocm_sdk_libraries_custom-.*\.whl$' } | Select-Object -First 1
$discoveredTar    = $allHrefs | Where-Object { $_ -match '^rocm-.*\.tar\.gz$' } | Select-Object -First 1
$discoveredTorch  = $allHrefs | Where-Object { $_ -match '^torch-.*\.whl$' } | Select-Object -First 1
$discoveredVision = $allHrefs | Where-Object { $_ -match '^torchvision-.*\.whl$' } | Select-Object -First 1
$discoveredAudio  = $allHrefs | Where-Object { $_ -match '^torchaudio-.*\.whl$' } | Select-Object -First 1

$missing = @()
if (-not $discoveredCore)   { $missing += "rocm_sdk_core-*.whl" }
if (-not $discoveredDevel)  { $missing += "rocm_sdk_devel-*.whl" }
if (-not $discoveredCustom) { $missing += "rocm_sdk_libraries_custom-*.whl" }
if (-not $discoveredTar)    { $missing += "rocm-*.tar.gz" }
if (-not $discoveredTorch)  { $missing += "torch-*.whl" }
if (-not $discoveredVision) { $missing += "torchvision-*.whl" }
if (-not $discoveredAudio)  { $missing += "torchaudio-*.whl" }

if ($missing.Count -gt 0) {
    [Console]::Error.WriteLine("Incomplete release: Missing $($missing.Count) required file(s) in $baseUrl/:`n  $($missing -join "`n  ")")
    exit 1
}

Write-Host "  [Discovered] Core SDK       : $discoveredCore" -ForegroundColor Green
Write-Host "  [Discovered] Devel SDK      : $discoveredDevel" -ForegroundColor Green
Write-Host "  [Discovered] Custom Libs    : $discoveredCustom" -ForegroundColor Green
Write-Host "  [Discovered] Metapackage    : $discoveredTar" -ForegroundColor Green
Write-Host "  [Discovered] PyTorch        : $discoveredTorch" -ForegroundColor Green
Write-Host "  [Discovered] TorchVision    : $discoveredVision" -ForegroundColor Green
Write-Host "  [Discovered] TorchAudio     : $discoveredAudio" -ForegroundColor Green

# 3. Buffer downloads to disk and compute SHA-256 hashes
Write-Host "`n==> Computing cryptographic SHA-256 hashes (temporary disk buffering)..." -ForegroundColor Yellow

$stageBufferDir = if ([string]::IsNullOrWhiteSpace($TempDir)) {
    Join-Path ([System.IO.Path]::GetTempPath()) ("winrocm_stage_" + [System.Guid]::NewGuid().ToString("N"))
} else {
    [System.IO.Path]::GetFullPath($TempDir)
}

New-Item -ItemType Directory -Path $stageBufferDir -Force | Out-Null

$fileList = @(
    $discoveredCore,
    $discoveredDevel,
    $discoveredCustom,
    $discoveredTar,
    $discoveredTorch,
    $discoveredVision,
    $discoveredAudio
)

$fileHashes = [ordered]@{}

try {
    $webClient = New-Object System.Net.WebClient
    try {
        foreach ($file in $fileList) {
            $downloadUrl = "$baseUrl/$file"
            $safeName = [System.IO.Path]::GetFileName(($file -replace '%2B', '+'))
            $tempFilePath = Join-Path $stageBufferDir $safeName
            
            Write-Host "  Downloading and hashing: $safeName..." -NoNewline
            try {
                $webClient.DownloadFile($downloadUrl, $tempFilePath)
                $sha256 = (Get-FileHash -Path $tempFilePath -Algorithm SHA256).Hash.ToUpperInvariant()
                $fileHashes[$file] = $sha256
                Write-Host " [SHA-256: $($sha256.Substring(0,12))...]" -ForegroundColor Green
            } finally {
                if (Test-Path -Path $tempFilePath) {
                    Remove-Item -Path $tempFilePath -Force -ErrorAction SilentlyContinue
                }
            }
        }
    } finally {
        $webClient.Dispose()
    }
} finally {
    if (Test-Path -Path $stageBufferDir) {
        Remove-Item -Path $stageBufferDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# 4. Resolve matching triton-windows release from PyPI
Write-Host "`n==> Resolving compatible triton-windows release from PyPI..." -ForegroundColor Yellow
$torchVersionMatch = [regex]::Match($discoveredTorch, '^torch-([0-9]+\.[0-9]+)')
$torchMinor = if ($torchVersionMatch.Success) { $torchVersionMatch.Groups[1].Value } else { "2.9" }
$targetTritonPrefix = switch ($torchMinor) {
    "2.6"  { "3.2" }
    "2.7"  { "3.3" }
    "2.8"  { "3.4" }
    "2.9"  { "3.5" }
    "2.10" { "3.6" }
    default { "3.5" }
}

$matchingTriton = $null
try {
    $pypiTriton = Invoke-RestMethod -Uri "https://pypi.org/pypi/triton-windows/json" -TimeoutSec 15
    $availableVersions = @($pypiTriton.releases.PSObject.Properties.Name)
    $matchingVersions = $availableVersions | Where-Object { $_ -like "$targetTritonPrefix.*" }
    if ($matchingVersions) {
        $matchingTriton = $matchingVersions[-1]
    } else {
        $matchingTriton = [string]$pypiTriton.info.version
    }
    Write-Host "  [Resolved] Torch $torchMinor pairs with triton-windows $matchingTriton." -ForegroundColor Green
} catch {
    Write-Warning "Could not query PyPI for triton-windows: $($_.Exception.Message)"
    $matchingTriton = "latest"
}

# 5. Format and display staging table
Write-Host "`n================ STAGING MANIFEST: ROCm $cleanVersion ================" -ForegroundColor Cyan
$manifestRows = @(
    [PSCustomObject]@{ Package = "rocm_sdk_core"; Filename = $discoveredCore; SHA256 = $fileHashes[$discoveredCore] },
    [PSCustomObject]@{ Package = "rocm_sdk_devel"; Filename = $discoveredDevel; SHA256 = $fileHashes[$discoveredDevel] },
    [PSCustomObject]@{ Package = "rocm_sdk_libraries_custom"; Filename = $discoveredCustom; SHA256 = $fileHashes[$discoveredCustom] },
    [PSCustomObject]@{ Package = "rocm"; Filename = $discoveredTar; SHA256 = $fileHashes[$discoveredTar] },
    [PSCustomObject]@{ Package = "torch"; Filename = $discoveredTorch; SHA256 = $fileHashes[$discoveredTorch] },
    [PSCustomObject]@{ Package = "torchvision"; Filename = $discoveredVision; SHA256 = $fileHashes[$discoveredVision] },
    [PSCustomObject]@{ Package = "torchaudio"; Filename = $discoveredAudio; SHA256 = $fileHashes[$discoveredAudio] }
)
$manifestRows | Format-Table -AutoSize | Out-String | Write-Host

# 6. Apply configuration update
if ($CheckOnly) {
    Write-Host "Check-only mode enabled: config/releases.psd1 was NOT modified.`n" -ForegroundColor Yellow
    exit 0
}

Write-Host "==> Updating config/releases.psd1..." -ForegroundColor Yellow
$cfgRaw = Get-Content -Path $configPath -Raw

# Check if release is already registered
$existingConfig = Import-PowerShellDataFile -Path $configPath
if ($existingConfig.Releases.ContainsKey($cleanVersion)) {
    Write-Host "  Release '$cleanVersion' is already present in config/releases.psd1. Updating entry." -ForegroundColor Yellow
    # Pattern to match existing block for this release
    $pattern = "(?ms)('$cleanVersion'\s*=\s*@\{.*?\n        \})"
    $newEntry = @"
'$cleanVersion' = @{
            BaseUrl   = '$baseUrl'
            SdkFiles  = @(
                '$discoveredCore'
                '$discoveredDevel'
                '$discoveredCustom'
                '$discoveredTar'
            )
            Torch     = '$discoveredTorch'
            Vision    = '$discoveredVision'
            Audio     = '$discoveredAudio'
        }
"@
    $cfgRaw = $cfgRaw -replace $pattern, $newEntry
} else {
    # Insert new entry before the closing brace of Releases hashtable
    $newEntry = @"
        '$cleanVersion' = @{
            BaseUrl   = '$baseUrl'
            SdkFiles  = @(
                '$discoveredCore'
                '$discoveredDevel'
                '$discoveredCustom'
                '$discoveredTar'
            )
            Torch     = '$discoveredTorch'
            Vision    = '$discoveredVision'
            Audio     = '$discoveredAudio'
        }
    }
"@
    $cfgRaw = [regex]::Replace($cfgRaw, '(\s+)\}\s*# Patterns matched against Win32_VideoController', "`n$newEntry`n`n`$1# Patterns matched against Win32_VideoController")
}

# Write and validate
$backupPath = "$configPath.bak"
Copy-Item -Path $configPath -Destination $backupPath -Force
try {
    Set-Content -Path $configPath -Value $cfgRaw -Encoding utf8
    $verified = Import-PowerShellDataFile -Path $configPath
    if (-not $verified.Releases.ContainsKey($cleanVersion)) {
        throw "Failed to verify release '$cleanVersion' in updated config/releases.psd1"
    }
    Remove-Item -Path $backupPath -Force -ErrorAction SilentlyContinue
    Write-Host "  [OK] Successfully registered release '$cleanVersion' in config/releases.psd1." -ForegroundColor Green
} catch {
    [Console]::Error.WriteLine("Failed to update config/releases.psd1 safely: $($_.Exception.Message). Restoring backup.")
    if (Test-Path -Path $backupPath) {
        Copy-Item -Path $backupPath -Destination $configPath -Force
        Remove-Item -Path $backupPath -Force
    }
    exit 1
}

# 7. Write staging metadata cache for promotion step
$stageMetaFile = Join-Path $resolvedRepo ".staged-release-$cleanVersion.json"
$stageMetaObj = [ordered]@{
    version      = $cleanVersion
    baseUrl      = $baseUrl
    sdkFiles     = @($discoveredCore, $discoveredDevel, $discoveredCustom, $discoveredTar)
    torch        = $discoveredTorch
    vision       = $discoveredVision
    audio        = $discoveredAudio
    triton       = $matchingTriton
    hashes       = $fileHashes
    stagedAtUtc  = [System.DateTime]::UtcNow.ToString("o")
}
$stageMetaObj | ConvertTo-Json -Depth 5 | Set-Content -Path $stageMetaFile -Encoding utf8
Write-Host "  [OK] Staging cache saved to $stageMetaFile." -ForegroundColor Green

Write-Host "`nRelease $cleanVersion successfully staged!" -ForegroundColor Green
Write-Host "Next step: Run hardware verification and promote the release:"
Write-Host "  setup.bat test-and-promote -Version $cleanVersion`n" -ForegroundColor White
exit 0
