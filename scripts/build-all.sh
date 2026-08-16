#!/usr/bin/env bash
# ============================================================================
# StudioShellTools build-all.sh
# Cross-compiles 23 CLI tools for Android ARM64 (aarch64, bionic, PIE).
#
# Uses the Android ARM64 NDK:
#   ANDROID_NDK_ROOT=<root>  ??path to an extracted arm64 NDK
#                              (toolchains/llvm/bin/clang-24 layout, NOT linux-x86_64)
#   If unset, downloads android-r27d-arm64.tar.gz from the MobileStudio
#   "NDK-arm64" GitHub Release automatically.
#
# Output: <repo>/<tool>/android-arm64/<tool>-android-arm64.tar.gz
# Each tarball contains bin/ (PIE executables) and lib/ (bundled .so if needed).
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$ROOT/build"
SRC="$WORK/src"
STAGE="$WORK/stage"
mkdir -p "$SRC" "$STAGE"

API="${API:-29}"
TARGET="aarch64-linux-android"
NDK_RELEASE_URL="https://github.com/MobileStudio-AndroidIDE/MobileStudio_AndroidIDE/releases/download/NDK-arm64/android-r27d-arm64.tar.gz"

# ---------------------------------------------------------------------------
# NDK setup
# ---------------------------------------------------------------------------
ensure_ndk() {
    if [ -n "${ANDROID_NDK_ROOT:-}" ] && [ -f "$ANDROID_NDK_ROOT/toolchains/llvm/bin/clang-24" ]; then
        NDK="$ANDROID_NDK_ROOT"
        echo "Using NDK: $NDK"
        return
    fi
    NDK="$WORK/android-ndk-r27d-arm64"
    if [ ! -f "$NDK/toolchains/llvm/bin/clang-24" ]; then
        echo "Downloading Android ARM64 NDK (r27d)..."
        mkdir -p "$WORK"
        curl -fL -o "$WORK/ndk.tar.gz" "$NDK_RELEASE_URL"
        tar -xzf "$WORK/ndk.tar.gz" -C "$WORK"
        rm -f "$WORK/ndk.tar.gz"
        # handle a possible nested root dir
        if [ ! -f "$NDK/toolchains/llvm/bin/clang-24" ]; then
            NESTED="$(find "$WORK" -maxdepth 2 -type f -path '*toolchains/llvm/bin/clang-24' | head -1)"
            NESTED="${NESTED%/toolchains/llvm/bin/clang-24}"
            if [ -n "$NESTED" ]; then mv "$NESTED" "$NDK"; fi
        fi
    fi
    [ -f "$NDK/toolchains/llvm/bin/clang-24" ] || { echo "NDK clang-24 not found"; exit 1; }
    echo "Using NDK: $NDK"
}

# ---------------------------------------------------------------------------
# Cross toolchain env
# ---------------------------------------------------------------------------
setup_toolchain() {
    export LLVM_HOME="$NDK/toolchains/llvm"
    export SYSROOT="$LLVM_HOME/sysroot"
    export TOOL_PREFIX="$LLVM_HOME/bin"
    export CC="$TOOL_PREFIX/clang --target=$TARGET$API --sysroot=$SYSROOT"
    export CXX="$TOOL_PREFIX/clang++ --target=$TARGET$API --sysroot=$SYSROOT"
    export AR="$TOOL_PREFIX/llvm-ar"
    export AS="$TOOL_PREFIX/llvm-as"
    export LD="$TOOL_PREFIX/ld.lld"
    export NM="$TOOL_PREFIX/llvm-nm"
    export STRIP="$TOOL_PREFIX/llvm-strip"
    export RANLIB="$TOOL_PREFIX/llvm-ranlib"
    export OBJDUMP="$TOOL_PREFIX/llvm-objdump"
    export CFLAGS="-O2 -fPIE -fPIC --sysroot=$SYSROOT"
    export CXXFLAGS="$CFLAGS"
    export LDFLAGS="-fPIE -pie --sysroot=$SYSROOT"
    export LIBS="-llog"
    export ac_cv_func_malloc_0_nonnull=yes
    export ac_cv_func_realloc_0_nonnull=yes
    export gl_cv_func_getcwd_null=yes
    export am_cv_func_working_getline=yes
    # `file`/`readelf` on the build host for arch verification:
    HOST_FILE="$(command -v file || true)"
    HOST_READELF="$(command -v readelf || true)"
    echo "Toolchain: clang-24 -> $TARGET$API"
}

