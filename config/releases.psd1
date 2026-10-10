@{
    DefaultRelease    = '7.2'
    PythonVersion     = '3.12.8'
    PythonZipUrl      = 'https://www.python.org/ftp/python/3.12.8/python-3.12.8-embed-amd64.zip'
    PythonSha256      = '8D3F33BE9EB810F23C102F08475AF2854E50484B8E4E06275E937BE61CE3D2FB'
    GetPipUrl         = 'https://bootstrap.pypa.io/get-pip.py'
    GetPipSha256      = 'FB24E693BAB954209A063D90953621412CCAD4A500905A726286E038F508DDF6'
    PipVersion        = '26.2.1'
    SetuptoolsVersion = '84.0.0'
    WheelVersion      = '0.48.0'

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
        }
    }

    # Patterns matched against Win32_VideoController Name. Source: AMD release notes
    SupportedGpuPatterns = @(
        'Radeon RX 9070', 'Radeon RX 9060 XT', 'Radeon AI PRO R9700',
        'Radeon RX 7900 XTX', 'Radeon PRO W7900',
        'Ryzen AI Max', 'Ryzen AI 9'
    )
}

