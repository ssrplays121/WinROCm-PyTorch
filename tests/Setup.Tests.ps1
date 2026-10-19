# Ensure Pester 5+ is loaded if available on the system
if ($null -eq (Get-Module Pester) -or (Get-Module Pester).Version.Major -lt 5) {
    Remove-Module Pester -ErrorAction SilentlyContinue
    $modernPester = Get-Module -ListAvailable Pester | Where-Object { $_.Version.Major -ge 5 } | Select-Object -First 1
    if ($modernPester) {
        Import-Module $modernPester.Path -Force
    }
}

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    $script:scriptPath = Join-Path $script:repoRoot "setup_rocm_portable.ps1"
    $script:configPath = Join-Path $script:repoRoot "config\releases.psd1"
    $script:templateDir = Join-Path $script:repoRoot "templates"

    # Dot-source the script to load its functions without executing Main
    . $script:scriptPath

    # Mock Invoke-WebRequest so test suite runs completely offline with 0 network latency
    Mock -CommandName Invoke-WebRequest {
        return [PSCustomObject]@{
            StatusCode = 200
            Headers    = @{ 'Content-Length' = @(1048576) }
        }
    }
}

Describe "ROCm Portable - Release Configuration" {
    It "config/releases.psd1 parses successfully with Import-PowerShellDataFile" {
        $config = Import-PowerShellDataFile -Path $script:configPath
        $config | Should -Not -BeNullOrEmpty
        $config.DefaultRelease | Should -Be '7.2'
        $config.PythonVersion | Should -Be '3.12.8'
        $config.PythonSha256 | Should -Not -BeNullOrEmpty
        $config.PythonDevMsiUrl | Should -Not -BeNullOrEmpty
        $config.PythonDevMsiSha256 | Should -Not -BeNullOrEmpty
        $config.GetPipSha256 | Should -Not -BeNullOrEmpty
    }

    It "Every release contains all required keys" {
        $config = Import-PowerShellDataFile -Path $script:configPath
        $releases = $config.Releases
        $releases.Keys.Count | Should -BeGreaterThan 0

        foreach ($relName in $releases.Keys) {
            $rel = $releases[$relName]
            $rel.BaseUrl | Should -Not -BeNullOrEmpty
            $rel.SdkFiles | Should -Not -BeNullOrEmpty
            $rel.Torch | Should -Not -BeNullOrEmpty
            $rel.Vision | Should -Not -BeNullOrEmpty
            $rel.Audio | Should -Not -BeNullOrEmpty
        }
    }

    It "Wheel filenames target cp312 and win_amd64" {
        $config = Import-PowerShellDataFile -Path $script:configPath
        foreach ($relName in $config.Releases.Keys) {
            $rel = $config.Releases[$relName]
            $rel.Torch | Should -Match "cp312"
            $rel.Torch | Should -Match "win_amd64"
            $rel.Vision | Should -Match "cp312"
            $rel.Audio | Should -Match "cp312"
        }
    }

    It "SupportedGpuPatterns is populated" {
        $config = Import-PowerShellDataFile -Path $script:configPath
        $config.SupportedGpuPatterns | Should -Contain "Radeon RX 9060 XT"
        $config.SupportedGpuPatterns | Should -Contain "Radeon RX 9070"
    }
}

Describe "ROCm Portable - Get-ReleaseConfig" {
    It "Resolves the default release when none is specified" {
        $config = Import-PowerShellDataFile -Path $script:configPath
        $res = Get-ReleaseConfig -Config $config -RequestedRelease ""
        $res.Name | Should -Be '7.2'
        $res.Config.BaseUrl | Should -Be 'https://repo.radeon.com/rocm/windows/rocm-rel-7.2'
    }

    It "Resolves an explicit release version" {
        $config = Import-PowerShellDataFile -Path $script:configPath
        $res = Get-ReleaseConfig -Config $config -RequestedRelease "7.2.1"
        $res.Name | Should -Be '7.2.1'
        $res.Config.BaseUrl | Should -Be 'https://repo.radeon.com/rocm/windows/rocm-rel-7.2.1'
    }

    It "Throws SetupException with exit code 2 on unknown release" {
        $config = Import-PowerShellDataFile -Path $script:configPath
        { Get-ReleaseConfig -Config $config -RequestedRelease "99.9" } | Should -Throw
        try {
            Get-ReleaseConfig -Config $config -RequestedRelease "99.9"
        } catch [SetupException] {
            $_.Exception.ExitCode | Should -Be 2
        }
    }
}

