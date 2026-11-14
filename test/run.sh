#!/bin/sh
# Run all unit tests. Needs a lua binary on PATH.
set -eu
cd "$(dirname "$0")/.."
for t in chat_engine theme theme_apply layout_calc vitals_parser settings lifecycle statusbar_format; do
    printf "%-18s " "$t"
    lua "test/${t}_test.lua"
done
