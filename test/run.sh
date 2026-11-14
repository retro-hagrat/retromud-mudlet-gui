#!/bin/sh
# Run all unit tests. Needs a lua binary on PATH.
set -eu
cd "$(dirname "$0")/.."
lua test/chat_engine_test.lua
lua test/theme_test.lua
