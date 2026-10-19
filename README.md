# WinROCm-PyTorch

> **Unofficial project.** Not affiliated with or endorsed by Advanced Micro Devices, Inc. (AMD).

A single-folder, fully isolated portable environment for **AMD ROCm PyTorch on Windows 11** (RDNA3 and RDNA4 GPUs, including Radeon RX 9060 XT, RX 9070, and RX 7900 series, with compatibility overrides for RX 7800/7700/7600 and RX 6000 RDNA2).

Everything—Python 3.12, C/C++ development headers (`Python.h`, `python312.lib`), AMD ROCm SDK wheels, PyTorch (`torch`, `torchvision`, `torchaudio`), caches, and temp directories—lives inside a **single folder**. Nothing pollutes your system `PATH`, Windows Registry, `%APPDATA%`, or user pip caches by default.

---

## What You Get

- **Zero System Pollution**: Completely portable. To uninstall, simply delete the folder.
- **Dedicated Container Directory (`bin/`)**: All launcher scripts live in `bin/`. Any temporary artifacts created beside them are safely quarantined inside the container.
- **Global Access Without Collisions**: Add `bin/` to your Windows User `PATH` (manually or via script) to run `run_rocm`, `pip_rocm`, and `torchrun_rocm` from any terminal without shadowing global `python` or `pip`.
- **Bundled C/C++ Development Headers**: Automatically downloads and unpacks official Python development headers (`include/Python.h` and `libs/python312.lib`), enabling `pip` packages that build native C/C++ extensions or Cython modules.
- **Official Binaries**: Directly downloads official AMD ROCm wheels and python.org packages; no repackaged third-party binaries.
- **Constraints Protection**: Generates `constraints-rocm.txt` so subsequent `pip install` commands cannot accidentally replace AMD's ROCm PyTorch with PyPI CUDA/CPU wheels.
- **Preflight Validation & Diagnostics**: Robust preflight checks (PS 5.1 and 7+ compatible) that never create unwanted directories on disk before confirmation. Includes `-DryRun` and `-Diagnose`.
- **One-Click Bootstrapper**: Double-click `setup.bat` to install without PowerShell execution policy restrictions.

---

## Requirements

1. **Operating System**: Windows 11 64-bit (Build 22000 or newer).
2. **Supported AMD GPU**:
   - **Native RDNA3/RDNA4 Flagships**:
     - AMD Radeon RX 9070 / RX 9070 XT
     - AMD Radeon RX 9060 XT
     - AMD Radeon RX 7900 XTX / 7900 XT / 7900 GRE
     - AMD Radeon AI PRO R9700 / PRO W7900
     - AMD Ryzen AI Max / Ryzen AI 9 processors
   - **RDNA3 Non-Flagships & RDNA2 (via Architecture Override)**:
     - AMD Radeon RX 7800 XT / RX 7700 XT / RX 7600 XT (`HSA_OVERRIDE_GFX_VERSION=11.0.0`)
     - AMD Radeon RX 6950 XT / RX 6900 XT / RX 6800 XT / RX 6800 / RX 6700 XT (`HSA_OVERRIDE_GFX_VERSION=10.3.0`)
3. **AMD Adrenalin Driver**: Install AMD's official "PyTorch on Windows" Adrenalin driver package before running.
4. **Disk Space**: At least **15 GB** free on the target drive (~3.5 GB download, ~11 GB installed footprint).
5. **PowerShell**: Windows PowerShell 5.1 or PowerShell 7+.

---

## Quick Start

We recommend installing into a short path (e.g. `C:\rocm`) to avoid Windows `MAX_PATH` limitations:

```cmd
:: 1. Clone repository
git clone https://github.com/ssrplays121/WinROCm-PyTorch.git C:\rocm
cd /d C:\rocm

:: 2. Run the bootstrapper (interactive confirmation prompt)
setup.bat

:: Or unattended / CI mode:
setup.bat -Yes
```

> [!TIP]
> You can also run the PowerShell installer directly:
> ```powershell
> powershell.exe -ExecutionPolicy Bypass -File .\setup_rocm_portable.ps1
> ```
> If you downloaded the repository as a ZIP archive, unblock files first: `Unblock-File .\setup_rocm_portable.ps1`.

