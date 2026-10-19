# WinROCm-PyTorch

> **Unofficial project.** Not affiliated with or endorsed by Advanced Micro Devices, Inc. (AMD).

A single-script, fully isolated portable environment for **AMD ROCm PyTorch on Windows 11** (RDNA3 and RDNA4 GPUs, including Radeon RX 9060 XT, RX 9070, and RX 7900 XTX).

Everything—Python 3.12 embeddable, AMD ROCm SDK wheels, PyTorch (`torch`, `torchvision`, `torchaudio`), caches, and temp directories—lives inside a **single folder**. Nothing is added to system `PATH`, the Windows Registry, `%APPDATA%`, or user pip caches.

---

## What You Get

- **Zero System Pollution**: Completely portable. To uninstall, simply delete the directory.
- **Official Binaries**: Directly downloads official AMD ROCm wheels and python.org packages; no repackaged third-party binaries.
- **Constraints Protection**: Generates `constraints-rocm.txt` so subsequent `pip install` commands cannot accidentally replace AMD's ROCm PyTorch with PyPI CUDA/CPU wheels.
- **Multi-Release Support**: Configurable via `config/releases.psd1` (supports ROCm 7.2 and 7.2.1).
- **Preflight Validation & Diagnostics**: Checks OS, PowerShell version, path length, disk space, network reachability, and detected AMD GPU before downloading. Includes `-DryRun` and `-Diagnose`.
- **Drop-in Launchers**: Ready-to-use batch files (`run_rocm.bat`, `pip_rocm.bat`, `shell_rocm.bat`) and PowerShell environment loader (`env_rocm.ps1`).

---

## Requirements

