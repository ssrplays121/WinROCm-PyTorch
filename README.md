# WinROCm-PyTorch

[![Platform](https://img.shields.io/badge/Platform-Windows%2011%2064--bit-blue.svg)](https://www.microsoft.com/windows)
[![Python](https://img.shields.io/badge/Python-3.12-3776AB.svg?logo=python&logoColor=white)](https://www.python.org/)
[![ROCm](https://img.shields.io/badge/ROCm-7.2%20%7C%207.2.1-red.svg)](https://repo.radeon.com/rocm/)
[![PyTorch](https://img.shields.io/badge/PyTorch-2.9.1-EE4C2C.svg?logo=pytorch&logoColor=white)](https://pytorch.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A self-contained, portable environment for running **AMD ROCm PyTorch natively on Windows 11**. 

Get full hardware acceleration on AMD Radeon GPUs without dual-booting Linux, configuring WSL2, or modifying your global Python environment.

> [!NOTE]
> **Unofficial Community Project.** This repository is maintained independently and is not affiliated with or endorsed by Advanced Micro Devices, Inc. (AMD).

---

## Why WinROCm-PyTorch?

Running PyTorch on AMD GPUs under Windows has traditionally required navigating complex driver setups, environment path conflicts, missing C++ development headers, or accidental package downgrades. 

**WinROCm-PyTorch provides a clean, single-folder solution:**

- **Zero System Pollution**: Python 3.12, the AMD ROCm SDK, PyTorch wheels, caches, and temporary files all live inside a single directory. To uninstall, simply delete the folder.
- **No Python or PATH Conflicts**: Never interferes with existing Python, Conda, or Windows Store installations.
- **Accidental Downgrade Protection**: Built-in pip constraints prevent subsequent `pip install` commands from replacing your ROCm-accelerated PyTorch with generic CPU or CUDA wheels.
- **Native C/C++ Extension Support**: Ships with full Python C headers (`Python.h`) and libraries, allowing packages that build native extensions or Cython modules to compile smoothly.
- **Built-in Compatibility Shims**: Automatically discovers installed Visual Studio toolchains and handles Windows ROCm runtime quirks out of the box.

---

## Supported Hardware

| GPU Family | Supported Models | Setup Required |
|---|---|---|
| **RDNA4 & RDNA3 Flagships** | Radeon RX 9070, RX 9070 XT<br>Radeon RX 9060 XT<br>Radeon RX 7900 XTX, RX 7900 XT, RX 7900 GRE<br>Radeon AI PRO R9700, PRO W7900<br>Ryzen AI Max, Ryzen AI 9 | **Native (Plug & Play)** |
| **RDNA3 (Non-Flagship)** | Radeon RX 7800 XT, RX 7700 XT, RX 7600 XT, RX 7600 | Architecture override:<br>`HSA_OVERRIDE_GFX_VERSION=11.0.0` |
| **RDNA2 Series** | Radeon RX 6950 XT, RX 6900 XT, RX 6800 XT, RX 6800, RX 6700 XT | Architecture override:<br>`HSA_OVERRIDE_GFX_VERSION=10.3.0` |

---

## Prerequisites

1. **Operating System**: Windows 11 64-bit (Build 22000 or higher).
2. **AMD Graphics Driver**: Install AMD's official "PyTorch on Windows" Adrenalin driver before installation.
3. **Storage**: At least **15 GB** free disk space on the target drive (~3.5 GB download, ~11 GB installed footprint).
4. **PowerShell**: Windows PowerShell 5.1 (built into Windows) or PowerShell 7+.

---

## Quick Start

We recommend installing into a short path (such as `C:\rocm`) to avoid Windows `MAX_PATH` limitations.

### 1. Clone & Install

1. Open a Command Prompt or PowerShell terminal:
2. Clone the repository:
   ```cmd
   git clone https://github.com/ssrplays121/WinROCm-PyTorch.git C:\rocm
   cd /d C:\rocm
   ```
3. Run the installer:
   ```cmd
   setup.bat install
   ```
   *(For automated scripts or CI environments, pass `-y` to run unattended: `setup.bat install -y`)*.

### 2. Verify Hardware Acceleration

Run the verification probe to confirm GPU detection and test matrix multiplication:

```cmd
setup.bat verify
```
*(Or use `run_rocm bin\verify_rocm.py`)*.

If successful, you will see your AMD Radeon GPU identified with ROCm acceleration active.

---

## Package Manager & CLI Reference

WinROCm-PyTorch features a Linux package manager-style CLI (`dnf`/`apt` workflow). You can run commands locally via `setup.bat` or globally via `rocm` once added to your PATH:

| Command | Linux Equivalent | Description |
|---|---|---|
| `setup.bat install` | `dnf install` | Install isolated Python, ROCm SDK, and PyTorch environment. |
| `setup.bat status` | `dnf info` | Fast inspection of installed package versions and detected AMD GPU. |
| `setup.bat check-update` | `dnf check-update` | Preview available candidate updates from upstream without writing. |
| `setup.bat update` | `dnf update` / `apt upgrade` | Interactively inspect package diffs and prompt to upgrade. |
| `setup.bat update -y` | `dnf update -y` | Non-interactive unattended upgrade of all outdated packages. |
| `setup.bat verify` | — | Run hardware verification suite (GEMM, Conv2d, BatchNorm, Triton). |
| `setup.bat reinstall` | `dnf reinstall` | Wipe existing environment and perform a fresh install. |
| `setup.bat diagnose` | — | Generate `diagnose.txt` system telemetry report. |
| `setup.bat help` | `dnf --help` | Display command usage and available options. |

---

## How to Use

WinROCm-PyTorch isolates all executables within dedicated launcher wrappers inside `bin/`:

| Command | Description | Example |
|---|---|---|
| `rocm <command>` | Unified global CLI matching `setup.bat` from ANY folder | `rocm update -y` |
| `run_rocm <script.py>` | Run any Python script using the ROCm environment | `run_rocm my_model.py` |
| `pip_rocm install <pkg>` | Install packages safely with constraint protection | `pip_rocm install diffusers` |
| `shell_rocm` | Open an interactive command prompt bound to this environment | `shell_rocm` |
| `torchrun_rocm` | Execute distributed / multi-process scripts | `torchrun_rocm train.py` |
| `update_rocm` | Direct shortcut to check and apply updates | `update_rocm` |
| `. .\bin\env_rocm.ps1` | Activate the ROCm environment in an existing PowerShell session | `. .\bin\env_rocm.ps1` |

### Optional: Global Access via Windows User PATH

You can make `rocm`, `run_rocm`, `pip_rocm`, and `update_rocm` callable from **any directory or terminal** without typing full paths:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\add_to_path.ps1
```

> [!TIP]
> **Why this is safe:** This script only exposes the launcher wrappers (`bin/`), **not** the underlying `python.exe` or `pip.exe`. Your system-wide Python or Conda installations remain completely untouched.
>
> To remove it at any time, run `.\scripts\remove_from_path.ps1`.

---

## Using with Popular AI Applications

> [!IMPORTANT]
> **Understanding the `torch.cuda` API on AMD ROCm**  
> AMD ROCm maps the HIP device runtime directly to PyTorch's `torch.cuda` API at the driver level. When writing or running PyTorch code:
> - Use standard `device = "cuda"` or `tensor.to("cuda")`.
> - `torch.cuda.is_available()` returns `True`.
> - `torch.cuda.get_device_name(0)` returns your AMD GPU name.
>
> No emulation layers or DirectML wrappers are required.

### 1. ComfyUI

ComfyUI runs with native ROCm acceleration:

```cmd
:: 1. Clone ComfyUI
git clone https://github.com/comfyanonymous/ComfyUI.git C:\ComfyUI
cd /d C:\ComfyUI

:: 2. Install dependencies
pip_rocm install -r requirements.txt

:: 3. Launch ComfyUI
run_rocm main.py --highvram --preview-method auto
```

### 2. Stable Diffusion WebUI (Forge & Automatic1111)

Point your WebUI installation to the WinROCm-PyTorch runtime:

1. Open `webui-user.bat` in your WebUI folder.
2. Set the `PYTHON` path to your installation's Python executable:
   ```bat
   @echo off
   set PYTHON=C:\rocm\python\python.exe
   set GIT=
   set VENV_DIR=
   set COMMANDLINE_ARGS=--opt-sdp-attention --precision full --no-half
   call webui.bat
   ```
3. Run `webui-user.bat`. Built-in pip constraints prevent WebUI from accidentally overwriting your ROCm PyTorch installation.

### 3. Hugging Face Transformers & Diffusers

Install modern ML libraries and run inference or fine-tuning directly on your Radeon GPU:

```cmd
pip_rocm install transformers diffusers accelerate
```

Example Python snippet (`test_model.py`):

```python
import torch

print(f"Device: {torch.cuda.get_device_name(0)}")
x = torch.randn(2048, 2048, device="cuda")
y = torch.matmul(x, x)
print(f"Computation successful! Shape: {y.shape}")
```

Run with:

```cmd
run_rocm test_model.py
```

### 4. JupyterLab & VS Code Notebooks

Register the environment so it appears in Jupyter and VS Code kernel selectors:

```cmd
pip_rocm install ipykernel
run_rocm -m ipykernel install --user --name "winrocm-pytorch" --display-name "WinROCm PyTorch (AMD)"
```

To start a standalone JupyterLab server:

```cmd
pip_rocm install jupyterlab
run_rocm -m jupyterlab
```

---

## GPU Architecture Overrides

If your AMD GPU is not on AMD's default verification list (such as non-flagship RDNA3 or RDNA2 cards), PyTorch may report `hipErrorNoBinaryForGpu`. 

You can enable acceleration by setting the architecture override:

| GPU Family | Models | Override Value |
|---|---|---|
| **RDNA3 (Non-Flagship)** | RX 7800 XT, RX 7700 XT, RX 7600 XT, RX 7600 | `set HSA_OVERRIDE_GFX_VERSION=11.0.0` |
| **RDNA2 Series** | RX 6950 XT, RX 6900 XT, RX 6800 XT, RX 6800, RX 6700 XT | `set HSA_OVERRIDE_GFX_VERSION=10.3.0` |

### Applying the Override:
- **In Command Prompt**: Run `set HSA_OVERRIDE_GFX_VERSION=11.0.0` before running your script.
- **In PowerShell**: Run `$env:HSA_OVERRIDE_GFX_VERSION = "11.0.0"`.
- **Permanent in WinROCm**: Uncomment the `HSA_OVERRIDE_GFX_VERSION` line directly inside `bin\env_rocm.bat` and `bin\env_rocm.ps1`.

---

## Installer Parameters

You can customize the installer by passing parameters to `setup.bat` or `setup_rocm_portable.ps1`:

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-InstallDir <path>` | String | Script directory | Target directory for the portable installation. |
| `-RocmRelease <ver>` | String | `7.2` | ROCm release track (`7.2` or `7.2.1`). |
| `-WithTriton` | Switch | Off | Installs version-matched `triton-windows` for `torch.compile` support. |
| `-Reinstall` | Switch | Off | Wipes existing Python environment and performs a fresh clean install. |
| `-NoVision` | Switch | Off | Skips downloading and installing `torchvision`. |
| `-NoAudio` | Switch | Off | Skips downloading and installing `torchaudio`. |
| `-DryRun` | Switch | Off | Runs preflight checks, displays plan, and tests URLs without writing to disk. |
| `-Diagnose` | Switch | Off | Generates a system and GPU diagnostic report in `diagnose.txt`. |
| `-Yes` | Switch | Off | Bypasses the confirmation prompt for unattended installation. |

---

## Troubleshooting & FAQ

### `torch.cuda.is_available()` returns `False`
1. Ensure you have installed the official AMD Adrenalin "PyTorch on Windows" driver.
2. If using an RX 7600/7700/7800 or RX 6000 series card, verify that you have set the appropriate `HSA_OVERRIDE_GFX_VERSION`.
3. Generate a diagnostic report to inspect detected hardware and drivers:
   ```cmd
   setup.bat -Diagnose
   ```
   Open `diagnose.txt` to review the system probe details.

### Upgrades and Updates
WinROCm-PyTorch follows a Linux package manager update workflow:
- Preview updates without modifying anything:
  ```cmd
  setup.bat check-update       (or: rocm check-update)
  ```
- Interactively inspect candidate version diffs and update:
  ```cmd
  setup.bat update             (or: rocm update)
  ```
- Unattended upgrade in CI or automation:
  ```cmd
  setup.bat update -y          (or: rocm update -y)
  ```
To update specific Python packages while keeping ROCm locked, use `pip_rocm install -U <package>`. The built-in constraints file (`constraints-rocm.txt`) ensures PyTorch remains strictly pinned to AMD's ROCm wheels.

### How do I uninstall?
Because WinROCm-PyTorch does not touch the Windows Registry or system files, uninstalling is as simple as deleting the installation folder. If you registered the `bin/` directory to your user PATH, run `powershell -ExecutionPolicy Bypass -File .\scripts\remove_from_path.ps1` before deleting the folder.

---

## Architecture & Technical Deep Dive

For detailed technical documentation on how WinROCm-PyTorch functions under the hood—including toolchain discovery, runtime shims, MIOpen JIT compilation fallbacks, pip constraint mechanics, and custom source builds—see:

- 📖 **[Architecture & Technical Details](docs/technical-details.md)**: Runtime shims, MSVC/UCRT auto-discovery, wave-size reduction patches, and process isolation mechanics.
- 🛠️ **[Tier 2 Source Build Guide: ROCm/TheRock](docs/the-rock-build.md)**: Advanced guide for compiling custom AMD ROCm DLLs from source.

---

## License

This project is licensed under the [MIT License](LICENSE).  
For release notes and version history, see the [CHANGELOG.md](CHANGELOG.md).
