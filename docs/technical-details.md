# WinROCm-PyTorch Technical Architecture & Internals

This document covers the low-level architecture, runtime shims, environment isolation, toolchain discovery, and compatibility layers implemented in **WinROCm-PyTorch**.

---

## 1. Process-Level Isolation Architecture

WinROCm-PyTorch is engineered as a zero-pollution, self-contained environment. Unlike traditional Python distributions or Anaconda environments, it does not modify the Windows Registry, global system environment variables, or user-level directories.

### Directory Layout

```
<InstallDir>\
├── bin\                       # User-facing launchers & container boundary
│   ├── env_rocm.bat           # Environment injector for CMD
│   ├── env_rocm.ps1           # Environment injector for PowerShell
│   ├── pip_rocm.bat           # Constraint-guarded pip wrapper
│   ├── run_rocm.bat           # Script execution runner
│   ├── shell_rocm.bat         # Pre-configured interactive command prompt
│   ├── torchrun_rocm.bat      # PyTorch distributed runner
│   └── verify_rocm.py         # Hardware & matrix multiplication probe
├── config\
│   └── releases.psd1          # Release definitions & upstream wheel manifests
├── docs\                      # Extended technical documentation
│   ├── technical-details.md   # This architecture document
│   └── the-rock-build.md      # Tier 2 ROCm/TheRock compilation guide
├── python\                    # CPython 3.12 embeddable distribution
│   ├── include\               # Extracted C/C++ Python headers (Python.h)
│   ├── libs\                  # Extracted Python static libraries (python312.lib)
│   ├── Lib\site-packages\     # Installed wheels & dependencies
│   │   ├── _rocm_sdk_core\    # AMD ROCm Core SDK
│   │   ├── _rocm_sdk_devel\   # Materialized HIP & LLVM headers
│   │   └── sitecustomize.py   # Runtime compatibility & discovery shim
│   └── Scripts\               # Internal executables (isolated from PATH)
├── scripts\
│   ├── add_to_path.ps1        # Safe User PATH registration for bin/
│   └── remove_from_path.ps1   # PATH cleanup utility
├── .cache\                    # Isolated cache storage (Torch, HuggingFace, MIOpen)
├── .tmp\                      # Isolated scratch space (temp builds & pip builds)
├── constraints-rocm.txt       # Auto-generated pip pin locks
└── .rocm-portable.json        # Installation state & idempotency tracker
```

### Isolation Guarantees

