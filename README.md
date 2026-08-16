# StudioShellTools

Android ARM64 (aarch64) CLI development tools for [MobileStudio](https://github.com/MobileStudio-AndroidIDE/MobileStudio_AndroidIDE) Shell.

Each tool is a **real Android ARM64 binary** (bionic, PIE, run via `/system/bin/linker64`). No Windows/Linux x86_64 binaries are used.

## Repository layout

```
StudioShellTools/
├── manifest.json          # tool metadata: version / size / url / sha256  (managed in git)
├── checksums.sha256       # SHA-256 of every release tarball             (managed in git)
├── scripts/
│   ├── build-all.sh       # cross-compile all tools for Android ARM64
│   ├── make-manifest.sh   # regenerate manifest.json + checksums.sha256 from built tarballs
│   ├── verify.sh          # pre-upload gate: arch / exec bits / checksum / size / no x86
│   └── upload.sh          # push tarballs to GitHub Release "tools-v1" + commit manifest
├── git/android-arm64/git-android-arm64.tar.gz    (generated, uploaded to Release — NOT committed)
├── curl/android-arm64/curl-android-arm64.tar.gz  (generated)
├── build/                 # NDK + sources + staging (generated, gitignored)
└── ... (23 tools)
```

Large binaries are **not** committed to the repository (see `.gitignore`).
They are uploaded as GitHub Release assets (`tools-v1`) and the manifest points to those URLs.
The repository itself only tracks metadata (manifest + checksums + scripts).

## Tools

| tool     | version            | source                |
|----------|--------------------|-----------------------|
| git      | 2.45.2             | git (+openssl 3.3.2, zlib 1.3.1, libcurl) |
| curl     | 8.7.1              | curl                  |
| wget     | 1.24.5             | wget                  |
| ssh/scp  | 9.7p1              | OpenSSH portable      |
| tar      | 1.35               | GNU tar               |
| unzip    | 6.0                | Info-ZIP              |
| grep     | 3.11               | GNU grep              |
| sed      | 4.9                | GNU sed               |
| find/xargs | 4.9.0            | GNU findutils         |
| diff     | 3.10               | GNU diffutils         |
| patch    | 2.7.6              | GNU patch             |
| sort/uniq/head/tail/cut | 9.5 | GNU coreutils     |
| which    | 2.21               | GNU which             |
| file     | 5.45               | file (libmagic)       |
| readelf/objdump/nm | LLVM 18 | NDK r27d (llvm-readelf/llvm-objdump/llvm-nm) |

These versions are recorded in `manifest.json` — the app's shell shows them in
`tools list` / `tools available` / `tools install <tool>` (override per tool with `<TOOL>_VERSION` env).

## Quick start (on Linux/WSL)

```bash
git clone https://github.com/MobileStudio-AndroidIDE/StudioShellTools.git
cd StudioShellTools

./scripts/build-all.sh     # downloads a Linux-host NDK (~600 MB, once) and builds all 23 tools
./scripts/upload.sh        # verify → regenerate manifest → upload to Release "tools-v1" → commit+push
```

Then in the MobileStudio app shell: `tools update` / `tools list` and run any missing command
(e.g. `git --version`) — it will be offered for lazy download.

## Build notes

* **NDK**: `build-all.sh` needs a **Linux-host** NDK (clang runs natively in WSL).
  It auto-downloads `android-ndk-r27d-linux.zip` from `dl.google.com` (~600 MB, extracted once into `build/android-ndk-r27d`).
  Set `ANDROID_NDK_ROOT=/path/to/ndk` to use an existing one.
  The **Windows** Android Studio NDK (clang.exe) does not work in WSL.
  The **ARM64 device** NDK (`NDK-arm64` GitHub Release on MobileStudio) is a separate thing —
  it runs on the phone for on-device compilation and is downloaded by the app itself.
* Output: `<tool>/android-arm64/<tool>-android-arm64.tar.gz`, each containing `bin/` (PIE executables)
  and `lib/` (bundled `.so` if needed).
* `build-all.sh` downloads pinned source tarballs into `build/src/` and cross-compiles with
  `--target=aarch64-linux-android29 --sysroot=$LLVM_HOME/sysroot`.

## Verification checklist (before upload)

* binary is `ELF 64-bit LSB pie executable, ARM aarch64` (`file`)
* `readelf -h` shows `Machine: AArch64`
* exec bits are preserved in the tarball
* all required shared libraries are bundled in `lib/`
* SHA-256 in `checksums.sha256` matches the tarball
* manifest `size` matches the tarball size
* binaries run on a real Android device:
  `git --version`, `curl --version`, `wget --version`, `ssh -V`, `tar --version`, `grep --version`, `find --version`
* no x86 / x86_64 binaries mixed in