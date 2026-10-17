#!/usr/bin/env bash
set -eu

ADDON_NAME="BagPlus_for_EllesmereUI"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)"
SRC_DIR="${ROOT_DIR}/src/${ADDON_NAME}"
CLIENT="retail"
CONFIG_FILE=""
SAVE_PATH=0

MODE="copy"
DRY_RUN=0
ADDONS_DIR="${WOW_ADDONS_DIR:-}"

usage() {
    cat <<USAGE
Usage: scripts/install-dev.sh [options]

Copies the development addon from src/${ADDON_NAME}/ into your World of Warcraft
Interface/AddOns folder for local testing.

Options:
  --client NAME      retail (default) or forever. Each has its own saved path.
  --addons-dir PATH  WoW Interface/AddOns folder. Windows paths are accepted in WSL.
  --save-path        Save the selected path for subsequent installs of this client.
  --link             Replace the addon folder with a symlink to src/${ADDON_NAME}.
  --copy             Copy files instead of linking. This is the default.
  --dry-run          Print what would happen without changing files.
  -h, --help         Show this help.

Configuration:
  Retail: WOW_RETAIL_ADDONS_DIR or .wow-addons-dir (existing setting).
  Forever: WOW_FOREVER_ADDONS_DIR or .wow-addons-dir.forever.
  --addons-dir overrides WOW_ADDONS_DIR, which overrides client settings.
  Only retail auto-detects a folder. Forever requires an explicit setting.
  Both config files are gitignored. Copy mode is recommended for Windows/WSL.
USAGE
}

die() {
    printf 'install-dev: %s\n' "$*" >&2
    exit 1
}

normalize_path() {
    local path="$1"
    case "$path" in
        [A-Za-z]:*|*\\*)
            if command -v wslpath >/dev/null 2>&1; then
                wslpath -u "$path"
            else
                printf '%s\n' "$path"
            fi
            ;;
        *)
            printf '%s\n' "$path"
            ;;
    esac
}

detect_addons_dir() {
    if [ -n "$ADDONS_DIR" ]; then
        normalize_path "$ADDONS_DIR"
        return 0
    fi

    local client_path=""
    case "$CLIENT" in
        retail) client_path="${WOW_RETAIL_ADDONS_DIR:-}" ;;
        forever) client_path="${WOW_FOREVER_ADDONS_DIR:-}" ;;
    esac
    if [ -n "$client_path" ]; then
        normalize_path "$client_path"
        return 0
    fi

    if [ -f "$CONFIG_FILE" ]; then
        ADDONS_DIR="$(sed -n '1s/[[:space:]]*$//p' "$CONFIG_FILE")"
        if [ -n "$ADDONS_DIR" ]; then
            normalize_path "$ADDONS_DIR"
            return 0
        fi
    fi

    [ "$CLIENT" = "retail" ] || return 1

    for candidate in \
        "/mnt/c/Program Files (x86)/World of Warcraft/_retail_/Interface/AddOns" \
        "/mnt/c/Program Files/World of Warcraft/_retail_/Interface/AddOns" \
        "/mnt/c/Games/World of Warcraft/_retail_/Interface/AddOns" \
        "/mnt/d/Games/World of Warcraft/_retail_/Interface/AddOns"
    do
        if [ -d "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --client)
            [ "$#" -ge 2 ] || die "--client requires retail or forever"
            CLIENT="$2"
            shift
            ;;
        --client=*)
            CLIENT="${1#--client=}"
            ;;
        --save-path)
            SAVE_PATH=1
            ;;
        --addons-dir)
            [ "$#" -ge 2 ] || die "--addons-dir requires a path"
            ADDONS_DIR="$2"
            shift
            ;;
        --addons-dir=*)
            ADDONS_DIR="${1#--addons-dir=}"
            ;;
        --link)
            MODE="link"
            ;;
        --copy)
            MODE="copy"
            ;;
        --dry-run)
            DRY_RUN=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown option: $1"
            ;;
    esac
    shift
done

case "$CLIENT" in
    retail) CONFIG_FILE="${ROOT_DIR}/.wow-addons-dir" ;;
    forever) CONFIG_FILE="${ROOT_DIR}/.wow-addons-dir.forever" ;;
    *) die "unknown client: $CLIENT (use retail or forever)" ;;
esac

[ -d "$SRC_DIR" ] || die "missing source addon folder: src/${ADDON_NAME}"
[ -f "${SRC_DIR}/${ADDON_NAME}.toc" ] || die "missing addon toc: src/${ADDON_NAME}/${ADDON_NAME}.toc"

if ! ADDONS_DIR="$(detect_addons_dir)"; then
    die "could not find the $CLIENT AddOns folder. Pass --addons-dir, set the client environment variable, or create $CONFIG_FILE"
fi

[ -d "$ADDONS_DIR" ] || die "AddOns folder does not exist: ${ADDONS_DIR}"

ADDONS_DIR="$(CDPATH= cd -- "$ADDONS_DIR" && pwd -P)"
TARGET_DIR="${ADDONS_DIR}/${ADDON_NAME}"
[ "$TARGET_DIR" != "$SRC_DIR" ] || die "target must not be the source addon folder"
if [ -d "$TARGET_DIR" ] && [ ! -L "$TARGET_DIR" ]; then
    target_real="$(CDPATH= cd -- "$TARGET_DIR" && pwd -P)"
    case "${ROOT_DIR}/" in
        "${target_real}/"*) die "target must not contain the repository" ;;
    esac
fi

printf 'Client: %s\n' "$CLIENT"
printf 'Source: %s\n' "$SRC_DIR"
printf 'Target: %s\n' "$TARGET_DIR"
printf 'Mode: %s\n' "$MODE"

if [ "$DRY_RUN" -eq 1 ]; then
    exit 0
fi

case "$MODE" in
    copy)
        if [ -L "$TARGET_DIR" ]; then
            rm "$TARGET_DIR"
        fi
        mkdir -p "$TARGET_DIR"
        if command -v rsync >/dev/null 2>&1; then
            rsync -a --delete "${SRC_DIR}/" "${TARGET_DIR}/"
        else
            rm -rf "$TARGET_DIR"
            mkdir -p "$TARGET_DIR"
            cp -R "${SRC_DIR}/." "$TARGET_DIR/"
        fi
        ;;
    link)
        rm -rf "$TARGET_DIR"
        ln -s "$SRC_DIR" "$TARGET_DIR"
        ;;
    *)
        die "unknown install mode: ${MODE}"
        ;;
esac

if [ "$SAVE_PATH" -eq 1 ]; then
    printf '%s\n' "$ADDONS_DIR" > "$CONFIG_FILE"
    printf 'Saved path: %s\n' "$CONFIG_FILE"
fi

printf 'Installed %s for local testing.\n' "$ADDON_NAME"
