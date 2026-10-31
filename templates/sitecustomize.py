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
    prog_roots = []
    for var in ("ProgramFiles(x86)", "ProgramFiles", "ProgramW6432"):
        val = os.environ.get(var)
        if val and val not in prog_roots:
            prog_roots.append(val)

    # A. Locate MSVC (VS 2026 / v18 and VS 2022 / v17) via vswhere or filesystem glob
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

    include_dirs = []
    bin_dirs = []

    if msvc_dirs:
        latest_msvc = sorted(msvc_dirs)[-1]
        msvc_bin = os.path.join(latest_msvc, "bin", "Hostx64", "x64")
        msvc_inc = os.path.join(latest_msvc, "include")
        if os.path.isdir(msvc_bin):
            bin_dirs.append(msvc_bin)
        if os.path.isdir(msvc_inc):
            include_dirs.append(msvc_inc)

    # B. Locate Windows 10/11 SDK Universal CRT (ucrt & shared) headers
    for root in prog_roots:
        kits_inc = os.path.join(root, "Windows Kits", "10", "Include")
        if os.path.isdir(kits_inc):
            sdk_vers = sorted(glob.glob(os.path.join(kits_inc, "10.*")))
            if sdk_vers:
                latest_sdk = sdk_vers[-1]
                for sub in ("ucrt", "shared", "um"):
                    sub_dir = os.path.join(latest_sdk, sub)
                    if os.path.isdir(sub_dir):
                        include_dirs.append(sub_dir)
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
