#!/usr/bin/env bash
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)"
ADDON_LUA="${ROOT_DIR}/src/BagPlus_for_EllesmereUI/BagPlus_for_EllesmereUI.lua"

cd "$ROOT_DIR"

bash -n scripts/release.sh scripts/test.sh

if command -v luac >/dev/null 2>&1; then
    luac -p "$ADDON_LUA"
elif command -v lua >/dev/null 2>&1; then
    lua -e "assert(loadfile(...))" "$ADDON_LUA"
else
    printf 'test: need lua or luac on PATH\n' >&2
    exit 1
fi

if ! command -v lua >/dev/null 2>&1; then
    printf 'test: need lua on PATH for runtime tests\n' >&2
    exit 1
fi

lua tests/run.lua
