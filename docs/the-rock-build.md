# Tier 2 Source Build Guide: ROCm/TheRock & Custom DLL Compilation

This guide documents the procedures for compiling, patching, and deploying custom ROCm Windows runtime DLLs (such as `MIOpen.dll` and `amdhip64.dll`) using AMD's `ROCm/TheRock` CMake super-project.

---

## When is Tier 2 Compilation Needed?

WinROCm-PyTorch includes **Tier 1 zero-compilation runtime shims** (`sitecustomize.py`) that resolve header discovery and provide automatic resilient fallbacks without compiling C++ binaries.

You only need **Tier 2 compilation** if you need:
1. **Direct C++ modifications** to the MIOpen convolution algorithm engine (e.g. permanently patching immediate mode scratchpad workspace allocation).
2. **Hardcoding HIPRTC include directories** into `MIOpen.dll` rather than relying on `sitecustomize.py` path injection.
3. **Custom device architecture targets** not present in official binary wheels.
4. **Debugging low-level runtime crashes** inside `amdhip64.dll` or `hiprtc.dll`.

---

## Prerequisites

1. **Operating System**: Windows 11 64-bit (Build 22000 or higher).
2. **Disk Storage**: At least **200 GB** of free space. A **Windows 11 Dev Drive (ReFS)** is strongly recommended to dramatically reduce build times and file I/O latency.
3. **Developer Mode**: Enable Windows Developer Mode (`Settings > System > For developers`) to allow unprivileged symlink and hardlink creation.
4. **Enable Windows Long Paths**:
   ```cmd
   reg add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v LongPathsEnabled /t REG_DWORD /d 1 /f
   git config --system core.longpaths true
   ```
5. **MSVC Build Tools**: Visual Studio 2022 (v14.43+ / VS 17.13+) or Visual Studio 2026 preview with:
   - "Desktop development with C++"
   - Windows 11 SDK (10.0.22621+)
   - CMake Tools for Windows
   - Ninja build system
6. **Clean Environment**: Remove any globally installed HIP SDK to prevent header and DLL shadowing.

---

## Step 1: Clone TheRock Super-Project

Execute from a standard `cmd.exe` terminal:

```cmd
chcp 65001
git clone https://github.com/ROCm/TheRock.git
cd TheRock
python -m venv .venv
.venv\Scripts\activate.bat
pip install --upgrade pip
pip install -r requirements.txt
python ./build_tools/fetch_sources.py
```

---

## Step 2: Apply Source Patches

### 1. Fix HIPRTC Include Paths in MIOpen ([ROCm/TheRock#9206](https://github.com/ROCm/TheRock/issues/9206))

To ensure HIPRTC locates `<type_traits>` and `<crtdefs.h>` without external environment variables:
1. Open `rocm-libraries/projects/miopen/src/hipoc/hipoc_program.cpp`.
2. Locate `hipoc_program::BuildHip` (~line 299).
3. Append normalized forward-slashed `-I` flags pointing to your MSVC and Windows SDK UCRT include directories into the compilation options string passed to `hiprtcCompileProgram`:
   ```cpp
   // Append MSVC & Windows SDK headers (use forward slashes)
   options += " -I\"C:/Program Files/Microsoft Visual Studio/2022/Community/VC/Tools/MSVC/<version>/include\"";
   options += " -I\"C:/Program Files (x86)/Windows Kits/10/Include/<version>/ucrt\"";
   options += " -I\"C:/Program Files (x86)/Windows Kits/10/Include/<version>/shared\"";
   ```

### 2. Fix Immediate Mode Zero-Workspace Convolutions ([ROCm/TheRock#3077](https://github.com/ROCm/TheRock/issues/3077))

To prevent MIOpen from falling back to `ConvDirectNaiveConvFwd` when PyTorch supplies `workspace = 0`:
1. In MIOpen's convolution forward find implementation (`src/convolution.cpp` / immediate mode):
   Ensure that `FindConvFwdAlgorithm` allocates or requests a minimum non-zero scratchpad workspace buffer (e.g. 32MB) rather than defaulting to naive convolution paths when passed a null workspace pointer.
2. Alternatively, apply the [`imagilux/miopen-conv-fix`](https://github.com/imagilux/miopen-conv-fix) workspace patch.

---

## Step 3: Build Binaries

Launch the **Visual Studio x64 Native Tools Command Prompt** and run CMake with Ninja:

```cmd
:: For RDNA3 (RX 7000 series):
cmake -B build -GNinja . -DTHEROCK_AMDGPU_FAMILIES=gfx110X-all

:: Or for RDNA4 (RX 9000 series):
cmake -B build -GNinja . -DTHEROCK_AMDGPU_FAMILIES=gfx120X-all

:: Build entire super-project or MIOpen specifically:
cmake --build build --target MIOpen
```

*(Tip: To build only HIP runtime, target `amdhip64`: `cmake --build build --target amdhip64`)*.

---

## Step 4: Deploy Built DLLs to WinROCm-PyTorch

Built DLLs are generated in `TheRock\build\dist\rocm\bin\`.

1. Copy the newly compiled `MIOpen.dll` into WinROCm-PyTorch:
   ```cmd
   copy /Y "TheRock\build\dist\rocm\bin\MIOpen.dll" "C:\rocm\python\Lib\site-packages\_rocm_sdk_libraries_custom\bin\"
   ```
2. If `torch\lib\MIOpen.dll` exists in your container, update it as well:
   ```cmd
   copy /Y "TheRock\build\dist\rocm\bin\MIOpen.dll" "C:\rocm\python\Lib\site-packages\torch\lib\"
   ```
3. If you compiled custom `amdhip64.dll` or `hiprtc64.dll`, deploy them to:
   ```cmd
   copy /Y "TheRock\build\dist\rocm\bin\amdhip64.dll" "C:\rocm\python\Lib\site-packages\_rocm_sdk_core\bin\"
   ```

---

## Step 5: Purge Kernel Caches

Cached kernels from previous runs must be purged to prevent execution of stale, corrupt, or unpatched kernels:

```cmd
:: WinROCm-PyTorch isolated container cache
rmdir /s /q "C:\rocm\.cache\miopen"

:: System-level caches (if any)
if exist "%USERPROFILE%\.cache\miopen" rmdir /s /q "%USERPROFILE%\.cache\miopen"
if exist "%LOCALAPPDATA%\miopen" rmdir /s /q "%LOCALAPPDATA%\miopen"
```

---

## Step 6: Verify Deployment

Run the WinROCm-PyTorch verification test:

```cmd
run_rocm .\bin\verify_rocm.py
```

Confirm that **GPU Conv2d** reports `OK` with sub-millisecond execution times and **BatchNorm2d** passes cleanly.

