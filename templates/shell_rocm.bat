@echo off
call "%~dp0env_rocm.bat"
cd /d "%ROCM_ROOT%"
echo =========================================================================
echo WinROCm Portable Shell: ROCm PyTorch Environment Active
echo Install Directory: %ROCM_ROOT%
echo Commands 'python', 'pip', and 'torchrun' now use this isolated container.
echo =========================================================================
cmd /k
