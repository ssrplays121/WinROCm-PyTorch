@{
    DefaultRelease    = '7.2.1'
    PythonVersion     = '3.12.10'
    PythonZipUrl      = 'https://www.python.org/ftp/python/3.12.10/python-3.12.10-embed-amd64.zip'
    PythonSha256      = '4ACBED6DD1C744B0376E3B1CF57CE906F9DC9E95E68824584C8099A63025A3C3'
    PythonDevMsiUrl   = 'https://www.python.org/ftp/python/3.12.10/amd64/dev.msi'
    PythonDevMsiSha256= '77B151B8D36F8BB4CDE20EE6F0FF0681A2F88B2072CEAC6ABAA8E173F5A1EB78'
    GetPipUrl         = 'https://bootstrap.pypa.io/get-pip.py'
    GetPipSha256      = '356E0D0DE21CDC348C3394084D90939B85E4246C4D14C76AEE6CA4F46646EA98'
    PipVersion        = '26.3'
    SetuptoolsVersion = '84.2.1'
    WheelVersion      = '0.48.0'

    # Multi-Arch Unified Stream Repositories
    StreamUrls = @{
        'stable'  = 'https://stable.repo.amd.com/rocm/whl-next/'
        'nightly' = 'https://nightly.repo.amd.com/rocm/whl-next/'
    }

    Releases = @{
        '7.2' = @{
            BaseUrl   = 'https://repo.radeon.com/rocm/windows/rocm-rel-7.2'
            SdkFiles  = @(
                'rocm_sdk_core-7.2.0.dev0-py3-none-win_amd64.whl'
                'rocm_sdk_devel-7.2.0.dev0-py3-none-win_amd64.whl'
                'rocm_sdk_libraries_custom-7.2.0.dev0-py3-none-win_amd64.whl'
                'rocm-7.2.0.dev0.tar.gz'
            )
            Torch     = 'torch-2.9.1%2Brocmsdk20260116-cp312-cp312-win_amd64.whl'
            Vision    = 'torchvision-0.24.1%2Brocmsdk20260116-cp312-cp312-win_amd64.whl'
            Audio     = 'torchaudio-2.9.1%2Brocmsdk20260116-cp312-cp312-win_amd64.whl'
            Triton    = '3.5.1.post24'
        }
        '7.2.1' = @{
            BaseUrl   = 'https://repo.radeon.com/rocm/windows/rocm-rel-7.2.1'
            SdkFiles  = @(
                'rocm_sdk_core-7.2.1-py3-none-win_amd64.whl'
                'rocm_sdk_devel-7.2.1-py3-none-win_amd64.whl'
                'rocm_sdk_libraries_custom-7.2.1-py3-none-win_amd64.whl'
                'rocm-7.2.1.tar.gz'
            )
            Torch     = 'torch-2.9.1%2Brocm7.2.1-cp312-cp312-win_amd64.whl'
            Vision    = 'torchvision-0.24.1%2Brocm7.2.1-cp312-cp312-win_amd64.whl'
            Audio     = 'torchaudio-2.9.1%2Brocm7.2.1-cp312-cp312-win_amd64.whl'
            Triton    = '3.5.1.post24'
        }
    }

    # Patterns matched against Win32_VideoController Name. Source: AMD release notes
    SupportedGpuPatterns = @(
        'Radeon RX 9070', 'Radeon RX 9060 XT', 'Radeon AI PRO R9700',
        'Radeon RX 7900 XTX', 'Radeon PRO W7900',
        'Ryzen AI Max', 'Ryzen AI 9'
    )
}

