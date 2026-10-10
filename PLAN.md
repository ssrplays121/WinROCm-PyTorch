# PLAN: rocm-portable-windows

Implementation plan for turning `setup_rocm_portable.ps1` into a publishable GitHub project: a one-script, fully isolated installer for AMD ROCm PyTorch on Windows.

**Status of the current script:** written and reviewed but not yet confirmed end-to-end on real hardware. Phase 0 is therefore a gate: nothing else starts until the baseline works.

---

## 1. Goals and non-goals

### Goals
1. Install Python 3.12 (embeddable), the ROCm SDK wheels and PyTorch (torch, torchvision, torchaudio) into **one folder**, with no system changes.
2. Support multiple AMD ROCm-for-Windows releases through a data file, not hard-coded URLs.
3. Fail early and clearly (preflight checks), recover gracefully (retries, re-runs), and be easy to debug (logs, `-Diagnose`).
4. Keep the environment stable after install (pin torch so a stray `pip install` cannot replace it).
5. Ship with a README, license, CI and issue templates.

### Non-goals
- Installing or managing the AMD Adrenalin driver (system-level; documented only).
- Supporting Linux, WSL, macOS, NVIDIA, or Python versions other than 3.12 (AMD's wheels are `cp312`).
- Redistributing AMD's wheels (the script only downloads them from AMD).
- Supporting GPUs that AMD's official Windows wheels do not support (warn, don't block).

---

## 2. Target repository layout

```
rocm-portable-windows/
├─ setup_rocm_portable.ps1        # main script
├─ config/
│  └─ releases.psd1               # ROCm release table (URLs, files, supported GPU patterns)
├─ templates/
│  ├─ env_rocm.bat                # isolated environment (sourced by the others)
│  ├─ run_rocm.bat
│  ├─ pip_rocm.bat
│  ├─ shell_rocm.bat
│  ├─ env_rocm.ps1                # PowerShell equivalent of env_rocm.bat
│  └─ verify_rocm.py
├─ tests/
│  ├─ Setup.Tests.ps1             # Pester tests
│  └─ PSScriptAnalyzerSettings.psd1
├─ .github/
│  ├─ workflows/
│  │  ├─ lint-test.yml            # PSScriptAnalyzer + Pester on windows-latest
│  │  └─ url-check.yml            # scheduled: HEAD-check every URL in releases.psd1
│  └─ ISSUE_TEMPLATE/
│     └─ bug_report.yml           # asks for `-Diagnose` output
├─ README.md
├─ CHANGELOG.md                   # Keep a Changelog format
├─ LICENSE                        # MIT
├─ SECURITY.md
├─ PLAN.md                        # this file (may be removed after 1.0)
└─ .gitignore
```

`.gitignore`:

```
python/
.cache/
.tmp/
logs/
constraints-rocm.txt
.rocm-portable.json
diagnose.txt
*.log
```

Installation folder behavior: default `-InstallDir` is the script's own folder (current behavior). Launchers are copied from `templates/` into the install dir on every run. If install dir equals the repo root, the committed templates stay in `templates/` and the copies at the root are generated, untracked files (add them to `.gitignore` by name: `/env_rocm.bat`, `/run_rocm.bat`, `/pip_rocm.bat`, `/shell_rocm.bat`, `/env_rocm.ps1`).

---

## 3. Phases

Effort: S = under an hour, M = a few hours, L = a day or more.

### Phase 0: Baseline gate (S)
- [ ] Run the current `setup_rocm_portable.ps1` on the target machine (RX 9060 XT) in a clean folder.
- [ ] Record: Windows build, GPU, driver version, PowerShell version, download size, install size, wall-clock time.
- [ ] Confirm `verify_rocm.py` reports `ROCm/CUDA Available : True` and the GPU matmul passes.
- [ ] Confirm `torch.__file__` points inside the folder.
- [ ] Confirm the `rocm-7.2.0.dev0.tar.gz` source build works inside embeddable Python (needs setuptools; build goes to `.tmp`).
- [ ] If anything fails, fix it before continuing. Everything below assumes a working baseline.

