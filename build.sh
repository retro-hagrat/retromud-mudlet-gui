#!/bin/sh
# Build the package with Muddler and copy it to dist/ (committed, for non-GitHub users).
set -eu
cd "$(dirname "$0")"
command -v muddle >/dev/null || { echo "muddle not found on PATH. Get it from https://github.com/demonnic/muddler/releases" >&2; exit 1; }
muddle
cp build/retromud-gui.mpackage dist/retromud-gui.mpackage
echo "Built dist/retromud-gui.mpackage"