# Fetch sources (pinned versions). Extracts any of .tar.gz/.tar.xz.
fetch() {
    local n="$1" u="$2"
    if [ ! -e "$SRC/$n" ]; then
        echo "Fetching $n ..."
        curl -fL -o "$SRC/$n.tmp" "$u"
        case "$u" in
            *.xz) xz -dc "$SRC/$n.tmp" | tar -xf - -C "$SRC" ;;
            *)    tar -xzf "$SRC/$n.tmp" -C "$SRC" ;;
        esac
        rm -f "$SRC/$n.tmp"
    fi
}

package_tool() {
    local tool="$1" stage="$2"
    local outdir="$ROOT/$tool/android-arm64"
    mkdir -p "$outdir"
    tar -czf "$outdir/$tool-android-arm64.tar.gz" -C "$stage" .
    echo "packaged: $outdir/$tool-android-arm64.tar.gz"
}

# ---------------------------------------------------------------------------
# Dependencies (static, so tools are self-contained)
# ---------------------------------------------------------------------------
build_zlib() {
    local dir="$SRC/zlib-1.3.1"
    [ -d "$dir" ] || { echo "skip zlib (missing $dir)"; return 1; }
    ( cd "$dir"
      CC="$CC" AR="$AR" RANLIB="$RANLIB" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
        ./configure --static --prefix="$STAGE/deps" >/dev/null
      make -j"$(nproc)" libz.a >/dev/null
      make install >/dev/null )
}

build_openssl() {
    local dir="$SRC/openssl-3.3.2"
    [ -d "$dir" ] || { echo "skip openssl (missing $dir)"; return 1; }
    ( cd "$dir"
      ./Configure android-aarch64 no-shared no-tests no-asm \
        -D__ANDROID_API__="$API" --prefix="$STAGE/deps" --openssldir="$STAGE/deps" \
        --cross-compile-prefix="$TOOL_PREFIX/llvm-" \
        CFLAGS="-O2 -fPIC" >/dev/null
      make -j"$(nproc)" >/dev/null
      make install_sw >/dev/null )
}

# ---------------------------------------------------------------------------
# Tool: curl
# ---------------------------------------------------------------------------
build_curl() {
    local dir="$SRC/curl-8.7.1" stage="$STAGE/curl"
    [ -d "$dir" ] || { echo "skip curl (missing $dir)"; return 1; }
    ( cd "$dir"
      ./configure --host="$TARGET" --prefix="$stage" --disable-shared --enable-static \
        --with-ssl="$STAGE/deps" --with-zlib="$STAGE/deps" \
        --without-libidn2 --without-libpsl --without-nghttp2 --without-brotli \
        --disable-ldap --disable-ldaps --disable-manual --disable-nls \
        --enable-threaded-resolver >/dev/null
      make -j"$(nproc)" >/dev/null
      make install >/dev/null )
    "$STRIP" "$stage/bin/curl"
}

# ---------------------------------------------------------------------------
# Tool: git (needs libcurl + openssl + zlib)
# ---------------------------------------------------------------------------
build_git() {
    local dir="$SRC/git-2.45.2" stage="$STAGE/git"
    [ -d "$dir" ] || { echo "skip git (missing $dir)"; return 1; }
    ( cd "$dir"
      ./configure --host="$TARGET" --prefix="$stage" \
        --with-curl="$STAGE/deps" --with-openssl="$STAGE/deps" \
        --with-zlib="$STAGE/deps" \
        --without-tcltk --disable-nls >/dev/null
      make -j"$(nproc)" \
        NO_GETTEXT=YesPlease NO_PERL=YesPlease NO_PYTHON=YesPlease \
        NO_TCLTK=YesPlease NO_ICONV=YesPlease NO_EXPAT=YesPlease NO_CURL= \
        prefix="$stage" >/dev/null
      make install prefix="$stage" \
        NO_GETTEXT=YesPlease NO_PERL=YesPlease NO_PYTHON=YesPlease \
        NO_TCLTK=YesPlease NO_ICONV=YesPlease NO_EXPAT=YesPlease >/dev/null )
    "$STRIP" "$stage/bin/git"
}

