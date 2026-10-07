#!/usr/bin/env bash
# ============================================================================
# make-checksums.sh — regenerate checksums.sha256 from every built
# <tool>/android-arm64/<tool>-android-arm64.tar.gz.
#
# The app derives the tool list, URLs and versions from the GitHub Release
# assets themselves (no manifest.json): tarball names provide the tools,
# this file provides their SHA-256, and the release tag is the version.
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKSUMS="$ROOT/checksums.sha256"

shopt -s nullglob
tarballs=("$ROOT"/*/android-arm64/*-android-arm64.tar.gz)
if [ "${#tarballs[@]}" -eq 0 ]; then
    echo "!! no tarballs found — run scripts/build-all.sh first"
    exit 1
fi

{
    echo "# StudioShellTools — Android ARM64 CLI tools for MobileStudio Shell"
    echo "# Format: <sha256>  <tool>-android-arm64.tar.gz"
    for t in "${tarballs[@]}"; do
        printf '%s  %s\n' "$(sha256sum "$t" | cut -d' ' -f1)" "$(basename "$t")"
    done
} > "$CHECKSUMS"

echo "checksums.sha256: ${#tarballs[@]} tarballs"