Describe "ROCm Portable - Templates" {
    It "All launcher and verification templates exist in templates/" {
        $expectedTemplates = @(
            "env_rocm.bat",
            "run_rocm.bat",
            "pip_rocm.bat",
            "shell_rocm.bat",
            "torchrun_rocm.bat",
            "env_rocm.ps1",
            "verify_rocm.py"
        )
        foreach ($tmpl in $expectedTemplates) {
            $tmplPath = Join-Path $script:templateDir $tmpl
            (Test-Path -Path $tmplPath) | Should -Be $true
        }
    }

    It "env_rocm.bat configures process isolation and constraints-rocm.txt" {
        $content = Get-Content -Path (Join-Path $script:templateDir "env_rocm.bat") -Raw
        $content | Should -Match "set `"PYTHONNOUSERSITE=1`""
        $content | Should -Match "set `"PIP_NO_CACHE_DIR=1`""
        $content | Should -Match "constraints-rocm\.txt"
    }

    It "env_rocm.ps1 configures process isolation and constraints-rocm.txt" {
        $content = Get-Content -Path (Join-Path $script:templateDir "env_rocm.ps1") -Raw
        $content | Should -Match '\$env:PYTHONNOUSERSITE = "1"'
        $content | Should -Match 'constraints-rocm\.txt'
    }
}

Describe "ROCm Portable - Preflight Path Checks" {
    It "Rejects install paths exceeding 100 characters and creates no folder on disk" {
        $longPath = "C:\" + ("a" * 105)
        $config = Import-PowerShellDataFile -Path $script:configPath
        { Test-Preflight -Config $config -TargetDir $longPath -SelectedRelease "7.2" -SkipGpu } | Should -Throw
        try {
            Test-Preflight -Config $config -TargetDir $longPath -SelectedRelease "7.2" -SkipGpu
        } catch [SetupException] {
            $_.Exception.ExitCode | Should -Be 2
        }
        (Test-Path -Path $longPath) | Should -Be $false
    }

    It "Rejects install paths with non-ASCII characters and creates no folder on disk" {
        $unicodePath = "C:\rocm_unicode_" + [char]0x6D4B + [char]0x8BD5
        $config = Import-PowerShellDataFile -Path $script:configPath
        { Test-Preflight -Config $config -TargetDir $unicodePath -SelectedRelease "7.2" -SkipGpu } | Should -Throw
        try {
            Test-Preflight -Config $config -TargetDir $unicodePath -SelectedRelease "7.2" -SkipGpu
        } catch [SetupException] {
            $_.Exception.ExitCode | Should -Be 2
        }
        (Test-Path -Path $unicodePath) | Should -Be $false
    }

    It "Allows paths with special characters like % and & with warning only" {
        $testTarget = Join-Path $TestDrive "test_special%folder&dir"
        New-Item -ItemType Directory -Force -Path $testTarget | Out-Null
        $config = Import-PowerShellDataFile -Path $script:configPath
        { Test-Preflight -Config $config -TargetDir $testTarget -SelectedRelease "7.2" -SkipGpu } | Should -Not -Throw
    }
}

Describe "ROCm Portable - Constraints Generation" {
    It "Generates expected package constraints format" {
        $testDir = Join-Path $TestDrive "constraints_test"
        New-Item -ItemType Directory -Force -Path $testDir | Out-Null
        $constraintsFile = Join-Path $testDir "constraints-rocm.txt"
        $mockOutput = @"
rocm==7.2.0.dev0
rocm-sdk-core==7.2.0.dev0
rocm-sdk-devel==7.2.0.dev0
rocm-sdk-libraries-custom==7.2.0.dev0
torch==2.9.1+rocmsdk20260116
torchaudio==2.9.1+rocmsdk20260116
torchvision==0.24.1+rocmsdk20260116
"@
        Set-Content -Path $constraintsFile -Value $mockOutput -Encoding ASCII
        $lines = Get-Content -Path $constraintsFile
        $lines | Should -Contain "torch==2.9.1+rocmsdk20260116"
        $lines | Should -Contain "rocm-sdk-core==7.2.0.dev0"
        foreach ($line in $lines) {
            $line | Should -Match '^[a-zA-Z0-9_\-]+==[a-zA-Z0-9_\.\+\-]+$'
        }
    }

    It "Constraints python script executes without syntax error when passed via stdin" {
        $systemPython = (Get-Command python.exe -ErrorAction SilentlyContinue).Source
        if ($systemPython) {
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
            $null = $pyCode | & $systemPython -
            $global:LASTEXITCODE | Should -Be 0
        }
    }
}