1. **Operating System**: Windows 11 64-bit (Build 22000 or newer).
2. **Supported AMD GPU**:
   - AMD Radeon RX 9070 / RX 9070 XT
   - AMD Radeon RX 9060 XT
   - AMD Radeon RX 7900 XTX / 7900 XT / 7900 GRE
   - AMD Radeon AI PRO R9700 / PRO W7900
   - AMD Ryzen AI Max / Ryzen AI 9 processors
   *(Check [AMD's Official ROCm for Windows Compatibility List](https://rocm.docs.amd.com/) for up-to-date hardware support).*
3. **AMD Adrenalin Driver**: Install AMD's official "PyTorch on Windows" Adrenalin driver package before running.
4. **Disk Space**: At least **15 GB** free on the target drive (approx. 3.5 GB download footprint, 11 GB installed footprint).
5. **PowerShell**: Windows PowerShell 5.1 or PowerShell 7+.

---

## Quick Start

We recommend installing into a short path (e.g. `C:\rocm`) to avoid Windows `MAX_PATH` limitations:

```powershell
# 1. Clone repository
git clone https://github.com/ssrplays121/WinROCm-PyTorch.git C:\rocm
cd C:\rocm

# 2. Run the installer (interactive confirmation prompt)
powershell.exe -ExecutionPolicy Bypass -File .\setup_rocm_portable.ps1

# Or non-interactive / unattended:
powershell.exe -ExecutionPolicy Bypass -File .\setup_rocm_portable.ps1 -Yes
```

> [!NOTE]
> If you downloaded the repository as a ZIP archive, unblock the script before executing:
> ```powershell
> Unblock-File .\setup_rocm_portable.ps1
> ```

---

## Usage

All commands execute against the isolated environment in the folder:

### 1. Run a Python script (`run_rocm.bat`)
```cmd
.\run_rocm.bat my_script.py
```

### 2. Install packages (`pip_rocm.bat`)
```cmd
.\pip_rocm.bat install transformers accelerate
```
*(Package installs obey `constraints-rocm.txt`—pip will never replace the ROCm PyTorch wheels with vanilla PyPI wheels).*

### 3. Open an interactive Command Prompt (`shell_rocm.bat`)
```cmd
.\shell_rocm.bat
```
Launches a `cmd` session where `python` and `pip` point directly to the portable directory.

### 4. Load environment in PowerShell (`env_rocm.ps1`)
Dot-source the PowerShell launcher to activate the environment in your current terminal session:
```powershell
. .\env_rocm.ps1
python -c "import torch; print(torch.cuda.is_available())"
```

### 5. Jupyter Notebooks & Interactive Workflows

#### Register as a Jupyter Kernel
Register the portable environment with your Jupyter installation so it appears in JupyterLab, classic Notebook, and VS Code:
```cmd
.\pip_rocm.bat install ipykernel
.\run_rocm.bat -m ipykernel install --user --name "winrocm-pytorch" --display-name "WinROCm PyTorch"
```
> [!TIP]
> After registration, select **"WinROCm PyTorch"** from the kernel picker in JupyterLab, Jupyter Notebook, or the top-right kernel dropdown in VS Code.
> To remove the kernel registration later:
> ```cmd
> .\run_rocm.bat -m jupyter kernelspec uninstall winrocm-pytorch
> ```

#### Run JupyterLab Directly
Run a self-contained JupyterLab server hosted directly out of the portable directory:
```cmd
.\pip_rocm.bat install jupyterlab
.\run_rocm.bat -m jupyterlab
```

#### Launch an Interactive IPython Shell
```cmd
.\pip_rocm.bat install ipython
.\run_rocm.bat -m IPython
```

#### Run Web UIs & Inference Apps (Gradio / Streamlit)
```cmd
.\pip_rocm.bat install gradio
.\run_rocm.bat app.py
```

---

## Parameters

| Parameter | Type | Description |
|---|---|---|
| `-InstallDir <path>` | String | Destination folder (defaults to script's own directory). |
| `-RocmRelease <ver>` | String | ROCm release to install (`7.2` or `7.2.1`). Defaults to `DefaultRelease` in `config/releases.psd1`. |
| `-NoVision` | Switch | Skip downloading and installing `torchvision`. |
| `-NoAudio` | Switch | Skip downloading and installing `torchaudio`. |
| `-Reinstall` | Switch | Wipe existing `python\`, state, and constraints, then perform a clean reinstall. |
| `-SkipGpuCheck` | Switch | Suppress warning if detected GPU is not on AMD's verified list. |
| `-SkipVerify` | Switch | Skip running `verify_rocm.py` at the end of setup. |
| `-DryRun` | Switch | Run preflight checks, display the plan, perform HEAD checks on all URLs, and exit without downloading. |
| `-Diagnose` | Switch | Collect system, GPU, driver, and PyTorch probe diagnostics into `diagnose.txt` and exit. |
| `-Yes` | Switch | Bypass the confirmation prompt (required for non-interactive CI). |

### Exit Codes

| Code | Meaning |
|---|---|
| `0` | Success (installation completed and verified, or dry-run passed) |
| `1` | Unexpected error |
| `2` | Preflight checks failed, confirmation declined, or non-interactive without `-Yes` |
| `3` | Download failed after retries or checksum mismatch |
| `4` | `pip install` execution failed |
| `5` | Installation succeeded, but GPU verification failed (`torch.cuda.is_available()` returned `False`) |

---

## Isolation: What is Isolated vs Not

### What is Isolated (Inside Folder)
- Embeddable Python 3.12 binaries (`python\`).
- All installed packages and wheels (`python\Lib\site-packages\`).
- Process-level `PATH` (prepended via launcher scripts only).
- Python user site-packages disabled (`PYTHONNOUSERSITE=1`).
- Temp directories and pip build caches (`.tmp\`).
- Framework caches:
  - Torch model cache (`.cache\torch\`)
  - Hugging Face cache (`.cache\huggingface\`)
  - Triton cache (`.cache\triton\`)
  - MIOpen database and cache (`.cache\miopen\`)
- Global pip configuration bypassed (`PIP_CONFIG_FILE=NUL`).

### What Remains Outside
- **AMD Graphics Driver**: The AMD Adrenalin driver with ROCm runtime is installed at the Windows system level.
- Any application that explicitly writes to `%LOCALAPPDATA%` or registry paths beyond Python's control.

---

## Tested Hardware Matrix

Verified end-to-end on physical hardware during Phase 0 baseline gate:

| Parameter | Value |
|---|---|
| **GPU** | AMD Radeon RX 9060 XT (16 GB) |
| **Driver Version** | AMD Adrenalin `32.0.31041.1004` |
| **Operating System** | Windows 11 Pro 64-bit (Build 26300) |
| **PowerShell Versions** | PowerShell 7.6.6 and Windows PowerShell 5.1 |
| **ROCm Release** | 7.2 (`torch 2.9.1+rocmsdk20260116`, `hip 7.2.26024`) |
| **Download Size** | ~3.43 GB |
| **Installed Footprint** | 10.84 GB (`python\` folder) |
| **Peak Disk Requirement** | ~15 GB |
| **Wall-Clock Install Time** | 11m 44s |
| **Verification Test** | `torch.cuda.is_available() == True`, matmul (1024x1024) **OK** |

---

## Limitations

1. **Embeddable Python**:
   - Embeddable Python does not contain standard Python C header files (`include\`) or import libraries (`libs\`). Packages that compile native C/C++ extensions during `pip install` will require pre-built wheels.
   - Standard `python -m venv` is not available in embeddable distributions (environment isolation is achieved at the folder level).
2. **CPython 3.12 Only**: AMD's Windows wheels are compiled strictly for `cp312`.
3. **Windows 11**: AMD officially targets Windows 11 for ROCm on Windows.
4. **`torch.compile` / Triton**: Triton on Windows remains experimental under AMD's Windows wheels.

---

## Troubleshooting

### `torch.cuda.is_available()` returns `False`
1. Confirm that AMD's official "PyTorch on Windows" Adrenalin driver is installed.
2. Ensure you are invoking scripts via `run_rocm.bat` or `. .\env_rocm.ps1` so that isolated environment variables are set.
3. Run diagnostics:
   ```cmd
   .\setup_rocm_portable.ps1 -Diagnose
   ```
   Inspect `diagnose.txt` (local Windows usernames are automatically redacted to `<user>`).

### Pip Package Upgrades
If `pip_rocm.bat install -U torch` fails with a conflict error, this is intentional: `constraints-rocm.txt` prevents PyPI from overwriting the ROCm wheels. To upgrade ROCm, re-run `setup_rocm_portable.ps1 -RocmRelease <new-version>`.

---

## Contributing and Testing

We welcome issues and pull requests!

```powershell
# Run PSScriptAnalyzer linting
Invoke-ScriptAnalyzer -Path .\setup_rocm_portable.ps1 -Settings .\tests\PSScriptAnalyzerSettings.psd1

# Run Pester test suite
Invoke-Pester -Path .\tests\Setup.Tests.ps1 -Output Detailed
```

---

## License

This project is licensed under the [MIT License](LICENSE).

For details on changes and release history, see [CHANGELOG.md](CHANGELOG.md).

