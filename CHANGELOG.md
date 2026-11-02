# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.1] - 2026-11-02

### Added
- **User-Accessible Interactive Setup Action Menu (`setup.bat` & `rocm.bat`)**: Replaced confusing nested submenus with a persistent, single-level action menu with choices `[1-9]` and `[0]` to abort (`Enter action [0-9] (0 to abort):`).
- **Window Keep-Active Safeguard**: Prevented batch windows from closing abruptly when double-clicked or when pressing Enter without typing; loops back with a friendly reminder while cleanly terminating on non-interactive EOF (`<nul>`) for automated CI environments.
- **Upfront Triton Onboarding & torch.compile Integration**: Setup banner reports live Triton status (`INSTALLED [torch.compile active]` vs `NOT INSTALLED [torch.compile disabled]`). Added comprehensive educational guide explaining Triton's purpose, benefits (15% to 50%+ speedup in ComfyUI/LLMs), and MSVC requirements via action `[8]` and `setup.bat triton` / `rocm triton`.
- **1-Click Triton Upgrade for Existing Environments**: Existing installations missing Triton can install `triton-windows` seamlessly via option `[1]` or option `[8]` (`update.ps1 -WithTriton`) without wiping or reinstalling.
- **Dedicated Subcommand-Level Help System**: Implemented individual help screens for all commands (`install`, `update`, `check-update`, `status`, `verify`, `reinstall`, `diagnose`, `triton`) accessible via prefix (`setup.bat help <cmd>`) and flags (`setup.bat <cmd> --help`, `-h`).
- **Preflight & Installation Plan Triton Transparency**: Pre-installation plan and dry-run output explicitly report Triton acceleration status, and interactive installs prompt users to include Triton when unconfigured.

### Fixed
- **Accidental Window Close on Double-Click**: Resolved premature exit when pressing Enter without input.
- **Batch Byte-Offset Label Resolution**: Enforced strict CRLF line endings across all batch files to prevent `The system cannot find the batch label specified` errors in `cmd.exe`.
- **Batch Parenthesis Parser Conflicts**: Sanitized nested parentheses inside status variables and flattened menu navigation to prevent batch parser syntax corruption.

## [0.3.0] - 2026-11-01

### Added
- **Linux Package Manager Workflow (`setup.bat update`)**: Added interactive upgrade detection and targeted updates modeled after `dnf`/`apt`. Synchronizes remote repository catalogs from GitHub, compares installed packages against candidates, renders a formatted package status diff table, and prompts the user for confirmation.
- **Strictly Read-Only Check Mode (`setup.bat check-update`)**: Non-destructive preview comparing installed packages against upstream candidates without modifying any files on disk.
- **Interactive Window of Options & Submenus (`setup.bat` & `rocm.bat`)**: When double-clicked or opened without arguments, displays a persistent interactive menu allowing users to choose from Install, Update, Check-Update, Status, Verify, Reinstall, and Diagnose. Includes dedicated submenus with input validation and safe pause handling so console windows do not close prematurely.
- **Dedicated Individual Help Options**: Every command and submenu features individual help (`setup.bat help <cmd>`, `setup.bat <cmd> --help`, `rocm help <cmd>`, `rocm <cmd> --help`). Scripts (`setup_rocm_portable.ps1`, `scripts/update.ps1`, `scripts/status.ps1`) natively handle `-Help` / `-h` without throwing parameter binding errors.
- **Unified Front-End CLI & Package Manager**: Redesigned `setup.bat` and `bin/rocm.bat` into clean command routers supporting `install`, `update`, `check-update`, `status`, `verify`, `reinstall`, and `diagnose`, with first-class parameter forwarding and `-Install` action support.
- **Reinstall Shortcut Launcher (`bin/reinstall_rocm.bat`)**: Added direct shortcut in `bin/` for single-command environment wipe and clean reinstallation alongside `update_rocm.bat`, `status_rocm.bat`, and `verify_rocm.bat`.
- **Synchronized SDK Metapackage Upgrades**: Updates both binary `.whl` files and the top-level AMD `rocm` metapackage (`rocm-*.tar.gz`) in unison to maintain strict dependency integrity.
- **Linux-Style Option Parity**: Added `-y` as a direct alias for `-Yes` for unattended, non-interactive script updates (`setup.bat update -y`).
- **Global `rocm` System Command**: Introduced `bin/rocm.bat` mirroring `setup.bat` syntax, enabling users to run `rocm update`, `rocm status`, `rocm check-update`, `rocm verify`, `rocm run`, and `rocm pip` from any terminal or folder once added to User PATH.
- **Dedicated Shortcut Launchers**: Added `update_rocm.bat`, `status_rocm.bat`, and `verify_rocm.bat` inside `bin/` for single-word command execution.
- **Modular Scripts Architecture**: Separated package manager logic into `scripts/update.ps1` and environment inspection into `scripts/status.ps1`.
- **Fast Pure-Python Metadata Probing**: Switched version detection to `importlib.metadata.version` to query package versions instantly without triggering GPU runtime initialization or `offload-arch` stderr messages.
- **PEP 503 Constraint Normalization**: Normalized distribution names in `constraints-rocm.txt` to ensure consistent package locking across all dependency tools.

## [0.2.1] - 2026-11-01

### Fixed
- **Pip Bootstrap Checksum Mismatch**: Updated `GetPipSha256` and pinned `PipVersion` in `config/releases.psd1` to match upstream PyPA release `26.2.2`.
- **CI Dynamic Checksum Validation**: Added dynamic SHA256 integrity check for `get-pip.py` to the weekly `url-check.yml` workflow.

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