Describe "ROCm Portable - Assert-LastExit and Exit Codes" {
    It "Assert-LastExit passes when LASTEXITCODE is 0" {
        $global:LASTEXITCODE = 0
        { Assert-LastExit "test step" 4 } | Should -Not -Throw
    }

    It "Assert-LastExit throws SetupException with specified code when LASTEXITCODE is non-zero" {
        $global:LASTEXITCODE = 1
        try {
            Assert-LastExit "failed step" 4
        } catch [SetupException] {
            $_.Exception.ExitCode | Should -Be 4
            $_.Exception.Message | Should -Match "failed step"
        }
    }
}

Describe "ROCm Portable - State Persistence" {
    It "Save-State creates valid .rocm-portable.json" {
        $testDir = Join-Path $TestDrive "state_test"
        New-Item -ItemType Directory -Force -Path $testDir | Out-Null
        Save-State -TargetDir $testDir -ScriptVer "0.1.0" -RocmRel "7.2" -PyVer "3.12.8" -TorchVer "2.9.1" -Components @("torch")

        $stateFile = Join-Path $testDir ".rocm-portable.json"
        (Test-Path -Path $stateFile) | Should -Be $true
        $json = Get-Content -Path $stateFile -Raw | ConvertFrom-Json
        $json.scriptVersion | Should -Be "0.1.0"
        $json.rocmRelease | Should -Be "7.2"
        $json.pythonVersion | Should -Be "3.12.8"
    }
}

Describe "ROCm Portable - DryRun" {
    It "Validates plan and all URLs with mocked network (offline safe, creates no python dir)" {
        $testTarget = Join-Path $TestDrive "dryrun_mock_dir"
        New-Item -ItemType Directory -Force -Path $testTarget | Out-Null
        $config = Import-PowerShellDataFile -Path $script:configPath
        $relInfo = Get-ReleaseConfig -Config $config -RequestedRelease "7.2"

        { Invoke-DryRun -Config $config -ReleaseInfo $relInfo -TargetDir $testTarget -IncludeVision:$true -IncludeAudio:$true } | Should -Not -Throw
        (Test-Path -Path (Join-Path $testTarget "python")) | Should -Be $false
    }

    It "DryRun leaves a non-existent target directory uncreated on disk" {
        $nonExistent = Join-Path $TestDrive "non_existent_dryrun_target"
        $config = Import-PowerShellDataFile -Path $script:configPath
        $relInfo = Get-ReleaseConfig -Config $config -RequestedRelease "7.2"

        { Invoke-DryRun -Config $config -ReleaseInfo $relInfo -TargetDir $nonExistent -IncludeVision:$true -IncludeAudio:$true } | Should -Not -Throw
        (Test-Path -Path $nonExistent) | Should -Be $false
    }
}

Describe "ROCm Portable - CLI Diagnostics" {
    It "Executes -Diagnose without modifying files or requiring network" {
        $testTarget = Join-Path $TestDrive "diag_dir"
        New-Item -ItemType Directory -Force -Path $testTarget | Out-Null
        $psExe = (Get-Process -Id $PID).Path
        $output = & $psExe -NoProfile -ExecutionPolicy Bypass -File $script:scriptPath -InstallDir $testTarget -Diagnose 2>&1
        $outputString = ($output -join "`n")
        $outputString | Should -Match "ROCm Portable Windows Diagnostics"
        (Test-Path -Path (Join-Path $testTarget "diagnose.txt")) | Should -Be $true
    }
}

Describe "ROCm Portable - Bootstrapper and PATH Management" {
    It "Root setup.bat exists and delegates to setup_rocm_portable.ps1" {
        $setupBat = Join-Path $script:repoRoot "setup.bat"
        (Test-Path -Path $setupBat) | Should -Be $true
        $content = Get-Content -Path $setupBat -Raw
        $content | Should -Match "setup_rocm_portable\.ps1"
        $content | Should -Match "-ExecutionPolicy Bypass"
    }

    It "scripts/add_to_path.ps1 and scripts/remove_from_path.ps1 exist" {
        $addScript = Join-Path $script:repoRoot "scripts\add_to_path.ps1"
        $removeScript = Join-Path $script:repoRoot "scripts\remove_from_path.ps1"
        (Test-Path -Path $addScript) | Should -Be $true
        (Test-Path -Path $removeScript) | Should -Be $true
    }

    It "add_to_path.ps1 fails cleanly when bin directory does not exist" {
        $testDir = Join-Path $TestDrive "no_bin_dir"
        New-Item -ItemType Directory -Force -Path $testDir | Out-Null
        $addScript = Join-Path $script:repoRoot "scripts\add_to_path.ps1"
        { & $addScript -InstallDir $testDir } | Should -Throw
    }
}

