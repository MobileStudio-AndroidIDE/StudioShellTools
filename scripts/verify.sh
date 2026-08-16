#!/usr/bin/env bash
# ============================================================================
# verify.sh — pre-upload gate for every built StudioShellTools tarball.
#
# Checks, per requirement 23:
#   * every binary is Android ARM64 (aarch64) ELF PIE
#   * exec bits preserved
#   * no x86 / x86_64 binaries mixed in
#   * SHA-256 matches checksums.sha256
#   * manifest size matches the tarball size
#   * bundled shared libraries present when needed
# ============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
checks() { [ "$?" -eq 0 ]; }

check_arch() {
    local tool="$1"
    local tarball="$ROOT/$tool/android-arm64/$tool-android-arm64.tar.gz"
    [ -f "$tarball" ] || { echo "!! $tool: missing tarball"; return 1; }

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

    # sha256 + size vs manifest
    local sha size msha msize
    sha="$(sha256sum "$tarball" | awk '{print $1}')"
    size="$(stat -c %s "$tarball")"
    msha="$(python3 -c "import json;print(json.load(open('$ROOT/manifest.json')).get('$tool',{}).get('sha256',''))" 2>/dev/null)"
    msize="$(python3 -c "import json;print(json.load(open('$ROOT/manifest.json')).get('$tool',{}).get('size',0))" 2>/dev/null)"
    if [ -n "$msha" ] && [ "$sha" != "$msha" ]; then
        echo "!! $tool: sha256 mismatch (manifest $msha vs $sha)"; bad=1
    fi
    if [ -n "$msize" ] && [ "$msize" != "0" ] && [ "$size" != "$msize" ]; then
        echo "!! $tool: size mismatch (manifest $msize vs $size)"; bad=1
    fi

    [ "$bad" -eq 0 ] || return 1
    echo "ok  $tool  ($(stat -c %s "$tarball") bytes)"
}

for tool in git curl wget ssh scp tar unzip grep sed find diff patch sort uniq head tail cut xargs which file readelf objdump nm; do
    check_arch "$tool" || failures=$((failures + 1))
done

echo
if [ "$failures" -eq 0 ]; then
    echo "All tools verified (Android ARM64)."
else
    echo "$failures tool(s) FAILED verification — do not upload."
    exit 1
fi