# ---------------------------------------------------------------------------
# Tool: wget
# ---------------------------------------------------------------------------
build_wget() {
    local dir="$SRC/wget-1.24.5" stage="$STAGE/wget"
    [ -d "$dir" ] || { echo "skip wget (missing $dir)"; return 1; }
    ( cd "$dir"
      ./configure --host="$TARGET" --prefix="$stage" --with-ssl=openssl \
        --with-openssl="$STAGE/deps" --with-zlib="$STAGE/deps" \
        --without-libpsl --without-libidn2 --without-libpcre2 \
        --disable-nls --disable-iri >/dev/null
      make -j"$(nproc)" >/dev/null
      make install >/dev/null )
    "$STRIP" "$stage/bin/wget"
}

# ---------------------------------------------------------------------------
# Tool: ssh + scp (OpenSSH portable)
# ---------------------------------------------------------------------------
build_openssh() {
    local dir="$SRC/openssh-9.7p1" stage="$STAGE/openssh"
    [ -d "$dir" ] || { echo "skip openssh (missing $dir)"; return 1; }
    ( cd "$dir"
      ./configure --host="$TARGET" --prefix="$stage" \
        --with-ssl-dir="$STAGE/deps" --with-zlib="$STAGE/deps" \
        --disable-etc-default-login --disable-strip \
        --with-privsep-path="$stage/var/empty" >/dev/null
      make -j"$(nproc)" ssh scp sftp >/dev/null )
    mkdir -p "$stage/bin"
    cp "$dir/ssh" "$dir/scp" "$dir/sftp" "$stage/bin/"
    "$STRIP" "$stage/bin/ssh" "$stage/bin/scp"
    package_tool ssh "$stage"
    package_tool scp "$stage"
}

# ---------------------------------------------------------------------------
# Tool: tar
# ---------------------------------------------------------------------------
build_tar() {
    local dir="$SRC/tar-1.35" stage="$STAGE/tar"
    [ -d "$dir" ] || { echo "skip tar (missing $dir)"; return 1; }
    ( cd "$dir"
      ./configure --host="$TARGET" --prefix="$stage" --disable-nls \
        --without-selinux --without-xattrs --without-acls >/dev/null
      make -j"$(nproc)" >/dev/null
      make install >/dev/null )
    "$STRIP" "$stage/bin/tar"
}

# ---------------------------------------------------------------------------
# Tool: unzip (Info-ZIP, plain Makefile)
# ---------------------------------------------------------------------------
build_unzip() {
    local dir="$SRC/unzip60" stage="$STAGE/unzip"
    [ -d "$dir" ] || { echo "skip unzip (missing $dir)"; return 1; }
    ( cd "$dir"
      make -f unix/Makefile generic \
        CC="$TOOL_PREFIX/clang --target=$TARGET$API --sysroot=$SYSROOT" \
        LD="$TOOL_PREFIX/clang --target=$TARGET$API --sysroot=$SYSROOT" \
        CFLAGS="-O2 -fPIE -DNO_LCHMOD -DNO_WORKING_GETCWD" \
        LDFLAGS="-fPIE -pie -llog" \
        BINDIR="$stage/bin" MANDIR="$stage/man" >/dev/null
      mkdir -p "$stage/bin"
      cp unzip "$stage/bin/unzip"
      cp unzipsfx "$stage/bin/" 2>/dev/null || true )
    "$STRIP" "$stage/bin/unzip"
}

# ---------------------------------------------------------------------------
# Tool: grep
# ---------------------------------------------------------------------------
build_grep() {
    local dir="$SRC/grep-3.11" stage="$STAGE/grep"
    [ -d "$dir" ] || { echo "skip grep (missing $dir)"; return 1; }
    ( cd "$dir"
      ./configure --host="$TARGET" --prefix="$stage" --disable-nls >/dev/null
      make -j"$(nproc)" >/dev/null
      make install >/dev/null )
    "$STRIP" "$stage/bin/grep"
}

# ---------------------------------------------------------------------------
# Tool: sed
# ---------------------------------------------------------------------------
build_sed() {
    local dir="$SRC/sed-4.9" stage="$STAGE/sed"
    [ -d "$dir" ] || { echo "skip sed (missing $dir)"; return 1; }
    ( cd "$dir"
      ./configure --host="$TARGET" --prefix="$stage" --disable-nls \
        --disable-i18n >/dev/null
      make -j"$(nproc)" >/dev/null
      make install >/dev/null )
    "$STRIP" "$stage/bin/sed"
}

