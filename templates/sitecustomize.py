"""
WinROCm-PyTorch Runtime Shim (sitecustomize.py)
Automated VS 2022/2026 + Windows SDK UCRT discovery, ROCm include injection,
and post-import stability patches for PyTorch on native Windows.
"""
import glob
import importlib.abc
import importlib.machinery
import os
import subprocess
import sys
import warnings

# 1. Performance & Cache Environment Defaults
os.environ.setdefault("TORCH_BLAS_PREFER_HIPBLASLT", "1")

# Centralize TunableOp cache file if TunableOp is enabled by the user
if os.environ.get("PYTORCH_TUNABLEOP_ENABLED") == "1":
    rocm_root = os.environ.get("ROCM_ROOT") or os.path.abspath(
        os.path.join(sys.prefix, "..")
    )
    cache_dir = os.path.join(rocm_root, ".cache")
    os.makedirs(cache_dir, exist_ok=True)
    os.environ.setdefault(
        "PYTORCH_TUNABLEOP_FILENAME",
        os.path.join(cache_dir, "tunableop_results.csv"),
    )


def _prepend_env_path(var_name: str, new_paths: list[str], use_forward_slash: bool = False) -> None:
    existing = os.environ.get(var_name, "")
    existing_parts = [p for p in existing.split(os.pathsep) if p]
    added = []
    for p in new_paths:
        if not p or not os.path.isdir(p):
            continue
        norm_p = p.replace("\\", "/") if use_forward_slash else os.path.normpath(p)
        if norm_p not in existing_parts and norm_p not in added:
            added.append(norm_p)
    if added:
        os.environ[var_name] = os.pathsep.join(added + existing_parts)


