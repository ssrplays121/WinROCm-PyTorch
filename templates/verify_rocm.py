"""
Comprehensive ROCm PyTorch Verification Script
Tests Toolchain Paths, GEMM, Conv2d Latency, BatchNorm2d (>32x32), F.normalize, and Triton JIT.
"""
import os
import sys
import time
import torch
import torch.nn as nn
import torch.nn.functional as F

print("\n" + "=" * 65)
print(f"Torch Version        : {torch.__version__}")
print(f"HIP Version          : {getattr(torch.version, 'hip', None)}")
print(f"CUDA Spoof Version   : {getattr(torch.version, 'cuda', None)}")
print(f"ROCm/CUDA Available  : {torch.cuda.is_available()}")
print(f"ROCM_PATH            : {os.environ.get('ROCM_PATH', 'Not Set')}")
print(f"MSVC/UCRT in CPATH   : {'MSVC' in os.environ.get('CPATH', '') and 'ucrt' in os.environ.get('CPATH', '').lower()}")
print(f"hipBLASLt Preferred  : {os.environ.get('TORCH_BLAS_PREFER_HIPBLASLT') == '1'}")
print(f"MIOpen Enabled       : {torch.backends.cudnn.enabled}")

success = True

if not torch.cuda.is_available():
    print("ERROR: ROCm GPU not detected by PyTorch.")
    sys.exit(1)

print(f"Device Name          : {torch.cuda.get_device_name(0)}")

# 1. GPU Matmul (GEMM)
try:
    x = torch.randn(2048, 2048, device="cuda", dtype=torch.float16)
    y = x @ x
    torch.cuda.synchronize()
    print(f"[PASS] GPU Matmul    : {tuple(y.shape)}")
except Exception as e:
    print(f"[FAIL] GPU Matmul    : {e}")
    success = False

# 2. GPU Conv2d + Naive Fallback Latency Check (#3077)
try:
    conv = nn.Conv2d(64, 128, kernel_size=3, padding=1).cuda().half()
    cx = torch.randn(8, 64, 64, 64, device="cuda", dtype=torch.float16)
    _ = conv(cx)
    torch.cuda.synchronize()
    t0 = time.perf_counter()
    for _ in range(10):
        cy = conv(cx)
    torch.cuda.synchronize()
    elapsed_ms = (time.perf_counter() - t0) * 100
    status = "OK" if elapsed_ms < 50.0 else f"SLOW ({elapsed_ms:.1f} ms/iter - possible workspace=0 fallback)"
    print(f"[PASS] GPU Conv2d    : {tuple(cy.shape)} ({status})")
except Exception as e:
    print(f"[FAIL] GPU Conv2d    : {e}")
    success = False

# 3. BatchNorm2d (>32x32 Spatial Tensor - #9206)
try:
    bn = nn.BatchNorm2d(64).cuda()
    bx = torch.randn(2, 64, 64, 64, device="cuda")
    by = bn(bx)
    torch.cuda.synchronize()
    print(f"[PASS] BatchNorm2d   : {tuple(by.shape)}")
except Exception as e:
    print(f"[FAIL] BatchNorm2d   : {e}")
    success = False

# 4. Safe F.normalize (Wave-Size Reduction Guard + Autograd Check)
try:
    nx = torch.randn(4, 128, 32, device="cuda", requires_grad=True)
    ny = F.normalize(nx, p=2.0, dim=1)
    ny.sum().backward()
    torch.cuda.synchronize()
    print(f"[PASS] F.normalize   : {tuple(ny.shape)} (Autograd OK)")
except Exception as e:
    print(f"[FAIL] F.normalize   : {e}")
    success = False

# 5. Optional Triton Check
try:
    import triton
    import triton.language as tl

    @triton.jit
    def _add_kernel(x_ptr, y_ptr, out_ptr, n, BLOCK: tl.constexpr):
        pid = tl.program_id(0)
        offs = pid * BLOCK + tl.arange(0, BLOCK)
        mask = offs < n
        tl.store(out_ptr + offs, tl.load(x_ptr + offs, mask=mask) + tl.load(y_ptr + offs, mask=mask), mask=mask)

    tx = torch.ones(1024, device="cuda")
    tout = torch.empty_like(tx)
    _add_kernel[(1,)](tx, tx, tout, 1024, BLOCK=1024)
    torch.cuda.synchronize()
    print(f"[PASS] Triton JIT    : v{triton.__version__} (Kernel execution OK)")
except ImportError:
    print("[INFO] Triton Support: Not installed (run setup with -WithTriton to enable)")
except Exception as e:
    print(f"[WARN] Triton JIT    : Installed but kernel compile failed ({e})")

print("=" * 65 + "\n")
if not success:
    sys.exit(1)
