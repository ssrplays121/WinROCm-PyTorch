import sys
import torch

print()
print("=" * 50)
print("Torch Version       :", torch.__version__)
print("Torch Location      :", torch.__file__)
print("HIP Version         :", getattr(torch.version, "hip", None))
print("ROCm/CUDA Available :", torch.cuda.is_available())
print("Device Count        :", torch.cuda.device_count())

success = True

if torch.cuda.is_available():
    print("Device Name         :", torch.cuda.get_device_name(0))
    try:
        x = torch.randn(1024, 1024, device="cuda")
        y = x @ x
        torch.cuda.synchronize()
        print("GPU matmul          : OK", tuple(y.shape))
    except Exception as e:
        print("GPU matmul          : FAILED -", e)
        success = False
else:
    print("Device Name         : None")
    print("WARNING: ROCm/CUDA is not available to PyTorch.")
    success = False

try:
    import torchvision
    print("Torchvision Version :", torchvision.__version__)
except ImportError:
    pass

try:
    import torchaudio
    print("Torchaudio Version  :", torchaudio.__version__)
except ImportError:
    pass

print("=" * 50)
print()

if not success:
    sys.exit(1)

