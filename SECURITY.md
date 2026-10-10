# Security Policy

## Scope and Network Activity

`WinROCm-PyTorch` installs an isolated AMD ROCm PyTorch environment on Windows. It does NOT bundle AMD binaries or Python executables inside this repository.

During installation and dry-run execution, the script contacts the following official hosts:

| Host | Purpose |
|---|---|
| `www.python.org` | Downloads the official Python 3.12 64-bit embeddable zip distribution. Verified against SHA256 in `config/releases.psd1`. |
| `bootstrap.pypa.io` | Downloads the official `get-pip.py` bootstrapper. Verified against SHA256 in `config/releases.psd1`. |
| `repo.radeon.com` | Downloads official AMD ROCm SDK wheels (`rocm_sdk_core`, `rocm_sdk_devel`, `rocm_sdk_libraries_custom`, `rocm-*.tar.gz`) and official AMD PyTorch wheels (`torch`, `torchvision`, `torchaudio`). |
| `pypi.org` / `files.pythonhosted.org` | Downloads wheel dependencies for PyTorch (e.g. `filelock`, `jinja2`, `networkx`, `sympy`, `pillow`, `numpy`). |

## Package Build Notice

The AMD ROCm metapackage `rocm-*.tar.gz` is distributed by AMD as a source archive. During installation, pip runs a local build step using `setuptools` inside isolated temporary directories (`.tmp`) to assemble the wheel metadata. No code is installed system-wide or outside the target folder.

## Environment Isolation

- **No System PATH modification**: The environment is process-isolated and only accessible via launcher scripts (`run_rocm.bat`, `pip_rocm.bat`, `shell_rocm.bat`, `env_rocm.ps1`).
- **No User Site-Packages**: `PYTHONNOUSERSITE=1` is enforced to prevent interference from `%APPDATA%\Python`.
- **Caches Redirected**: All caches (`TORCH_HOME`, `HF_HOME`, `TRITON_CACHE_DIR`, `MIOPEN_*`) are redirected to `.cache\` inside the folder.
- **Constraints Protection**: A generated `constraints-rocm.txt` pins ROCm and torch packages to prevent downstream pip invocations from overwriting the AMD ROCm build with upstream PyPI wheels.

## Reporting a Vulnerability

If you discover a security vulnerability, please do NOT file a public issue. Instead, report it via GitHub Private Vulnerability Reporting or contact the maintainers directly.

