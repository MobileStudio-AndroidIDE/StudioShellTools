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
└── ... (23 tools)
```

Large binaries are **not** committed to the repository (see `.gitignore`).
They are uploaded as GitHub Release assets (`tools-v1`) and the manifest points to those URLs.
The repository itself only tracks metadata (manifest + checksums + scripts).

## Tools

| tool     | source                |
|----------|-----------------------|
| git      | git 2.45.2 (+openssl 3.3.2, zlib 1.3.1, libcurl) |
| curl     | curl 8.7.1            |
| wget     | wget 1.24.5           |
| ssh/scp  | OpenSSH portable 9.7p1 |
| tar      | GNU tar 1.35          |
| unzip    | Info-ZIP 6.0          |
| grep     | GNU grep 3.11         |
| sed      | GNU sed 4.9           |
| find/xargs | GNU findutils 4.9.0 |
| diff     | GNU diffutils 3.10    |
| patch    | GNU patch 2.7.6       |
| sort/uniq/head/tail/cut | GNU coreutils 9.5 |
| which    | GNU which 2.21        |
| file     | file 5.45 (libmagic)  |
| readelf/objdump/nm | LLVM 24 from the ARM64 NDK (llvm-readelf/llvm-objdump/llvm-nm) |

## Build (on Linux/WSL, with the ARM64 NDK)

```bash
# 1. Get the ARM64 NDK (r27d) — from the NDK-arm64 GitHub Release:
#    https://github.com/MobileStudio-AndroidIDE/MobileStudio_AndroidIDE/releases/tag/NDK-arm64
#    or set ANDROID_NDK_ROOT=/path/to/android-ndk-r27d-arm64

./scripts/build-all.sh          # builds all 23 tools into <tool>/android-arm64/*.tar.gz
./scripts/verify.sh             # arch + exec bit + checksum + size checks
./scripts/upload.sh             # creates/updates Release tools-v1 and commits manifest
```

`build-all.sh` downloads pinned source tarballs into `build/src/` and cross-compiles
with the ARM64 NDK clang (`--target=aarch64-linux-android29 --sysroot=$LLVM_HOME/sysroot`).

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