- **`PYTHONNOUSERSITE=1`**: Prevents Python from loading packages installed in `%APPDATA%\Python\Python312\site-packages`, avoiding version conflicts.
- **Cache Redirection**: `TORCH_HOME`, `HF_HOME`, `TRITON_CACHE_DIR`, `MIOPEN_USER_DB_PATH`, and `MIOPEN_CUSTOM_CACHE_DIR` are all pinned to `<InstallDir>\.cache\`.
- **Temp Redirection**: `TEMP` and `TMP` within launcher processes point to `<InstallDir>\.tmp\`.
- **Path Isolation**: The root `python\` directory and `python\Scripts\` are **not** placed directly in the persistent Windows `PATH`. Only the specialized wrapper scripts in `bin/` are exposed.

---

## 2. Python C/C++ Development Headers

Official Python embeddable distributions (`python-3.12.x-embed-amd64.zip`) are minimal runtimes meant for bundling with applications; they omit C development headers (`Python.h`) and import libraries (`python312.lib`). 

Without these files, any downstream `pip install` command attempting to compile C/C++ extensions or Cython modules (e.g., FlashAttention, custom CUDA/HIP kernels, or specific data loaders) will fail with:

```text
fatal error C1083: Cannot open include file: 'Python.h': No such file or directory
```

### Automated Extraction Mechanism

During installation, WinROCm-PyTorch:
1. Downloads the matching official Python MSI development package (`dev.msi`) from `python.org`.
2. Verifies its SHA256 integrity hash against `config/releases.psd1`.
3. Performs an administrative MSI extraction (`msiexec /a dev.msi /qn TARGETDIR=...`) into temporary storage.
4. Moves `include\` (containing `Python.h` and associated C-API headers) and `libs\` (containing `python312.lib` and `python3.lib`) directly into `<InstallDir>\python\`.

---

## 3. Toolchain & Header Discovery (`sitecustomize.py`)

When PyTorch compiles JIT kernels on Windows via HIPRTC (HIP Runtime Compilation) or MIOpen, the compiler requires access to the MSVC C++ standard library (such as `<type_traits>`, `<utility>`, `<string>`) and the Windows Universal CRT (UCRT) headers.

WinROCm-PyTorch injects a dynamic configuration hook at startup via `python\Lib\site-packages\sitecustomize.py`:

```
┌─────────────────────────────────────────────────────────────┐
│                      Python Startup                         │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                     sitecustomize.py                        │
├─────────────────────────────────────────────────────────────┤
│ 1. Locate MSVC via vswhere.exe or registry/disk globbing    │
│    -> Appends Hostx64/x64 tools to PATH                     │
│    -> Appends MSVC include directories to INCLUDE / CPATH   │
│                                                             │
│ 2. Discover Windows 10/11 SDK UCRT headers                  │
│    -> Appends ucrt, shared, and um to INCLUDE / CPATH       │
│                                                             │
│ 3. Materialize ROCm SDK headers                             │
│    -> Discovers _rocm_sdk_devel and sets ROCM_PATH/HIP_PATH │
│                                                             │
│ 4. Install MetaPath Hook for torch import                   │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                     PyTorch Module Load                     │
├─────────────────────────────────────────────────────────────┤
│ - Strip NVIDIA CUDA arch checks                             │
│ - Set torch.version.cuda = "12.6" for library compatibility │
│ - Apply safe F.normalize L2 reduction patch                 │
│ - Apply resilient F.batch_norm with automatic ATen fallback │
└─────────────────────────────────────────────────────────────┘
```

### Visual Studio & Windows SDK Detection

The shim searches for:
1. **MSVC Toolset (v143 / v144 / v180+)**: Uses `vswhere.exe` to find Visual Studio 2022 or Visual Studio 2026 previews. If `vswhere.exe` is absent, it performs heuristic path discovery under `Program Files\Microsoft Visual Studio\`.
2. **Windows 10/11 SDK Universal CRT**: Probes `Program Files (x86)\Windows Kits\10\Include\<SDK-Version>\` and automatically discovers `ucrt`, `shared`, and `um` header folders.
3. **Environment Injection**: Normalizes discovered paths and prepends them to `PATH`, `INCLUDE`, `CPATH`, and `CPLUS_INCLUDE_PATH`.

---

## 4. Runtime Compatibility & Stability Patches

### Single-Execution MetaPath Import Hook

To patch PyTorch behaviors cleanly without executing module initialization code twice, `sitecustomize.py` registers an `importlib.abc.MetaPathFinder` hook (`_TorchPostImportHook`). The hook intercepts the loading of `torch`, invokes the original loader once, and immediately executes internal patches before user code runs.

### CUDA Capability Check Bypass

Upstream PyTorch includes checks (such as `_check_capability` and `_check_cubins`) designed to validate NVIDIA compute architectures. Under ROCm, these checks are unnecessary and can trigger false-positive warnings or exceptions. The import hook removes these queued calls and provides a safe fallback for architecture extraction.

### CUDA Version Spoofing

Many popular third-party machine learning libraries (such as certain releases of FlashAttention, vLLM, or Triton wrappers) check `torch.version.cuda` and throw errors if it returns `None`. 

Because AMD ROCm on Windows translates the HIP device API to the `torch.cuda` namespace, `sitecustomize.py` sets:

```python
if torch.version.cuda is None:
    torch.version.cuda = "12.6"
