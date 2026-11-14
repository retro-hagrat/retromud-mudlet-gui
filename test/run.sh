#!/bin/sh
# Run all unit tests. Needs a lua binary on PATH.
set -eu
cd "$(dirname "$0")/.."
for f in test/*_test.lua; do
    t=$(basename "$f" _test.lua)
    printf "%-18s " "$t"
    lua "$f"
done
