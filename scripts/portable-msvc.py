#!/usr/bin/env python3
"""
Portable MSVC & Windows SDK Downloader and Unpacker
Extracts standalone, minimal x64 MSVC compiler toolset and Windows SDK
directly from Microsoft official release manifests without Visual Studio IDE bloat.
Based on Mārtiņš Možeiko's public domain implementation.
"""

import argparse
import hashlib
import io
import json
import os
import shutil
import subprocess
import sys
import zipfile
import urllib.error
import urllib.request
from pathlib import Path

DEFAULT_HOST = "x64"
ALL_HOSTS = "x64 x86 arm64".split()

DEFAULT_TARGET = "x64"
ALL_TARGETS = "x64 x86 arm arm64".split()

DEFAULT_VERSION = "latest"
ALL_VERSIONS = "2019 2022 2026 latest".split()

MANIFEST_URLS = {
    "latest": [
        "https://aka.ms/vs/stable/channel",
        "https://aka.ms/vs/insiders/channel",
    ],
    "2026": [
        "https://aka.ms/vs/18/stable/channel",
        "https://aka.ms/vs/18/insiders/channel",
    ],
    "2022": [
        "https://aka.ms/vs/17/release/channel",
        "https://aka.ms/vs/17/pre/channel",
    ],
    "2019": [
        "https://aka.ms/vs/16/release/channel",
        "https://aka.ms/vs/16/pre/channel",
    ],
}

ssl_context = None


def download(url: str) -> bytes:
    with urllib.request.urlopen(url, context=ssl_context) as res:
        return res.read()


total_download = 0


def download_progress(url: str, check: str, filename: str, downloads_dir: Path) -> bytes:
    fpath = downloads_dir / filename
    if fpath.exists():
        data = fpath.read_bytes()
        if hashlib.sha256(data).hexdigest() == check.lower():
            print(f"\r  [Cached] {filename} ... OK")
            return data

    global total_download
    with fpath.open("wb") as f:
        data = io.BytesIO()
        with urllib.request.urlopen(url.replace(" ", "%20"), context=ssl_context) as res:
            total = int(res.headers.get("Content-Length", 0))
            size = 0
            while True:
                block = res.read(1 << 20)
                if not block:
                    break
                f.write(block)
                data.write(block)
                size += len(block)
                if total > 0:
                    perc = size * 100 // total
                    print(f"\r  {filename} ... {perc}% ({size >> 20}/{total >> 20} MB)", end="", flush=True)
                else:
                    print(f"\r  {filename} ... ({size >> 20} MB)", end="", flush=True)
        print()
        data_bytes = data.getvalue()
        digest = hashlib.sha256(data_bytes).hexdigest()
        if check.lower() != digest:
            sys.exit(f"Hash mismatch for {filename} (expected {check}, got {digest})")
        total_download += len(data_bytes)
        return data_bytes


def get_msi_cabs(msi_bytes: bytes):
    index = 0
    while True:
        index = msi_bytes.find(b".cab", index + 4)
        if index < 0:
            return
        yield msi_bytes[index - 32 : index + 4].decode("ascii")


def first(items, cond=lambda x: True):
    return next((item for item in items if cond(item)), None)