---

## Global Access via Windows User PATH

You can make WinROCm commands available in **any terminal, prompt, or external script across your entire system** without having to type `C:\rocm\bin\` or navigate to the install directory.

### Why this is safe:
Unlike typical Python installers, adding `C:\rocm\bin` to your User `PATH` **only exposes the launcher scripts** (`run_rocm`, `pip_rocm`, `torchrun_rocm`, `shell_rocm`). The underlying `python.exe` and `pip.exe` remain isolated inside `python\`, meaning:
- **No Python collisions**: Your system Python (3.10, 3.11), Anaconda, or Windows Store Python will **never** be shadowed or overridden.
- **Instant access**: Type `run_rocm my_script.py` from any directory or project folder.

### Option A: Automated PowerShell Script (Recommended)
Run in PowerShell (no administrator privileges needed):
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\add_to_path.ps1
```
*(To remove it later, run `.\scripts\remove_from_path.ps1`)*.

### Option B: Manual Windows GUI Setup
1. Press `Win + R`, type `sysdm.cpl`, and press **Enter** (System Properties).
2. Go to the **Advanced** tab and click **Environment Variables...**
3. Under **User variables for <YourUser>**, select `Path` and click **Edit...**
4. Click **New** and enter the full path to your `bin` folder (e.g. `C:\rocm\bin`).
5. Click **OK** on all windows, and restart any open terminal windows.

---

## Usage

All commands execute against the isolated environment in the folder:

### 1. Run a Python script (`run_rocm`)
```cmd
:: If in PATH:
run_rocm my_script.py

:: Or direct path:
.\bin\run_rocm.bat my_script.py
```