**Done when:** a clean run succeeds end-to-end and the numbers above are written into the README "Tested on" table draft.

### Phase 1: Refactor into data + templates (M)
- [ ] Create `config/releases.psd1` (see section 4) and load it with `Import-PowerShellDataFile` (no code execution).
- [ ] Move launcher here-strings into real files under `templates/`; script copies them to the install dir.
- [ ] Move `verify_rocm.py` into `templates/`.
- [ ] Add a `[CmdletBinding()]` param block (section 5) and comment-based help (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`).
- [ ] Add `Set-StrictMode -Version Latest` and fix whatever it surfaces.
- [ ] Split the script into functions: `Test-Preflight`, `Get-ReleaseConfig`, `Install-Python`, `Install-Pip`, `Install-RocmSdk`, `Install-Torch`, `Write-Launchers`, `Write-Constraints`, `Invoke-Verify`, `Invoke-Diagnose`.

**Done when:** behavior is identical to the Phase 0 script, driven by `releases.psd1`.

### Phase 2: Preflight checks (M)
Run before any download. See section 6 for the check list. Add `-DryRun` here: runs preflight, prints the plan, HEAD-checks every URL, downloads nothing.

**Done when:** `-DryRun` on a bad environment (e.g., a 150-character path) fails with a clear message and exit code 2.

### Phase 3: Robustness (M)
- [ ] `Invoke-WithRetry` helper for downloads (3 attempts, exponential backoff).
- [ ] pip flags: `--retries 5 --timeout 60`.
- [ ] State file `.rocm-portable.json` and idempotent steps (section 7).
- [ ] `-Reinstall` switch.
- [ ] Transcript logging (section 8).
- [ ] Exit codes (section 9).
- [ ] Hash verification for the Python zip (section 10).
- [ ] Pin pip and setuptools versions.

### Phase 4: Environment protection (S)
- [ ] After a successful install, generate `constraints-rocm.txt` (section 11).
- [ ] Set `PIP_CONSTRAINT` in `env_rocm.bat` and `env_rocm.ps1`.
- [ ] `-Reinstall` and release changes temporarily bypass the constraint.

### Phase 5: Diagnostics (S)
- [ ] Implement `-Diagnose` (section 12).
- [ ] Issue template that asks for `diagnose.txt`.

### Phase 6: Tests and CI (M)
- [ ] Pester tests (section 13).
- [ ] PSScriptAnalyzer config and workflow.
- [ ] Scheduled URL-check workflow.
- [ ] Manual test matrix (section 13.3), results recorded in README.

### Phase 7: Docs and release (M)
- [ ] README (section 14), CHANGELOG, LICENSE, SECURITY.md, `.gitignore`.
- [ ] Tag `v0.1.0`; create a GitHub release with notes.

### Phase 8 (optional, after 1.0): `uv` spike (L)
Decision gate in section 15. Not part of 1.0 unless the spike clearly wins.

---

## 4. Release table: `config/releases.psd1`

Data-only PowerShell file. Adding a new ROCm release should require no script changes.

```powershell
@{
    DefaultRelease = '7.2'

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

    # Name patterns for the GPU preflight (warn-only). Source: AMD's release notes
    # for "PyTorch on Windows"; re-check on every new release.
    SupportedGpuPatterns = @(
        'Radeon RX 9070', 'Radeon RX 9060 XT', 'Radeon AI PRO R9700',
        'Radeon RX 7900 XTX', 'Radeon PRO W7900',
        'Ryzen AI Max', 'Ryzen AI 9'
    )
}
```

Tasks and open items:
- [ ] Before publishing, check AMD's current Windows PyTorch install page: a release newer than 7.2.1 may exist. Set `DefaultRelease` to the newest one that is verified to work.
- [ ] **Verify** that 7.2.1 supports the RX 9060 XT. The 7.2.1 file names above come from AMD's Ryzen docs page, and the 7.2 support list from the Radeon release notes. Don't ship 7.2.1 as a supported option until it is tested on real hardware or confirmed in AMD's Radeon documentation.
- [ ] Keep one `SupportedGpuPatterns` list per release if support differs between releases.
- [ ] The scheduled `url-check.yml` (section 13.2) HEAD-checks every URL here, so broken links are noticed when AMD reorganizes the repo.

---

## 5. Parameters

```powershell
[CmdletBinding()]
param(
    [string] $InstallDir   = $PSScriptRoot,
    [string] $RocmRelease,                  # defaults to DefaultRelease in releases.psd1
    [switch] $NoVision,                     # skip torchvision
    [switch] $NoAudio,                      # skip torchaudio
    [switch] $Reinstall,                    # wipe .\python and reinstall everything
    [switch] $SkipGpuCheck,                 # do not warn about unsupported / undetected GPU
    [switch] $SkipVerify,                   # skip verify_rocm.py at the end
    [switch] $DryRun,                       # preflight + plan + URL HEAD checks; download nothing
    [switch] $Diagnose,                     # print/write diagnostics and exit
    [switch] $Yes                           # no confirmation prompt (CI / unattended)
)
```

Behavior notes:
- Without `-Yes`, show the plan (release, install dir, approximate download/disk size, components) and ask for confirmation. Non-interactive sessions without `-Yes` exit with code 2.
- `-NoVision`/`-NoAudio` change what the constraints file contains and what the verify step checks.
- `-InstallDir` is created if missing and resolved to a full path. All paths in the script derive from it via `Join-Path`.

---

## 6. Preflight checks (`Test-Preflight`)

Each check returns `Pass`, `Warn` or `Fail`. Any `Fail` aborts with exit code 2 before any download.

| # | Check | Severity | Notes |
|---|-------|----------|-------|
| 1 | 64-bit Windows 11 | Fail | `[Environment]::Is64BitOperatingSystem`; OS build from `Win32_OperatingSystem`. Windows 10: Warn (AMD lists Windows 11). |
| 2 | PowerShell 5.1 or 7+ | Fail below 5.1 | |
| 3 | Not running from a path that is too long | Fail over ~100 chars; Warn over ~60 | Torch has deep paths; MAX_PATH is 260. Suggest `C:\rocm`. Tune thresholds from Phase 0 measurements. |
| 4 | Path has only ASCII, no `%`, `^`, `&`, `!` | Fail on non-ASCII; Warn on the others | Embeddable Python and `.bat` quoting problems. Verify in the test matrix. |
| 5 | Free disk space on the install drive | Fail below the measured need | Measure the real peak (download in `.tmp` plus installed size) in Phase 0; add a margin. |
| 6 | Folder is writable | Fail | Create and delete a temp file. |
| 7 | Network reachability | Fail | HEAD/GET to `www.python.org`, `bootstrap.pypa.io`, `repo.radeon.com`, `pypi.org`. Report which host failed (proxy/firewall hint). |
| 8 | GPU detection | Warn | `Get-CimInstance Win32_VideoController`; match names against `SupportedGpuPatterns`. Print detected name and driver version. No match: warn that official wheels may not detect the GPU. Skipped with `-SkipGpuCheck`. |
| 9 | Not elevated | Warn | The script never needs admin; running elevated is unnecessary. |
| 10 | Mark-of-the-Web | Warn | If `Zone.Identifier` exists on the script, hint at `Unblock-File`. |
| 11 | Existing install state | Info | Read `.rocm-portable.json`; show what would be reused or replaced. |

Driver detection is deliberately **not** a hard gate: AMD's "PyTorch on Windows" driver package has no reliable version check that we have verified. Print the driver version, link to AMD's driver page in the README, and point to `-Diagnose` when `torch.cuda.is_available()` is `False`.

---

## 7. Idempotency and state

State file `.rocm-portable.json` in the install dir:

```json
{
  "scriptVersion": "0.1.0",
  "rocmRelease": "7.2",
  "pythonVersion": "3.12.8",
  "torchVersion": "2.9.1+rocmsdk20260116",
  "components": ["torch", "torchvision", "torchaudio"],
  "installedAtUtc": "2026-10-10T00:00:00Z"
}
```

Step behavior on re-run:

| Step | Skip when | Otherwise |
|------|-----------|-----------|
| Python extract | `python\python.exe` exists and version matches | extract |
| `._pth` config | content already equals expected | rewrite (cheap, always safe) |
| pip bootstrap | `python -m pip --version` works | run get-pip |
| ROCm SDK | state release equals requested and packages import | install |
| PyTorch | state release equals requested and `import torch` works | install |
| Launchers | never skipped | always overwrite from `templates/` |
| Constraints | never skipped | regenerate after successful install |

`-Reinstall`: delete `python\`, `constraints-rocm.txt`, `.rocm-portable.json`; keep `.cache\` and `logs\`. Changing `-RocmRelease` against an existing install behaves like `-Reinstall` for the SDK and torch steps, after a confirmation prompt (or `-Yes`).

---

## 8. Logging

- `Start-Transcript -Path logs\setup-<yyyyMMdd-HHmmss>.log` at start, `Stop-Transcript` in a `finally` block.
- Keep the 5 newest logs; delete older ones.
- pip output is captured by the transcript because the script calls pip directly.
- README note: logs contain local paths (including the Windows user name); redact before sharing publicly. `-Diagnose` output already redacts the user name.

---

## 9. Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success (install complete, verification passed or skipped) |
| 1 | Unexpected error |
| 2 | Preflight failed or confirmation declined / non-interactive without `-Yes` |
| 3 | Download failed after retries |
| 4 | pip install failed |
| 5 | Install succeeded but verification failed (e.g., GPU not available) |

Use a single top-level `try/catch/finally` that maps typed failures to codes and always stops the transcript.

---

## 10. Integrity and pinning

- [ ] Download the Python zip, compute SHA256, store the expected hash in `releases.psd1` (`PythonSha256`), verify after download, and delete + fail on mismatch. Compute the hash yourself from the official download and cross-check it against python.org's published checksum; don't copy from third-party sites.
- [ ] `get-pip.py`: pin to a specific, versioned source (e.g., a tagged commit of `pypa/get-pip`) and verify its SHA256 the same way. Verify the exact URL when implementing.
- [ ] Pin `pip` and `setuptools` versions (and `wheel`) in `releases.psd1` instead of `--upgrade` to latest.
- [ ] Optional hardening: AMD wheel hashes via a generated requirements file with `--require-hashes`. Only if AMD's files are stable; they are not versioned by hash, so record hashes per release and refresh them in the URL-check workflow. Mark as a stretch goal.
- [ ] SECURITY.md: list every host the script contacts (`www.python.org`, `bootstrap.pypa.io`, `repo.radeon.com`, `pypi.org`, `files.pythonhosted.org`), state that the `rocm-*.tar.gz` source package runs a build step during install, and explain how to report vulnerabilities.

---

## 11. Constraints file (stop pip from replacing torch)

Problem: a later `pip install some-package` can pull a different `torch` from PyPI and silently replace the ROCm build.

Plan:
1. After a successful install, write `constraints-rocm.txt` with exact installed versions of the ROCm-related packages. Generate it from metadata, not from guesses:

```python
# executed with the portable python
from importlib.metadata import distributions
want = {"torch", "torchvision", "torchaudio", "rocm",
        "rocm-sdk-core", "rocm-sdk-devel", "rocm-sdk-libraries-custom"}
for d in sorted(distributions(), key=lambda d: d.metadata["Name"].lower()):
    name = d.metadata["Name"]
    if name.lower().replace("_", "-") in want:
        print(f"{name}=={d.version}")
```

2. Set `PIP_CONSTRAINT=%~dp0constraints-rocm.txt` in `env_rocm.bat` / `env_rocm.ps1`.
3. Do **not** set it for the setup script's own pip calls before the file exists.
4. `-Reinstall` and release changes remove the constraints file first.
5. README: explain that `pip_rocm.bat install -U torch` is intentionally blocked, and how to upgrade (re-run the script with a newer `-RocmRelease`).
6. Test (manual and Pester where possible): installing a package that depends on `torch` leaves torch unchanged; a package requiring a newer torch fails with a clear resolver error instead of replacing it.

---

## 12. Diagnostics (`-Diagnose`)

Prints to the console and writes `diagnose.txt` (no install actions):

- Script version, release table version, PowerShell version/edition
- Windows version/build, 64-bit status
- Install dir, path length, free disk space
- GPU names and driver versions (`Win32_VideoController`)
- Whether `python\python.exe` exists, its version, and the contents of the `._pth` file
- `pip list` filtered to torch/rocm packages
- Output of a short Python probe: `torch.__version__`, `torch.__file__`, `torch.version.hip`, `torch.cuda.is_available()`, device names
- Relevant environment variables set by `env_rocm.bat`
- Redaction: replace the Windows user name in all paths with `<user>`

Guidance printed when `is_available()` is `False`: confirm the AMD "PyTorch on Windows" driver package is installed, that the GPU is on AMD's list, and that the install is using the in-folder Python.

---

## 13. Testing and CI

### 13.1 Pester tests (`tests/Setup.Tests.ps1`) — run in CI, no GPU needed
- `releases.psd1` parses; every release has all required keys; filenames match expected patterns (`cp312`, `win_amd64`).
- `Get-ReleaseConfig` resolves the default and rejects unknown releases.
- Path checks: long path, non-ASCII path, path with `%`/`&` produce the expected severity.
- Constraints generation produces valid `name==version` lines (mock the Python call).
- Exit-code mapping for each failure type.
- `-DryRun` makes no network downloads and creates no `python\` folder (mock `Invoke-WebRequest`).

### 13.2 GitHub Actions
- `lint-test.yml` (push, pull_request; `windows-latest`): PSScriptAnalyzer with the repo settings, then Pester. Run Pester under both `pwsh` and Windows PowerShell 5.1.
- `url-check.yml` (weekly schedule + manual): HEAD request for every URL in `releases.psd1`; fail the job and open/update an issue when any returns an error. (Verify during implementation that `repo.radeon.com` answers HEAD requests; fall back to a ranged GET if not.)
- CI has no GPU, so it never runs the GPU verification. A full-install CI job is optional and only worth it if the runner disk and time limits allow several GB of downloads; otherwise rely on `-DryRun`.

### 13.3 Manual test matrix (record results in README)

| Scenario | Expected |
|----------|----------|
| Clean folder, PowerShell 5.1 | success |
| Clean folder, PowerShell 7 | success |
| Folder path with spaces | success |
| Very long folder path | preflight fails with clear message |
| Non-ASCII folder path | preflight fails (or documented limitation) |
| No AMD driver installed | install succeeds, verify reports GPU unavailable, exit code 5, helpful hint |
| Unsupported GPU | warning, install proceeds |
| Network drops mid-download | retry or clean failure with exit code 3/4; re-run recovers |
| Re-run on a completed install | steps skipped; launchers refreshed |
| `-Reinstall` | clean reinstall |
| Switch 7.2 to 7.2.1 | confirmation prompt, then clean switch |
| `pip_rocm.bat install transformers` | torch unchanged (constraints) |
| `-NoVision -NoAudio` | torch only; verify still passes |
| `-DryRun` | no downloads, no folders created |
| Run from `cmd` and PowerShell launchers | both activate the isolated environment |

---

## 14. README outline

1. **Title and one-line description**, plus an "Unofficial, not affiliated with AMD" disclaimer.
2. **What you get** (isolated folder, no PATH/registry changes, what stays outside: the AMD driver).
3. **Requirements:** Windows 11 x64, supported AMD GPU (link to AMD's current compatibility list rather than copying it), AMD "PyTorch on Windows" Adrenalin driver package, free disk space (measured), internet access.
4. **Quick start:**
   ```powershell
   git clone <repo> C:\rocm
   cd C:\rocm
   powershell -ExecutionPolicy Bypass -File .\setup_rocm_portable.ps1
   ```
   Also mention `Unblock-File` for ZIP downloads.
5. **Usage:** `run_rocm.bat script.py`, `pip_rocm.bat install <pkg>`, `shell_rocm.bat`, `env_rocm.ps1` for PowerShell.
6. **Parameters** table (section 5) and exit codes (section 9).
7. **What is isolated and what is not** (temp, caches, user site-packages, pip config; not isolated: driver, anything Windows or a library writes under `%LOCALAPPDATA%`).
8. **Choosing a ROCm release** and how to add one (`releases.psd1`).
9. **Limitations:** embeddable Python (no venv, no headers/libs, no tkinter; packages that compile C extensions and Triton-based `torch.compile` may not work), cp312 only, Windows 11 only.
10. **Troubleshooting:** `is_available()` is `False`; `No matching distribution found for rocm==...` (SDK step missing); path length; antivirus/SmartScreen; proxy; how to run `-Diagnose` and attach `diagnose.txt`.
11. **Updating and uninstalling** (re-run with a newer release; delete the folder).
12. **Tested on** table (Windows build, GPU, driver, ROCm release, PowerShell version).
13. **Security notes**, **Contributing**, **License**, **Changelog link**.

---

## 15. `uv` spike (optional, post-1.0)

Why: embeddable Python lacks `venv`, headers and import libraries, which limits packages that compile extensions and Triton-based features.

Spike scope (time-boxed):
- [ ] Use a standalone `uv.exe` placed in the install dir, with `UV_PYTHON_INSTALL_DIR`, `UV_CACHE_DIR` and `UV_TOOL_DIR` redirected into the folder.
- [ ] Install a full CPython 3.12 into the folder and create a venv there.
- [ ] Install the same ROCm SDK + torch wheels with `uv pip`.
- [ ] Check: folder is still the only place written to; `torch.cuda.is_available()` is `True` on the RX 9060 XT; a GPU matmul passes; `venv` and C-extension builds work; whether `torch.compile` works (**unverified**, that is what the spike must answer).

Decision gate: ship as `-PythonMode uv` (experimental) only if all checks pass and isolation is not weakened. Otherwise document the embeddable limitations and stop.

---

## 16. Release process

1. All phases 0 to 7 complete; manual matrix filled in.
2. `CHANGELOG.md` entry for `0.1.0` (Keep a Changelog; semantic versioning).
3. Script version constant in `setup_rocm_portable.ps1` matches the tag.
4. Tag `v0.1.0`; GitHub release with notes: tested-on table, known limitations, link to AMD's driver page.
5. Enable GitHub Issues with the bug-report template; enable the weekly URL-check workflow.
6. After release: when AMD ships a new ROCm Windows release, add a table entry, run the matrix, bump the minor version.

---

## 17. Risks and open questions

| Item | Risk / question | Mitigation |
|------|-----------------|------------|
| AMD moves or renames files | Broken downloads | Weekly URL check; release table is data-only |
| RX 9060 XT support in newer releases | Unverified for 7.2.1 | Test before enabling; default stays on a verified release |
| Source build of `rocm-*.tar.gz` in embeddable Python | Untested here | Phase 0 gate |
| Install size / time | Several GB; not yet measured | Measure in Phase 0; show in the confirmation prompt |
| Driver detection | No verified version check | Warn-only; rely on `-Diagnose` and README |
| `torch.compile` / Triton on embeddable Python | Likely unsupported | Document; evaluate in the `uv` spike |
| Non-ASCII or long paths | Hard-to-diagnose failures | Preflight checks; README recommends a short ASCII path |
| Antivirus/SmartScreen flagging a downloaded script | User friction | README guidance; no obfuscation; no `iex` one-liner |

---

## 18. Definition of done (v0.1.0)

- Clean install works on PowerShell 5.1 and 7 on the target machine, results recorded.
- All scripts and templates pass PSScriptAnalyzer; Pester tests pass in CI.
- `-DryRun`, `-Diagnose`, `-Reinstall` and re-run behavior verified.
- `pip` cannot replace torch accidentally (constraints verified).
- README, LICENSE, CHANGELOG, SECURITY.md, `.gitignore`, issue template present.
- No AMD binaries committed to the repo.

