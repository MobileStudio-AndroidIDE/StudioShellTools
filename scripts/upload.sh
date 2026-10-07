#!/usr/bin/env bash
# ============================================================================
# upload.sh — publish StudioShellTools.
#
#   1. regenerate checksums.sha256 from every built tarball
#   2. run verify.sh (fail-fast on arch/checksum problems)
#   3. upload every <tool>/android-arm64/*.tar.gz + checksums.sha256 to the
#      GitHub Release "$RELEASE_TAG"
#   4. commit + push checksums / README / scripts to the repository
#
# The repository itself tracks no binaries and no manifest.json — the app
# derives the tool list straight from the release assets (see StudioToolsIndex).
#
# Requires: gh CLI authenticated, git repo with a remote.
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_TAG="${RELEASE_TAG:-tools-v1}"
REPO="${REPO:-MobileStudio-AndroidIDE/StudioShellTools}"

cd "$ROOT"

echo "==> regenerating checksums..."
"$ROOT/scripts/make-checksums.sh"

echo "==> verifying..."
"$ROOT/scripts/verify.sh"

echo "==> ensuring release $RELEASE_TAG exists..."
gh release view "$RELEASE_TAG" --repo "$REPO" >/dev/null 2>&1 ||
    gh release create "$RELEASE_TAG" --repo "$REPO" --title "StudioShellTools $RELEASE_TAG" --notes "Android ARM64 development tools for MobileStudio Shell."

echo "==> uploading tarballs..."
shopt -s nullglob
TARBALLS=("$ROOT"/*/android-arm64/*-android-arm64.tar.gz)
if [ "${#TARBALLS[@]}" -eq 0 ]; then
    echo "!! no tarballs found — run scripts/build-all.sh first"
    exit 1
fi
gh release upload "$RELEASE_TAG" "${TARBALLS[@]}" "$ROOT/checksums.sha256" --repo "$REPO" --clobber

echo "==> committing metadata..."
git add checksums.sha256 README.md scripts
git commit -m "Update StudioShellTools checksums ($RELEASE_TAG)" || true
git push

echo
echo "Done. Release: https://github.com/$REPO/releases/tag/$RELEASE_TAG"
