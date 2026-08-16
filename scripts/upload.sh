#!/usr/bin/env bash
# ============================================================================
# upload.sh — publish StudioShellTools.
#
#   1. run verify.sh (fail-fast on arch/checksum problems)
#   2. regenerate manifest.json + checksums.sha256 (make-manifest.sh)
#   3. upload every <tool>/android-arm64/*.tar.gz to GitHub Release "$RELEASE_TAG"
#   4. commit + push manifest / checksums / scripts to the repository
#
# Requires: gh CLI authenticated, git repo with a remote.
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_TAG="${RELEASE_TAG:-tools-v1}"
REPO="${REPO:-MobileStudio-AndroidIDE/StudioShellTools}"

cd "$ROOT"

echo "==> verifying..."
"$ROOT/scripts/verify.sh"

echo "==> regenerating manifest + checksums..."
"$ROOT/scripts/make-manifest.sh"

echo "==> ensuring release $RELEASE_TAG exists..."
gh release view "$RELEASE_TAG" --repo "$REPO" >/dev/null 2>&1 ||
    gh release create "$RELEASE_TAG" --repo "$REPO" --title "StudioShellTools $RELEASE_TAG" --notes "Android ARM64 development tools for MobileStudio Shell."

echo "==> uploading tarballs..."
TARBALLS=(git/android-arm64/git-android-arm64.tar.gz curl/android-arm64/curl-android-arm64.tar.gz wget/android-arm64/wget-android-arm64.tar.gz ssh/android-arm64/ssh-android-arm64.tar.gz scp/android-arm64/scp-android-arm64.tar.gz tar/android-arm64/tar-android-arm64.tar.gz unzip/android-arm64/unzip-android-arm64.tar.gz grep/android-arm64/grep-android-arm64.tar.gz sed/android-arm64/sed-android-arm64.tar.gz find/android-arm64/find-android-arm64.tar.gz diff/android-arm64/diff-android-arm64.tar.gz patch/android-arm64/patch-android-arm64.tar.gz sort/android-arm64/sort-android-arm64.tar.gz uniq/android-arm64/uniq-android-arm64.tar.gz head/android-arm64/head-android-arm64.tar.gz tail/android-arm64/tail-android-arm64.tar.gz cut/android-arm64/cut-android-arm64.tar.gz xargs/android-arm64/xargs-android-arm64.tar.gz which/android-arm64/which-android-arm64.tar.gz file/android-arm64/file-android-arm64.tar.gz readelf/android-arm64/readelf-android-arm64.tar.gz objdump/android-arm64/objdump-android-arm64.tar.gz nm/android-arm64/nm-android-arm64.tar.gz)
EXISTING=()
for t in "${TARBALLS[@]}"; do
    [ -f "$t" ] && EXISTING+=("$t")
done
if [ "${#EXISTING[@]}" -gt 0 ]; then
    gh release upload "$RELEASE_TAG" "${EXISTING[@]}" --repo "$REPO" --clobber
else
    echo "!! no tarballs found — run scripts/build-all.sh first"
fi

echo "==> committing metadata..."
git add manifest.json checksums.sha256 README.md scripts
git commit -m "Update StudioShellTools manifest + checksums ($RELEASE_TAG)" || true
git push

echo
echo "Done. Release: https://github.com/$REPO/releases/tag/$RELEASE_TAG"