```

This satisfies strict third-party checks while retaining true ROCm device acceleration underneath.

### Safe L2 Normalize Patch (`F.normalize`)

In certain ROCm Windows driver and runtime builds, running `torch.nn.functional.normalize` with $p = 2.0$ over tensor reductions can cause low-level wave-size reduction crashes inside the HIP device driver. 

`sitecustomize.py` overrides `F.normalize` with a mathematically equivalent, numerically stable ATen formulation:

$$\text{normalized}(x) = \frac{x}{\max\left(\sqrt{\sum x^2}, \epsilon\right)}$$

This preserves exact fp32/fp16 precision while eliminating native driver reduction crashes.

### Resilient BatchNorm with Automatic ATen Fallback (ROCm/TheRock #9206)

When executing convolutional networks or vision models with BatchNorm layers on tensors larger than $32 \times 32$, MIOpen attempts to JIT-compile specialized kernels via HIPRTC. If MSVC C++ headers are missing or HIPRTC fails to compile the kernel, MIOpen previously raised a fatal `RuntimeError: miopenStatus` exception.

WinROCm-PyTorch wraps `F.batch_norm` to detect MIOpen JIT failures automatically:
- When a failure is detected, it logs an informative advisory warning.
- It immediately evaluates the operation using PyTorch's native ATen fallback (`with torch.backends.cudnn.flags(enabled=False): ...`).
- Your model continues executing without crashing.

---

## 5. ROCm SDK Materialization (`rocm-sdk init`)

AMD packages the ROCm Windows runtime across several wheels:
- `rocm_sdk_core`: Core runtime binaries (`amdhip64.dll`, `hiprtc.dll`, etc.).
- `rocm_sdk_devel`: Compilers (`hipcc.exe`, `amdclang.exe`) and device header archives.
- `rocm_sdk_libraries_custom`: Vendor libraries (`rocBLAS`, `hipBLAS`, `MIOpen`, `rocFFT`).

When `rocm_sdk_devel` is installed, device header files (such as `hip/hip_runtime.h`) are packaged inside compressed archives. WinROCm-PyTorch automatically invokes:

```cmd
rocm-sdk.exe init
```

This materializes the full header tree inside `_rocm_sdk_devel\include` and exports the canonical `ROCM_PATH` and `HIP_PATH` root directories.

---

## 6. Constraints Lock Protection (`constraints-rocm.txt`)

A common failure mode when using ROCm on Windows occurs when a user runs a standard pip command, such as:

```cmd
pip install transformers torchvision
```

Because PyPI's official repository indexes CUDA and CPU wheels by default, standard pip dependency resolution will often attempt to uninstall AMD's custom-built `torch` wheel and replace it with a vanilla CUDA or CPU build.

### How WinROCm-PyTorch Prevents This

1. At the completion of installation, `setup_rocm_portable.ps1` probes the exact package names and versions of all installed ROCm wheels (`torch`, `torchvision`, `torchaudio`, `rocm-sdk-*`).
2. It writes a strict lock file to `<InstallDir>\constraints-rocm.txt`:
   ```text
   torch==2.9.1+rocmsdk20260116
   torchvision==0.24.1+rocmsdk20260116
   torchaudio==2.9.1+rocmsdk20260116
   rocm_sdk_core==7.2.0.dev0
   ...
   ```
3. All wrapper launchers (`pip_rocm.bat`, `run_rocm.bat`, `env_rocm.bat`, `env_rocm.ps1`) set:
   ```cmd
   set PIP_CONSTRAINT=<InstallDir>\constraints-rocm.txt
   ```
4. Pip strictly honors this constraint. Any command attempting to downgrade or replace PyTorch will halt with an explanatory resolution error rather than silently corrupting your installation.

---

## 7. Triton for Windows (`torch.compile`) & Portable MSVC Toolchain

`torch.compile` requires Triton to lower PyTorch computation graphs into high-performance GPU kernels. Triton historically lacked native Windows support, but community pre-built wheels (`triton-windows`) provide Windows-native JIT acceleration.

### The MSVC Compiler Requirement
Both Triton and PyTorch Inductor require a C++ compiler (`cl.exe`), C++ STL headers (`<type_traits>`, `<vector>`), and Windows SDK UCRT headers/libraries (`<stdio.h>`, `ucrt.lib`, `kernel32.lib`):
1. **PyTorch Inductor**: Generates C++ wrappers and CPU kernels using `cl.exe`. Without a C++ compiler, `torch.compile` fails with `torch._inductor.exc.BackendCompilerFailed` or `CppCompileError`.
2. **Triton JIT**: Generates and compiles C launcher stubs using `cl.exe`.
3. **MIOpen JIT**: Requires standard C++ STL headers (`<type_traits>`) for BatchNorm and Conv2d hardware kernels.

### Lightweight Portable MSVC Toolchain (`.\msvc\`)
Instead of forcing users to install the 4–60 GB Visual Studio IDE with administrative privileges, WinROCm-PyTorch includes `scripts/portable-msvc.py`:
- Downloads only the standalone x64 compiler, linker, MSVC STL headers, and Windows SDK UCRT/UM headers and libraries directly from Microsoft's official CDN (`https://aka.ms/vs/17/release/channel`).
- **Download footprint**: ~130 MB compressed.
- **Disk footprint**: ~450 MB uncompressed in `<InstallDir>\msvc\`.
- **Zero elevation / zero registry pollution**: 100% self-contained within the installation directory.

### Three-Layer Toolchain Injection
When Portable MSVC is present, toolchain environment variables are automatically configured across three layers:
1. **`sitecustomize.py` (Python Runtime Injection)**:
   - On Python startup, `_discover_and_inject_toolchains()` detects `<rocm_root>\msvc` before searching system paths.
   - Prepends MSVC and SDK binary paths to `PATH`.
   - Prepends MSVC and UCRT include directories to `INCLUDE`.
   - Prepends MSVC and UCRT include directories with forward slashes (`/`) to `CPATH` and `CPLUS_INCLUDE_PATH` for HIPRTC / AMD Clang.
   - Prepends MSVC and UCRT library directories to `LIB`.
   - Sets `DISTUTILS_USE_SDK=1` and `MSSdk=1` to notify setuptools that the SDK environment is pre-initialized.
2. **Launchers (`env_rocm.bat`, `env_rocm.ps1`, `shell_rocm.bat`)**:
   - Automatically sources `msvc\setup_x64.bat` to expose `cl.exe` directly in interactive CMD and PowerShell sessions.
3. **Inductor Safety Fallback**:
   - If MSVC is omitted and a user runs `torch.compile`, `sitecustomize.py` intercepts compiler-missing exceptions, issues an actionable warning, and falls back to standard eager execution instead of terminating with an unhandled crash.

---

## 8. Tier 2 Custom Compilation (ROCm / TheRock)

The runtime shims described above provide **Tier 1 (Zero-Compilation)** stability for the vast majority of workflows. 

If your work requires modifying AMD's low-level C++ runtime DLLs (such as hacking memory scratchpad sizes directly in `MIOpen.dll` or compiling custom hardware targets not supported by official wheels), refer to:

👉 [Tier 2 Source Build Guide: ROCm/TheRock](the-rock-build.md)