def _discover_and_inject_toolchains() -> None:
    include_dirs = []
    bin_dirs = []
    lib_dirs = []

    rocm_root = os.environ.get("ROCM_ROOT") or os.path.abspath(
        os.path.join(sys.prefix, "..")
    )
    portable_msvc = os.path.join(rocm_root, "msvc")
    portable_found = False

    # A. Check for self-contained Portable MSVC in <ROCM_ROOT>\msvc
    if os.path.isdir(portable_msvc):
        p_msvc_dirs = glob.glob(
            os.path.join(portable_msvc, "VC", "Tools", "MSVC", "*")
        )
        if p_msvc_dirs:
            latest_p_msvc = sorted(p_msvc_dirs)[-1]
            p_bin = os.path.join(latest_p_msvc, "bin", "Hostx64", "x64")
            p_inc = os.path.join(latest_p_msvc, "include")
            p_lib = os.path.join(latest_p_msvc, "lib", "x64")
            if os.path.isdir(p_bin):
                bin_dirs.append(p_bin)
            if os.path.isdir(p_inc):
                include_dirs.append(p_inc)
            if os.path.isdir(p_lib):
                lib_dirs.append(p_lib)

            # SDK inside portable MSVC
            p_kits_inc = os.path.join(portable_msvc, "Windows Kits", "10", "Include")
            if os.path.isdir(p_kits_inc):
                p_sdk_vers = sorted(glob.glob(os.path.join(p_kits_inc, "*")))
                if p_sdk_vers:
                    latest_p_sdk = os.path.basename(p_sdk_vers[-1])
                    for sub in ("ucrt", "shared", "um"):
                        sub_dir = os.path.join(p_kits_inc, latest_p_sdk, sub)
                        if os.path.isdir(sub_dir):
                            include_dirs.append(sub_dir)
                    p_sdk_bin = os.path.join(
                        portable_msvc, "Windows Kits", "10", "bin", latest_p_sdk, "x64"
                    )
                    if os.path.isdir(p_sdk_bin):
                        bin_dirs.append(p_sdk_bin)
                    for sub_lib in ("ucrt", "um"):
                        sub_lib_dir = os.path.join(
                            portable_msvc, "Windows Kits", "10", "Lib", latest_p_sdk, sub_lib, "x64"
                        )
                        if os.path.isdir(sub_lib_dir):
                            lib_dirs.append(sub_lib_dir)

            os.environ.setdefault("DISTUTILS_USE_SDK", "1")
            os.environ.setdefault("MSSdk", "1")
            portable_found = True

    # B. If portable MSVC is not found, fallback to system Visual Studio & Windows Kits
    if not portable_found:
        prog_roots = []
        for var in ("ProgramFiles(x86)", "ProgramFiles", "ProgramW6432"):
            val = os.environ.get(var)
            if val and val not in prog_roots:
                prog_roots.append(val)

        vs_install_dirs = []
        for root in prog_roots:
            vswhere = os.path.join(root, "Microsoft Visual Studio", "Installer", "vswhere.exe")
            if os.path.isfile(vswhere):
                try:
                    out = subprocess.check_output(
                        [
                            vswhere,
                            "-latest",
                            "-products", "*",
                            "-requires", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
                            "-property", "installationPath",
                        ],
                        text=True,
                        stderr=subprocess.DEVNULL,
                        timeout=3,
                    ).strip()
                    if out and os.path.isdir(out):
                        vs_install_dirs.append(out)
                except Exception:
                    pass

        msvc_dirs = []
        for vs_dir in vs_install_dirs:
            msvc_dirs.extend(glob.glob(os.path.join(vs_dir, "VC", "Tools", "MSVC", "*")))

        if not msvc_dirs:
            for root in prog_roots:
                for ver in ("2026", "18", "2022", "17"):
                    pattern = os.path.join(
                        root, "Microsoft Visual Studio", ver, "*", "VC", "Tools", "MSVC", "*"
                    )
                    msvc_dirs.extend(glob.glob(pattern))

        if msvc_dirs:
            latest_msvc = sorted(msvc_dirs)[-1]
            msvc_bin = os.path.join(latest_msvc, "bin", "Hostx64", "x64")
            msvc_inc = os.path.join(latest_msvc, "include")
            msvc_lib = os.path.join(latest_msvc, "lib", "x64")
            if os.path.isdir(msvc_bin):
                bin_dirs.append(msvc_bin)
            if os.path.isdir(msvc_inc):
                include_dirs.append(msvc_inc)
            if os.path.isdir(msvc_lib):
                lib_dirs.append(msvc_lib)

        for root in prog_roots:
            kits_inc = os.path.join(root, "Windows Kits", "10", "Include")
            kits_lib = os.path.join(root, "Windows Kits", "10", "Lib")
            if os.path.isdir(kits_inc):
                sdk_vers = sorted(glob.glob(os.path.join(kits_inc, "10.*")))
                if sdk_vers:
                    latest_sdk = sdk_vers[-1]
                    latest_sdk_ver = os.path.basename(latest_sdk)
                    for sub in ("ucrt", "shared", "um"):
                        sub_dir = os.path.join(latest_sdk, sub)
                        if os.path.isdir(sub_dir):
                            include_dirs.append(sub_dir)
                    for sub_lib in ("ucrt", "um"):
                        sub_lib_dir = os.path.join(kits_lib, latest_sdk_ver, sub_lib, "x64")
                        if os.path.isdir(sub_lib_dir):
                            lib_dirs.append(sub_lib_dir)
                break

    # C. Locate ROCm SDK Devel & Core headers inside site-packages
    site_pkgs = os.path.join(sys.prefix, "Lib", "site-packages")
    for rocm_pkg in ("_rocm_sdk_devel", "_rocm_sdk_core"):
        rocm_pkg_dir = os.path.join(site_pkgs, rocm_pkg)
        if os.path.isdir(rocm_pkg_dir):
            os.environ.setdefault("ROCM_PATH", rocm_pkg_dir)
            os.environ.setdefault("HIP_PATH", rocm_pkg_dir)
            rocm_inc = os.path.join(rocm_pkg_dir, "include")
            if os.path.isdir(rocm_inc):
                include_dirs.append(rocm_inc)

    _prepend_env_path("PATH", bin_dirs, use_forward_slash=False)
    _prepend_env_path("INCLUDE", include_dirs, use_forward_slash=False)
    _prepend_env_path("LIB", lib_dirs, use_forward_slash=False)
    _prepend_env_path("CPATH", include_dirs, use_forward_slash=True)
    _prepend_env_path("CPLUS_INCLUDE_PATH", include_dirs, use_forward_slash=True)


_discover_and_inject_toolchains()


