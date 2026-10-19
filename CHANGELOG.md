# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-10-19

### Added
- **Dedicated `bin/` Container**: All launcher scripts (`run_rocm.bat`, `pip_rocm.bat`, `torchrun_rocm.bat`, `shell_rocm.bat`, `env_rocm.bat`, `env_rocm.ps1`, `verify_rocm.py`) now reside in `<InstallDir>\bin\`, containing any temporary artifacts inside the container.
- **Root `setup.bat` Bootstrapper**: Double-click or run from CMD without PowerShell execution policy restrictions.
- **Python C/C++ Development Headers**: Integrated official `dev.msi` (397 KB) extraction via silent `msiexec /a`, provisioning `include/Python.h` and `libs/python312.lib` for compiling native C-extensions.
- **Windows User PATH Management**: Added `scripts/add_to_path.ps1` and `scripts/remove_from_path.ps1` to safely add `bin/` to the user's `PATH` without polluting global Python.
- **Comprehensive AI & Machine Learning Guide in README**: Complete setup recipes for ComfyUI, SD-Forge / Automatic1111, Hugging Face Transformers & Diffusers, PEFT/LoRA fine-tuning, YOLO, Whisper, and Jupyter.
- **GPU Architecture Overrides Documentation**: Clear instructions and presets for RX 7600/7700/7800 (`HSA_OVERRIDE_GFX_VERSION=11.0.0`) and RX 6000 series (`10.3.0`).

### Fixed
- **Premature Directory Creation**: Deferred physical folder creation until after preflight, dry-run, and user confirmation pass. Fixed preflight writability checks to test existing parent directories.
- **PowerShell 5.1 Dry-Run Bug**: Fixed `Content-Length` division runtime error caused by indexing into single string header values.
- **Stderr Terminating Exceptions**: Fixed native executable calls with `2>&1` failing prematurely under `$ErrorActionPreference = "Stop"`.
- **Install Skip Logic**: Fixed `Install-Torch` to verify all requested components (`torch`, `torchvision`, `torchaudio`) and `Install-RocmSdk` to verify all core SDK packages.
- **Diagnostic Probe & Redaction**: Fixed `Invoke-Diagnose` to run within isolated environment variables and replaced raw substring username redaction with safe path-segment matching to avoid corrupting `AMD Radeon` or package names.
- **Python Path File Pollution**: Dynamically derived standard library `.zip` name from matched `._pth` file and removed `..` to prevent root directory files from polluting `sys.path`.
- **Launcher Script Idempotency**: Fixed repeated PATH prepending in `env_rocm.bat`/`env_rocm.ps1`, explicitly reset `PIP_CONSTRAINT` when absent, and added working directory `cd /d` to `shell_rocm.bat`.

## [0.1.0] - 2026-10-10

### Added
- Initial release of **WinROCm-PyTorch**: One-script portable installer `setup_rocm_portable.ps1` for AMD ROCm PyTorch on Windows 11.
- Complete process-level isolation: Python 3.12 embeddable, wheels, and caches (`.tmp`, `.cache`) reside exclusively within the install directory.
- Multi-release configuration driven by `config/releases.psd1` (supports ROCm 7.2 and 7.2.1).
- Comprehensive preflight checks (`Test-Preflight`): OS version (64-bit Windows 11), PowerShell version (5.1 or 7+), path length (MAX_PATH safety), ASCII path validation, free disk space (15 GB check), directory writability, host reachability, AMD GPU detection, and elevation check.
- Non-destructive execution plan preview and interactive confirmation (`-Yes` to bypass).
- `-DryRun` mode: performs preflight checks, displays plan, and HEAD-checks all download URLs without writing or downloading files.
- Integrity verification: SHA256 checksum validation for the Python embeddable archive and `get-pip.py`.
- Download retry helper (`Invoke-WithRetry`) with exponential backoff.
- Launcher script templates in `templates/`: `run_rocm.bat`, `pip_rocm.bat`, `shell_rocm.bat`, `env_rocm.bat`, and `env_rocm.ps1`.
- Environment constraints protection: generates `constraints-rocm.txt` and exports `PIP_CONSTRAINT` in launcher environments to prevent `pip install` from replacing ROCm torch with PyPI wheels.
- State tracking via `.rocm-portable.json` for idempotent re-runs and upgrade detection.
- Clean `-Reinstall` option to wipe Python binaries and state without affecting logs and caches.
- Diagnostic probe (`-Diagnose`) generating `diagnose.txt` with username redaction and GPU/Torch verification.
- Pester test suite (`tests/Setup.Tests.ps1`) and PSScriptAnalyzer configuration (`tests/PSScriptAnalyzerSettings.psd1`).
- GitHub Actions CI workflows (`lint-test.yml` and scheduled `url-check.yml`).

