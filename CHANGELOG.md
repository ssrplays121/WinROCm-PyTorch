# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