def main():
    global ssl_context

    ap = argparse.ArgumentParser(description="Download standalone MSVC toolchain & Windows SDK")
    ap.add_argument("--show-versions", action="store_true", help="Show available MSVC and Windows SDK versions")
    ap.add_argument("--accept-license", action="store_true", help="Automatically accept Microsoft Visual Studio license")
    ap.add_argument("--msvc-version", help="Get specific MSVC version")
    ap.add_argument("--sdk-version", help="Get specific Windows SDK version")
    ap.add_argument("--vs", default=DEFAULT_VERSION, help="Visual Studio channel to query", choices=ALL_VERSIONS)
    ap.add_argument("--insiders", action="store_true", help="Use insiders channel")
    ap.add_argument("--preview", action="store_true", help="Allow preview MSVC versions")
    ap.add_argument("--target", default=DEFAULT_TARGET, help=f"Target architectures ({','.join(ALL_TARGETS)})")
    ap.add_argument("--host", default=DEFAULT_HOST, help="Host architecture", choices=ALL_HOSTS)
    ap.add_argument("--output", default="msvc", help="Destination folder for portable MSVC installation")
    ap.add_argument("--downloads", default=None, help="Directory for temporary download cache")
    args = ap.parse_args()

    host = args.host
    targets = args.target.split(",")
    for target in targets:
        if target not in ALL_TARGETS:
            sys.exit(f"Unknown {target} target architecture!")

    output_dir = Path(args.output).resolve()
    downloads_dir = Path(args.downloads).resolve() if args.downloads else (output_dir / ".downloads")

    manifest_url = MANIFEST_URLS[args.vs][1 if args.insiders else 0]

    try:
        manifest = json.loads(download(manifest_url))
    except urllib.error.URLError as err:
        import ssl

        if isinstance(err.args[0], ssl.SSLCertVerificationError):
            try:
                import certifi

                ssl_context = ssl.create_default_context(cafile=certifi.where())
                manifest = json.loads(download(manifest_url))
            except ModuleNotFoundError:
                sys.exit("ERROR: SSL certificate verification failed. Install 'certifi' or update root certificates.")
        else:
            raise

    item_name = (
        "Microsoft.VisualStudio.Manifests.VisualStudioPreview"
        if args.insiders
        else "Microsoft.VisualStudio.Manifests.VisualStudio"
    )
    vs_item = first(manifest["channelItems"], lambda x: x["id"] == item_name)
    payload_url = vs_item["payloads"][0]["url"]
    vsmanifest = json.loads(download(payload_url))

    packages = {}
    for p in vsmanifest["packages"]:
        packages.setdefault(p["id"].lower(), []).append(p)

    msvc = {}
    sdk = {}

    for pid, p in packages.items():
        if (
            pid.startswith("microsoft.vc.")
            and pid.endswith(".tools.hostx64.targetx64.base")
            and "premium" not in pid.lower()
        ):
            pver = ".".join(pid.split(".")[2:4])
            if pver[0].isnumeric():
                msvc[pver] = pid
        elif pid.startswith("microsoft.visualstudio.component.windows10sdk.") or pid.startswith(
            "microsoft.visualstudio.component.windows11sdk."
        ):
            pver = pid.split(".")[-1]
            if pver.isnumeric():
                sdk[pver] = pid

    if not args.preview:
        p = packages.get("microsoft.vc.preview.tools.hostx64.targetx64")
        if p:
            pver = ".".join(p[0]["version"].split(".")[:2])
            msvc.pop(pver, None)

    if args.show_versions:
        print("MSVC versions:", " ".join(sorted(msvc.keys())))
        print("Windows SDK versions:", " ".join(sorted(sdk.keys())))
        return 0

    msvc_ver = args.msvc_version or max(sorted(msvc.keys()))
    sdk_ver = args.sdk_version or max(sorted(sdk.keys()))

    if msvc_ver in msvc:
        msvc_pid = msvc[msvc_ver]
        msvc_ver_clean = msvc_pid.removeprefix("microsoft.vc.").removesuffix(".tools.hostx64.targetx64.base")
    else:
        sys.exit(f"Unknown MSVC version: {args.msvc_version}")

    if sdk_ver in sdk:
        sdk_pid = sdk[sdk_ver]
    else:
        sys.exit(f"Unknown Windows SDK version: {args.sdk_version}")

    tools = first(manifest["channelItems"], lambda x: x["id"] == "Microsoft.VisualStudio.Product.BuildTools")
    resource = first(tools["localizedResources"], lambda x: x["language"].lower() == "en-us")
    license_url = resource.get("license", "https://visualstudio.microsoft.com/license-terms/")

    if not args.accept_license:
        print(f"Visual Studio Build Tools License: {license_url}")
        accept = input("Do you accept the license terms? [y/N]: ")
        if not accept or accept.strip().lower() != "y":
            print("Installation aborted (license not accepted).")
            return 1

    print(f"Installing Portable MSVC v{msvc_ver_clean} and Windows SDK v{sdk_ver} into: {output_dir}")
    output_dir.mkdir(parents=True, exist_ok=True)
    downloads_dir.mkdir(parents=True, exist_ok=True)

    msvc_packages = [
        "microsoft.visualcpp.dia.sdk",
        f"microsoft.vc.{msvc_ver_clean}.crt.headers.base",
        f"microsoft.vc.{msvc_ver_clean}.crt.source.base",
        f"microsoft.vc.{msvc_ver_clean}.asan.headers.base",
        f"microsoft.vc.{msvc_ver_clean}.pgo.headers.base",
    ]

    for target in targets:
        msvc_packages += [
            f"microsoft.vc.{msvc_ver_clean}.tools.host{host}.target{target}.base",
            f"microsoft.vc.{msvc_ver_clean}.tools.host{host}.target{target}.res.base",
            f"microsoft.vc.{msvc_ver_clean}.crt.{target}.desktop.base",
            f"microsoft.vc.{msvc_ver_clean}.crt.{target}.store.base",
            f"microsoft.vc.{msvc_ver_clean}.premium.tools.host{host}.target{target}.base",
            f"microsoft.vc.{msvc_ver_clean}.pgo.{target}.base",
        ]
        if target in ["x86", "x64"]:
            msvc_packages += [f"microsoft.vc.{msvc_ver_clean}.asan.{target}.base"]

        redist_suffix = ".onecore.desktop" if target == "arm" else ""
        redist_pkg = f"microsoft.vc.{msvc_ver_clean}.crt.redist.{target}{redist_suffix}.base"
        if redist_pkg not in packages:
            redist_name = f"microsoft.visualcpp.crt.redist.{target}{redist_suffix}"
            if redist_name in packages:
                redist = first(packages[redist_name])
                redist_pkg = first(redist["dependencies"], lambda dep: dep.endswith(".base")).lower()
        msvc_packages += [redist_pkg]

    print("\n[1/3] Downloading & extracting MSVC compiler & CRT libraries...")
    for pkg in sorted(msvc_packages):
        if pkg not in packages:
            continue
        p = first(packages[pkg], lambda p: p.get("language") in (None, "en-US", "en-us"))
        if not p or "payloads" not in p:
            continue
        for payload in p["payloads"]:
            filename = payload["fileName"]
            download_progress(payload["url"], payload["sha256"], filename, downloads_dir)
            archive_path = downloads_dir / filename
            with zipfile.ZipFile(archive_path) as z:
                for name in z.namelist():
                    if name.startswith("Contents/"):
                        out = output_dir / Path(name).relative_to("Contents")
                        out.parent.mkdir(parents=True, exist_ok=True)
                        out.write_bytes(z.read(name))

    print("\n[2/3] Downloading & extracting Windows SDK (UCRT & UM headers/libs)...")
    sdk_packages = [
        "Windows SDK for Windows Store Apps Tools-x86_en-us.msi",
        "Windows SDK for Windows Store Apps Headers-x86_en-us.msi",
        "Windows SDK for Windows Store Apps Headers OnecoreUap-x86_en-us.msi",
        "Windows SDK for Windows Store Apps Libs-x86_en-us.msi",
        "Universal CRT Headers Libraries and Sources-x86_en-us.msi",
    ]

    for target in ALL_TARGETS:
        sdk_packages += [
            f"Windows SDK Desktop Headers {target}-x86_en-us.msi",
            f"Windows SDK OnecoreUap Headers {target}-x86_en-us.msi",
        ]

    for target in targets:
        sdk_packages += [f"Windows SDK Desktop Libs {target}-x86_en-us.msi"]

    sdk_pkg = packages[sdk_pid][0]
    sdk_pkg = packages[first(sdk_pkg["dependencies"]).lower()][0]

    msi_files = []
    cab_files = []

    for pkg in sorted(sdk_packages):
        payload = first(
            sdk_pkg["payloads"],
            lambda p: p["fileName"].replace("\\", "/") == f"Installers/{pkg}",
        )
        if payload is None:
            continue
        msi_files.append(downloads_dir / pkg)
        data = download_progress(payload["url"], payload["sha256"], pkg, downloads_dir)
        cab_files += list(get_msi_cabs(data))

    cab_files = sorted(set(cab_files))
    for pkg in cab_files:
        payload = first(
            sdk_pkg["payloads"],
            lambda p: p["fileName"].replace("\\", "/") == f"Installers/{pkg}",
        )
        if payload is not None:
            download_progress(payload["url"], payload["sha256"], pkg, downloads_dir)

    print("\nUnpacking Windows SDK MSI packages...")
    for m in msi_files:
        if m.exists():
            target_arg = f'TARGETDIR={str(output_dir.resolve()).rstrip(os.sep) + os.sep}'
            subprocess.check_call(
                ["msiexec.exe", "/a", str(m.resolve()), "/quiet", "/qn", target_arg],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            # Remove msi copied to root of output_dir if present
            (output_dir / m.name).unlink(missing_ok=True)

    print("\n[3/3] Finalizing portable directory structure & configuration...")
    msvcv_item = first((output_dir / "VC/Tools/MSVC").glob("*"))
    if not msvcv_item:
        sys.exit("ERROR: MSVC toolchain directory was not extracted properly.")
    msvcv = msvcv_item.name

    sdkv_item = first((output_dir / "Windows Kits/10/bin").glob("*"))
    if not sdkv_item:
        # Check in Include or Lib if bin has different structure
        sdkv_item = first((output_dir / "Windows Kits/10/Include").glob("10.*"))
    if not sdkv_item:
        sys.exit("ERROR: Windows SDK directory was not extracted properly.")
    sdkv = sdkv_item.name

    # Place debug CRT non-redist files into MSVC bin if present
    redist = output_dir / "VC/Redist"
    if redist.exists():
        redistv_item = first((redist / "MSVC").glob("*"))
        if redistv_item:
            src = redist / "MSVC" / redistv_item.name / "debug_nonredist"
            for target in targets:
                target_src = src / target
                if target_src.exists():
                    for f in target_src.glob("**/*.dll"):
                        dst = output_dir / "VC/Tools/MSVC" / msvcv / f"bin/Host{host}" / target
                        dst.mkdir(parents=True, exist_ok=True)
                        shutil.copyfile(f, dst / f.name)
        shutil.rmtree(redist, ignore_errors=True)

    # Copy msdia140.dll into MSVC bin folder
    msdia140dll = {
        "x86": "msdia140.dll",
        "x64": "amd64/msdia140.dll",
        "arm": "arm/msdia140.dll",
        "arm64": "arm64/msdia140.dll",
    }
    dia_bin = output_dir / "DIA%20SDK/bin"
    if dia_bin.exists():
        src_dia = dia_bin / msdia140dll.get(host, "amd64/msdia140.dll")
        if src_dia.exists():
            dst_dia = output_dir / "VC/Tools/MSVC" / msvcv / f"bin/Host{host}"
            for target in targets:
                target_dia = dst_dia / target
                target_dia.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(src_dia, target_dia / src_dia.name)
        shutil.rmtree(output_dir / "DIA%20SDK", ignore_errors=True)

    # Prune unneeded architectures and bloat
    shutil.rmtree(output_dir / "Common7", ignore_errors=True)
    shutil.rmtree(output_dir / "VC/Tools/MSVC" / msvcv / "Auxiliary", ignore_errors=True)
    for target in targets:
        for f in ["store", "uwp", "enclave", "onecore"]:
            shutil.rmtree(output_dir / "VC/Tools/MSVC" / msvcv / "lib" / target / f, ignore_errors=True)
        shutil.rmtree(output_dir / "VC/Tools/MSVC" / msvcv / f"bin/Host{host}" / target / "onecore", ignore_errors=True)

    for f in ["Catalogs", "DesignTime", f"bin/{sdkv}/chpe", f"Lib/{sdkv}/ucrt_enclave"]:
        shutil.rmtree(output_dir / "Windows Kits/10" / f, ignore_errors=True)

    for arch in ["x86", "x64", "arm", "arm64"]:
        if arch not in targets:
            shutil.rmtree(output_dir / "Windows Kits/10/Lib" / sdkv / "ucrt" / arch, ignore_errors=True)
            shutil.rmtree(output_dir / "Windows Kits/10/Lib" / sdkv / "um" / arch, ignore_errors=True)
        if arch != host:
            shutil.rmtree(output_dir / "VC/Tools/MSVC" / msvcv / f"bin/Host{arch}", ignore_errors=True)
            shutil.rmtree(output_dir / "Windows Kits/10/bin" / sdkv / arch, ignore_errors=True)

    # Remove telemetry executable vctip.exe
    for target in targets:
        (output_dir / "VC/Tools/MSVC" / msvcv / f"bin/Host{host}/{target}/vctip.exe").unlink(missing_ok=True)

    # Dummy vcvarsall.bat / vcvars64.bat for nvcc/setuptools compatibility
    aux_build = output_dir / "VC/Auxiliary/Build"
    aux_build.mkdir(parents=True, exist_ok=True)
    (aux_build / "vcvarsall.bat").write_text("@rem Portable MSVC compatibility stub\n")
    (aux_build / "vcvars64.bat").write_text("@rem Portable MSVC compatibility stub\n")

    # Generate setup_x64.bat in portable root
    setup_bat = f"""@echo off
set VSCMD_ARG_HOST_ARCH={host}
set VSCMD_ARG_TGT_ARCH=x64
set VCToolsVersion={msvcv}
set WindowsSDKVersion={sdkv}\\
set VCToolsInstallDir=%~dp0VC\\Tools\\MSVC\\{msvcv}\\
set WindowsSdkBinPath=%~dp0Windows Kits\\10\\bin\\
set PATH=%~dp0VC\\Tools\\MSVC\\{msvcv}\\bin\\Host{host}\\x64;%~dp0Windows Kits\\10\\bin\\{sdkv}\\{host};%PATH%
set INCLUDE=%~dp0VC\\Tools\\MSVC\\{msvcv}\\include;%~dp0Windows Kits\\10\\Include\\{sdkv}\\ucrt;%~dp0Windows Kits\\10\\Include\\{sdkv}\\shared;%~dp0Windows Kits\\10\\Include\\{sdkv}\\um
set LIB=%~dp0VC\\Tools\\MSVC\\{msvcv}\\lib\\x64;%~dp0Windows Kits\\10\\Lib\\{sdkv}\\ucrt\\x64;%~dp0Windows Kits\\10\\Lib\\{sdkv}\\um\\x64
set DISTUTILS_USE_SDK=1
set MSSdk=1
"""
    (output_dir / "setup_x64.bat").write_text(setup_bat)

    # Clean up temporary downloads
    if not args.downloads:
        shutil.rmtree(downloads_dir, ignore_errors=True)

    print(f"\nPortable MSVC installation completed successfully!")
    print(f"  MSVC Version       : {msvcv}")
    print(f"  Windows SDK Version: {sdkv}")
    print(f"  Target Location    : {output_dir}")
    print(f"  Total Downloaded   : {total_download >> 20} MB")
    return 0


if __name__ == "__main__":
    sys.exit(main())