# ---------------------------------------------------------------------------
# Tool: find + xargs (findutils)
# ---------------------------------------------------------------------------
build_findutils() {
    local dir="$SRC/findutils-4.9.0" stage="$STAGE/findutils"
    [ -d "$dir" ] || { echo "skip findutils (missing $dir)"; return 1; }
    ( cd "$dir"
      ./configure --host="$TARGET" --prefix="$stage" --disable-nls \
        --without-selinux >/dev/null
      make -j"$(nproc)" >/dev/null
      make install >/dev/null )
    mkdir -p "$stage/bin"
    "$STRIP" "$stage/bin/find" "$stage/bin/xargs" "$stage/bin/locate" 2>/dev/null || true
    mkdir -p "$ROOT/find/android-arm64" "$ROOT/xargs/android-arm64"
    # find
    local findStage="$STAGE/find"; mkdir -p "$findStage/bin"
    cp "$stage/bin/find" "$findStage/bin/"
    package_tool find "$findStage"
    # xargs
    local xargsStage="$STAGE/xargs"; mkdir -p "$xargsStage/bin"
    cp "$stage/bin/xargs" "$xargsStage/bin/"
    package_tool xargs "$xargsStage"
}

# ---------------------------------------------------------------------------
# Tool: diff (diffutils)
# ---------------------------------------------------------------------------
build_diffutils() {
    local dir="$SRC/diffutils-3.10" stage="$STAGE/diff"
    [ -d "$dir" ] || { echo "skip diffutils (missing $dir)"; return 1; }
    ( cd "$dir"
      ./configure --host="$TARGET" --prefix="$stage" --disable-nls >/dev/null
      make -j"$(nproc)" >/dev/null
      make install >/dev/null )
    "$STRIP" "$stage/bin/diff"
}

# ---------------------------------------------------------------------------
# Tool: patch
# ---------------------------------------------------------------------------
build_patch() {
    local dir="$SRC/patch-2.7.6" stage="$STAGE/patch"
    [ -d "$dir" ] || { echo "skip patch (missing $dir)"; return 1; }
    ( cd "$dir"
      ./configure --host="$TARGET" --prefix="$stage" --disable-nls >/dev/null
      make -j"$(nproc)" >/dev/null
      make install >/dev/null )
    "$STRIP" "$stage/bin/patch"
}

# ---------------------------------------------------------------------------
# Tools: sort / uniq / head / tail / cut (coreutils)
# ---------------------------------------------------------------------------
build_coreutils() {
    local dir="$SRC/coreutils-9.5" stage="$STAGE/coreutils"
    [ -d "$dir" ] || { echo "skip coreutils (missing $dir)"; return 1; }
    ( cd "$dir"
      ./configure --host="$TARGET" --prefix="$stage" --disable-nls \
        --without-selinux >/dev/null
      make -j"$(nproc)" >/dev/null
      make install >/dev/null )
    mkdir -p "$stage/bin"
    for tool in sort uniq head tail cut; do
        local tStage="$STAGE/$tool"
        mkdir -p "$tStage/bin"
        cp "$stage/bin/$tool" "$tStage/bin/"
        "$STRIP" "$tStage/bin/$tool"
        package_tool "$tool" "$tStage"
    done
}

# ---------------------------------------------------------------------------
# Tool: which
# ---------------------------------------------------------------------------
build_which() {
    local dir="$SRC/which-2.21" stage="$STAGE/which"
    [ -d "$dir" ] || { echo "skip which (missing $dir)"; return 1; }
    ( cd "$dir"
      ./configure --host="$TARGET" --prefix="$stage" --disable-nls >/dev/null
      make -j"$(nproc)" >/dev/null
      make install >/dev/null )
    "$STRIP" "$stage/bin/which"
}

# ---------------------------------------------------------------------------
# Tool: file (libmagic)
# ---------------------------------------------------------------------------
build_file() {
    local dir="$SRC/file-5.45" stage="$STAGE/file"
    [ -d "$dir" ] || { echo "skip file (missing $dir)"; return 1; }
    ( cd "$dir"
      ./configure --host="$TARGET" --prefix="$stage" --disable-nls \
        --disable-silent-rules >/dev/null
      make -j"$(nproc)" >/dev/null
      make install >/dev/null )
    "$STRIP" "$stage/bin/file"
}