### 2. Install packages (`pip_rocm`)
```cmd
pip_rocm install transformers accelerate diffusers
```
*(Package installs strictly obey `constraints-rocm.txt`—pip will never replace AMD's ROCm PyTorch wheels with vanilla PyPI CUDA/CPU wheels).*

### 3. Open an interactive Command Prompt (`shell_rocm`)
```cmd
shell_rocm
```
Launches an isolated `cmd` session where `python` and `pip` point directly to this container and start in the installation directory.

### 4. Load environment in PowerShell (`env_rocm.ps1`)
Dot-source the launcher to activate the environment in your current PowerShell session:
```powershell
. .\bin\env_rocm.ps1
python -c "import torch; print(torch.cuda.is_available())"
```

### 5. Run verification test
Test hardware acceleration and matrix multiplication:
```cmd
run_rocm .\bin\verify_rocm.py
```

---

## Setting Up AI & Machine Learning Frameworks

> [!IMPORTANT]
> **Understanding the `torch.cuda` Namespace on AMD ROCm**
> In AMD ROCm PyTorch on Windows, AMD maps the ROCm/HIP device runtime directly onto PyTorch's `torch.cuda` API at the driver level. 
> 
> When running Python code, **always use `torch.cuda` calls**:
> - `torch.cuda.is_available()` returns `True`
> - `model.to("cuda")` or `device="cuda"` loads your model onto your AMD Radeon GPU.
> - `torch.cuda.get_device_name(0)` displays your AMD GPU (e.g. `AMD Radeon RX 9060 XT`).
> 
> You do **not** need DirectML translation layers or emulation wrappers—this is pure, native ROCm acceleration.

---

### 1. ComfyUI (Generative Image & Video)

ComfyUI runs with native ROCm acceleration on AMD GPUs using WinROCm-PyTorch:

```cmd
:: 1. Clone ComfyUI into your projects directory
git clone https://github.com/comfyanonymous/ComfyUI.git C:\AI\ComfyUI
cd /d C:\AI\ComfyUI

:: 2. Install ComfyUI dependencies using pip_rocm
pip_rocm install -r requirements.txt

:: 3. Launch ComfyUI with high VRAM allocation
run_rocm main.py --highvram --preview-method auto
```

#### Installing ComfyUI Custom Nodes:
When a custom node has extra requirements, use `pip_rocm`:
```cmd
cd /d C:\AI\ComfyUI\custom_nodes\ComfyUI-Manager
pip_rocm install -r requirements.txt
```

---

### 2. Stable Diffusion WebUI (Forge & Automatic1111)

To point SD WebUI Forge or Automatic1111 to WinROCm-PyTorch:

1. Open `webui-user.bat` in your SD WebUI directory.
2. Set the `PYTHON` variable to point to your `python.exe`:
   ```bat
   @echo off
   set PYTHON=C:\rocm\python\python.exe
   set GIT=
   set VENV_DIR=
   set COMMANDLINE_ARGS=--opt-sdp-attention --precision full --no-half
   call webui.bat
   ```
3. Run `webui-user.bat`. The built-in `constraints-rocm.txt` prevents WebUI from overriding your ROCm PyTorch with CUDA wheels.

---

### 3. Hugging Face Diffusers (SDXL, Flux, Stable Diffusion)

Generate images programmatically using official Hugging Face pipelines:

```cmd
pip_rocm install diffusers transformers accelerate invisible-watermark
```

Create `generate_sdxl.py`:
```python
import torch
from diffusers import DiffusionPipeline

print(f"Using device: {torch.cuda.get_device_name(0)}")

# Load model in fp16
pipe = DiffusionPipeline.from_pretrained(
    "stabilityai/stable-diffusion-xl-base-1.0",
    torch_dtype=torch.float16,
    use_safetensors=True
).to("cuda")

# Generate image
prompt = "Astronaut in a jungle, cold color palette, 8k resolution"
image = pipe(prompt=prompt, num_inference_steps=30).images[0]
image.save("astronaut.png")
print("Image saved to astronaut.png!")
```

Run with:
```cmd
run_rocm generate_sdxl.py
```

---

### 4. Hugging Face Transformers & Local LLMs

Run open-source large language models (Qwen 2.5, Llama 3.2, Mistral, Gemma 2):

```cmd
pip_rocm install transformers accelerate sentencepiece protobuf tiktoken
```

Create `run_llm.py`:
```python
import torch
from transformers import AutoModelForCausalLM, AutoTokenizer

model_id = "Qwen/Qwen2.5-1.5B-Instruct"

print(f"Loading {model_id} on {torch.cuda.get_device_name(0)}...")
tokenizer = AutoTokenizer.from_pretrained(model_id)
model = AutoModelForCausalLM.from_pretrained(
    model_id,
    torch_dtype=torch.bfloat16,
    device_map="cuda"
)

prompt = "Explain quantum computing in three clear bullet points."
inputs = tokenizer(prompt, return_tensors="pt").to("cuda")

with torch.no_grad():
    outputs = model.generate(**inputs, max_new_tokens=150)

response = tokenizer.decode(outputs[0], skip_special_tokens=True)
print("\n" + response)
```

Run with:
```cmd
run_rocm run_llm.py
```

---

### 5. Fine-Tuning & Model Training (PEFT / LoRA)

Train adapters and fine-tune models directly on your AMD GPU:

```cmd
pip_rocm install peft datasets trl
```

Because WinROCm-PyTorch includes official Python C/C++ development headers (`Python.h`, `python312.lib`), packages that require native building or compilation work without "missing Python.h" errors.

---

### 6. Computer Vision (Ultralytics YOLO)

Train and run real-time object detection models (YOLOv8 / YOLO11):

```cmd
pip_rocm install ultralytics
```

Run inference:
```python
import torch
from ultralytics import YOLO

print("ROCm Active:", torch.cuda.is_available())
model = YOLO("yolo11n.pt")  # automatically downloads weights
results = model.predict(source="https://ultralytics.com/images/bus.jpg", device="cuda")
results[0].save(filename="detected_bus.jpg")
print("Saved detection to detected_bus.jpg")
```

---

### 7. Speech-to-Text (OpenAI Whisper)

High-speed GPU audio transcription:

```cmd
pip_rocm install openai-whisper
```

Transcribe audio with:
```python
import whisper

model = whisper.load_model("small", device="cuda")
result = model.transcribe("sample_audio.mp3")
print("Transcription:\n", result["text"])
```

---

### 8. Jupyter Notebooks & JupyterLab

Register WinROCm-PyTorch so it appears in JupyterLab, classic Notebooks, and VS Code:

```cmd
pip_rocm install ipykernel
run_rocm -m ipykernel install --user --name "winrocm-pytorch" --display-name "WinROCm PyTorch"
```

Select **"WinROCm PyTorch"** from your notebook's kernel dropdown.

To run a standalone JupyterLab server:
```cmd
pip_rocm install jupyterlab
run_rocm -m jupyterlab
```

---

## GPU Architecture Overrides (`HSA_OVERRIDE_GFX_VERSION`)

If you have an AMD GPU that is not on AMD's official Windows verification list (e.g. non-flagship RDNA3 or RDNA2 series), PyTorch may throw `hipErrorNoBinaryForGpu`.

You can enable full acceleration by setting the architecture override:

| GPU Family | Models | Override Value |
|---|---|---|
| **RDNA3 (Non-Flagship)** | RX 7600, RX 7600 XT, RX 7700 XT, RX 7800 XT | `set HSA_OVERRIDE_GFX_VERSION=11.0.0` |
| **RDNA2** | RX 6700 XT, RX 6800, RX 6800 XT, RX 6900 XT, RX 6950 XT | `set HSA_OVERRIDE_GFX_VERSION=10.3.0` |

### How to apply:
- **In Command Prompt / Batch**: Add `set HSA_OVERRIDE_GFX_VERSION=11.0.0` before running your script (or uncomment the line in `bin\env_rocm.bat`).
- **In PowerShell**: Set `$env:HSA_OVERRIDE_GFX_VERSION = "11.0.0"` (or uncomment the line in `bin\env_rocm.ps1`).

---

## Parameters

| Parameter | Type | Description |
|---|---|---|
| `-InstallDir <path>` | String | Destination folder (defaults to script's own directory). |
| `-RocmRelease <ver>` | String | ROCm release to install (`7.2` or `7.2.1`). Defaults to `7.2`. |
| `-NoVision` | Switch | Skip downloading and installing `torchvision`. |
| `-NoAudio` | Switch | Skip downloading and installing `torchaudio`. |
| `-Reinstall` | Switch | Wipe existing `python\`, state, and constraints, then perform a clean reinstall. |
| `-SkipGpuCheck` | Switch | Suppress warning if detected GPU is not on AMD's verified list. |
| `-SkipVerify` | Switch | Skip running `verify_rocm.py` at the end of setup. |
| `-DryRun` | Switch | Run preflight checks, display the plan, perform HEAD checks on all URLs, and exit without downloading or modifying disk. |
| `-Diagnose` | Switch | Collect system, GPU, driver, and PyTorch probe diagnostics into `diagnose.txt` and exit. |
| `-Yes` | Switch | Bypass the confirmation prompt (required for non-interactive CI). |

---

## Limitations

1. **CPython 3.12 Only**: AMD's Windows wheels are compiled strictly for `cp312`.
2. **Windows 11**: AMD officially targets Windows 11 64-bit for ROCm on Windows.
3. **`torch.compile` / Triton**: Triton on Windows remains experimental under AMD's Windows wheels.
4. **PyTorch Distributed (`torchrun`)**: PyTorch on Windows omits the Rendezvous Store component of c10d, so multi-process distributed training via `torchrun` has limited Windows support. Single-GPU training works completely natively.

---

## Troubleshooting

### `torch.cuda.is_available()` returns `False`
1. Confirm that AMD's official "PyTorch on Windows" Adrenalin driver is installed.
2. If using an RX 7600/7700/7800 or RX 6000 GPU, ensure `HSA_OVERRIDE_GFX_VERSION` is set.
3. Run diagnostics:
   ```cmd
   setup.bat -Diagnose
   ```
   Inspect `diagnose.txt` to verify driver and device detection.

---

## License

This project is licensed under the [MIT License](LICENSE).
For details on changes and release history, see [CHANGELOG.md](CHANGELOG.md).
