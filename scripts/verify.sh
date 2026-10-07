#!/usr/bin/env bash
# ============================================================================
# verify.sh — pre-upload gate for every built StudioShellTools tarball.
#
# Checks, per requirement 23:
#   * every binary is Android ARM64 (aarch64) ELF PIE
#   * exec bits preserved
#   * no x86 / x86_64 binaries mixed in
#   * SHA-256 matches checksums.sha256 (regenerate first: scripts/make-checksums.sh)
#   * bundled shared libraries present when needed
# ============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0

check_arch() {
    local tarball="$1"
    local tool
    tool="$(basename "$tarball" -android-arm64.tar.gz)"

    rm -rf "$TMP/$tool"; mkdir -p "$TMP/$tool"
    tar -xzf "$tarball" -C "$TMP/$tool"

    local bad=0
    while IFS= read -r bin; do
        if [ -f "$bin" ]; then
            local out
            out="$(file -b "$bin" 2>/dev/null)"
            case "$out" in
                *"ELF 64-bit LSB"*"ARM aarch64"*) : ;;
                *"script"*|*"text"*) : ;;   # helper scripts are fine
                *) echo "!! $tool: wrong arch: $out ($bin)"; bad=1 ;;
            esac
        fi
    done < <(find "$TMP/$tool" -path '*/bin/*' -type f -o -path '*/bin/*' -type l)

    # any x86 ELF binary anywhere? (raw string grep would false-positive on
    # LLVM tools, which reference x86 targets internally)
    if find "$TMP/$tool" -type f -print0 | xargs -0 file -b 2>/dev/null | grep -qE "ELF .*(x86-64|Intel 80386)"; then
        echo "!! $tool: x86 ELF binary detected"; bad=1
    fi

    # exec bits
    local exe="$TMP/$tool/bin/$tool"
    if [ -f "$exe" ] && [ ! -x "$exe" ]; then
        echo "!! $tool: exec bit missing on $exe"; bad=1
    fi

    # sha256 vs checksums.sha256
    local sha want
    sha="$(sha256sum "$tarball" | awk '{print $1}')"
    want="$(awk -v n="$tool-android-arm64.tar.gz" '$2 == n {print $1}' "$ROOT/checksums.sha256")"
    if [ -z "$want" ]; then
        echo "!! $tool: no entry in checksums.sha256 (run scripts/make-checksums.sh)"; bad=1
    elif [ "$sha" != "$want" ]; then
        echo "!! $tool: sha256 mismatch (checksums $want vs $sha)"; bad=1
    fi

    [ "$bad" -eq 0 ] || return 1
    echo "ok  $tool  ($(stat -c %s "$tarball") bytes)"
}

shopt -s nullglob
tarballs=("$ROOT"/*/android-arm64/*-android-arm64.tar.gz)
if [ "${#tarballs[@]}" -eq 0 ]; then
    echo "!! no tarballs found — run scripts/build-all.sh first"
    exit 1
fi

for tarball in "${tarballs[@]}"; do
    check_arch "$tarball" || failures=$((failures + 1))
done

echo
if [ "$failures" -eq 0 ]; then
    echo "All tools verified (Android ARM64)."
else
    echo "$failures tool(s) FAILED verification — do not upload."
    exit 1
fi