# ---------------------------------------------------------------------------
# Tools: readelf / objdump / nm ??LLVM 24 from the ARM64 NDK
# ---------------------------------------------------------------------------
build_llvm_tools() {
    local stage="$STAGE/llvm-tools" bin="$LLVM_HOME/bin" lib="$LLVM_HOME/lib"
    for pair in "readelf:llvm-readelf" "objdump:llvm-objdump" "nm:llvm-nm"; do
        local tool="${pair%%:*}" src="${pair##*:}"
        local tStage="$STAGE/$tool" binDir
        mkdir -p "$tStage/bin" "$tStage/lib"
        if [ -f "$bin/$src" ]; then
            cp "$bin/$src" "$tStage/bin/$tool"
            chmod +x "$tStage/bin/$tool"
        else
            echo "!! $src not found in NDK bin ??skipping $tool"
            continue
        fi
        # bundle any shared libs the LLVM tool needs (libLLVM*.so etc.)
        for d in "$lib" "$bin"; do
            if [ -d "$d" ]; then
                for so in "$d"/*.so; do
                    [ -e "$so" ] && cp "$so" "$tStage/lib/" 2>/dev/null || true
                done
            fi
        done
        "$STRIP" "$tStage/bin/$tool" 2>/dev/null || true
        package_tool "$tool" "$tStage"
    done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
ensure_ndk
setup_toolchain

# Fetch sources (pinned versions)
fetch zlib-1.3.1      https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz
fetch openssl-3.3.2   https://www.openssl.org/source/openssl-3.3.2.tar.gz
fetch curl-8.7.1      https://curl.se/download/curl-8.7.1.tar.gz
fetch git-2.45.2      https://github.com/git/git/archive/refs/tags/v2.45.2.tar.gz
fetch wget-1.24.5     https://ftp.gnu.org/gnu/wget/wget-1.24.5.tar.gz
fetch openssh-9.7p1   https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-9.7p1.tar.gz
fetch tar-1.35        https://ftp.gnu.org/gnu/tar/tar-1.35.tar.gz
fetch unzip60         https://downloads.sourceforge.net/project/infozip/UnZip%206.x%20%28latest%29/UnZip%206.0/unzip60.tar.gz
fetch grep-3.11       https://ftp.gnu.org/gnu/grep/grep-3.11.tar.xz
fetch sed-4.9         https://ftp.gnu.org/gnu/sed/sed-4.9.tar.xz
fetch findutils-4.9.0 https://ftp.gnu.org/gnu/findutils/findutils-4.9.0.tar.xz
fetch diffutils-3.10  https://ftp.gnu.org/gnu/diffutils/diffutils-3.10.tar.xz
fetch patch-2.7.6     https://ftp.gnu.org/gnu/patch/patch-2.7.6.tar.xz
fetch coreutils-9.5   https://ftp.gnu.org/gnu/coreutils/coreutils-9.5.tar.xz
fetch which-2.21      https://ftp.gnu.org/gnu/which/which-2.21.tar.gz
fetch file-5.45       https://astron.com/pub/file/file-5.45.tar.gz

# Dependencies first
build_zlib || true
build_openssl || true

# Tools
build_curl || echo "!! curl failed ??skipping"
build_git || echo "!! git failed ??skipping"
build_wget || echo "!! wget failed ??skipping"
build_openssh || echo "!! openssh failed ??skipping"
build_tar || echo "!! tar failed ??skipping"
build_unzip || echo "!! unzip failed ??skipping"
build_grep || echo "!! grep failed ??skipping"
build_sed || echo "!! sed failed ??skipping"
build_findutils || echo "!! findutils failed ??skipping"
build_diffutils || echo "!! diffutils failed ??skipping"
build_patch || echo "!! patch failed ??skipping"
build_coreutils || echo "!! coreutils failed ??skipping"
build_which || echo "!! which failed ??skipping"
build_file || echo "!! file failed ??skipping"
build_llvm_tools || echo "!! llvm tools failed ??skipping"

echo
echo "Done. Run ./scripts/verify.sh then ./scripts/make-manifest.sh,"
echo "then ./scripts/upload.sh to publish."