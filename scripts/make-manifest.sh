#!/usr/bin/env bash
# ============================================================================
# make-manifest.sh — regenerate manifest.json + checksums.sha256
# from the built tarballs in <tool>/android-arm64/.
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT/manifest.json"
CHECKSUMS="$ROOT/checksums.sha256"
RELEASE_TAG="${RELEASE_TAG:-tools-v1}"

# Build the manifest using python3 (present on WSL/Ubuntu).
python3 - "$ROOT" "$RELEASE_TAG" <<'PY'
import hashlib, json, os, sys

root, tag = sys.argv[1], sys.argv[2]
tools = [
    "git","curl","wget","ssh","scp","tar","unzip","grep","sed","find","diff",
    "patch","sort","uniq","head","tail","cut","xargs","which","file",
    "readelf","objdump","nm",
]
base = f"https://github.com/MobileStudio-AndroidIDE/StudioShellTools/releases/download/{tag}"
manifest = {}
checksum_lines = []
for tool in tools:
    tarball = os.path.join(root, tool, "android-arm64", f"{tool}-android-arm64.tar.gz")
    if not os.path.isfile(tarball):
        print(f"!! missing {tarball} — skipped")
        continue
    size = os.path.getsize(tarball)
    sha = hashlib.sha256(open(tarball, "rb").read()).hexdigest()
    manifest[tool] = {
        "version": os.environ.get(f"{tool.upper()}_VERSION", "?"),
        "size": size,
        "url": f"{base}/{tool}-android-arm64.tar.gz",
        "sha256": sha,
    }
    checksum_lines.append(f"{sha}  {tool}-android-arm64.tar.gz")

# preserve existing versions when not overridden by env
old = {}
if os.path.isfile(os.path.join(root, "manifest.json")):
    try:
        old = json.load(open(os.path.join(root, "manifest.json")))
    except Exception:
        old = {}
for tool, info in manifest.items():
    if info["version"] == "?" and tool in old:
        info["version"] = old[tool].get("version", "?")

with open(os.path.join(root, "manifest.json"), "w") as f:
    json.dump(manifest, f, indent=2, ensure_ascii=False)
    f.write("\n")
with open(os.path.join(root, "checksums.sha256"), "w") as f:
    f.write("# StudioShellTools SHA-256 checksums\n")
    f.write("\n".join(checksum_lines) + "\n")

print(f"manifest.json: {len(manifest)} tools")
print(f"checksums.sha256: {len(checksum_lines)} files")
PY