# 2. Post-Import ROCm PyTorch Patching
def _apply_torch_patches(torch_module) -> None:
    if getattr(torch_module, "_winrocm_patched", False):
        return
    if not getattr(torch_module.version, "hip", None):
        return

    torch_module._winrocm_patched = True

    # Defense-in-depth: Remove CUDA arch validation queued calls intended only for NVIDIA GPUs (# on ROCm we don't want this check)
    if hasattr(torch_module, "cuda") and hasattr(torch_module.cuda, "_queued_calls"):
        torch_module.cuda._queued_calls = [
            (fn, tb)
            for fn, tb in torch_module.cuda._queued_calls
            if getattr(fn, "__name__", "") not in ("_check_capability", "_check_cubins")
        ]
    if hasattr(torch_module, "cuda") and hasattr(torch_module.cuda, "_extract_arch_version"):
        def _safe_extract_arch(arch_string: str) -> int:
            try:
                if "_" in arch_string:
                    base = arch_string.split("_", maxsplit=2)[1]
                    return int(base.removesuffix("a").removesuffix("f"))
            except Exception:
                pass
            return 80
        torch_module.cuda._extract_arch_version = _safe_extract_arch

    # Spoof CUDA version for libraries with strict NVIDIA checks
    if torch_module.version.cuda is None:
        torch_module.version.cuda = "12.6"

    # Global MIOpen opt-out toggle
    if os.environ.get("ROCM_DISABLE_MIOPEN", "").strip() == "1":
        torch_module.backends.cudnn.enabled = False

    import torch.nn.functional as F

    # Patch 1: Safe L2 Normalize (prevents Windows HIP reduction wave-size crash)
    _orig_normalize = F.normalize

    def _safe_normalize(input, p=2.0, dim=1, eps=1e-12, out=None):
        if input.is_cuda and out is None and p == 2.0:
            denom = torch_module.sqrt(
                torch_module.sum(input.float() ** 2, dim=dim, keepdim=True)
            ).clamp(min=eps)
            return (input.float() / denom).to(input.dtype)
        return _orig_normalize(input, p=p, dim=dim, eps=eps, out=out)

    F.normalize = _safe_normalize

    # Patch 2: Resilient BatchNorm with automatic ATen fallback on HIPRTC failure (#9206)
    _orig_batch_norm = F.batch_norm
    _bn_fallback_warned = False

    def _safe_batch_norm(
        input,
        running_mean,
        running_var,
        weight=None,
        bias=None,
        training=False,
        momentum=0.1,
        eps=1e-5,
    ):
        nonlocal _bn_fallback_warned
        if not input.is_cuda or not torch_module.backends.cudnn.enabled:
            return _orig_batch_norm(
                input, running_mean, running_var, weight, bias, training, momentum, eps
            )
        try:
            return _orig_batch_norm(
                input, running_mean, running_var, weight, bias, training, momentum, eps
            )
        except RuntimeError as exc:
            if "miopenStatus" in str(exc) or "HIPRTC" in str(exc):
                if not _bn_fallback_warned:
                    warnings.warn(
                        "MIOpen JIT failed on BatchNorm (ROCm/TheRock #9206). "
                        "Falling back to native ATen BatchNorm. Install VS C++ Build Tools "
                        "and run 'rocm-sdk init' to enable MIOpen JIT.",
                        RuntimeWarning,
                        stacklevel=2,
                    )
                    _bn_fallback_warned = True
                with torch_module.backends.cudnn.flags(enabled=False):
                    return _orig_batch_norm(
                        input, running_mean, running_var, weight, bias, training, momentum, eps
                    )
            raise

    F.batch_norm = _safe_batch_norm

    # Patch 3: Resilient torch.compile with automatic eager fallback on missing MSVC compiler
    _orig_compile = getattr(torch_module, "compile", None)
    _compile_fallback_warned = False

    if callable(_orig_compile):
        def _safe_compile(*args, **kwargs):
            nonlocal _compile_fallback_warned
            compiled_fn = _orig_compile(*args, **kwargs)

            def _wrapped_callable(*c_args, **c_kwargs):
                nonlocal _compile_fallback_warned
                try:
                    return compiled_fn(*c_args, **c_kwargs)
                except Exception as exc:
                    exc_name = type(exc).__name__
                    exc_str = str(exc)
                    if (
                        "BackendCompilerFailed" in exc_name
                        or "CppCompileError" in exc_name
                        or ("Compiler" in exc_str and "is not found" in exc_str)
                        or ("cl" in exc_str and "not recognized" in exc_str)
                    ):
                        if not _compile_fallback_warned:
                            warnings.warn(
                                "torch.compile failed because MSVC C++ Build Tools (cl.exe) were not found. "
                                "Falling back to standard eager execution. To enable hardware torch.compile "
                                "acceleration, run 'setup.bat' and select Portable MSVC (Option 1).",
                                RuntimeWarning,
                                stacklevel=2,
                            )
                            _compile_fallback_warned = True
                        orig_fn = args[0] if args else kwargs.get("model")
                        if callable(orig_fn):
                            return orig_fn(*c_args, **c_kwargs)
                    raise

            return _wrapped_callable

        torch_module.compile = _safe_compile


# 3. Single-Execution MetaPath Loader Hook (Avoids double module execution)
class _TorchPostImportHook(importlib.abc.MetaPathFinder):
    def find_spec(self, fullname, path, target=None):
        if fullname != "torch":
            return None

        # Remove hook immediately so PathFinder resolves torch normally once
        if self in sys.meta_path:
            sys.meta_path.remove(self)

        spec = importlib.machinery.PathFinder.find_spec(fullname, path, target)
        if spec is not None and spec.loader is not None:
            orig_exec_module = spec.loader.exec_module

            def _wrapped_exec_module(module):
                orig_exec_module(module)
                _apply_torch_patches(module)

            spec.loader.exec_module = _wrapped_exec_module
        return spec


if "torch" in sys.modules:
    _apply_torch_patches(sys.modules["torch"])
else:
    sys.meta_path.insert(0, _TorchPostImportHook())
