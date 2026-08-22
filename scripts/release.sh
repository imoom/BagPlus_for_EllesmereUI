#!/usr/bin/env bash
set -eu

ADDON_NAME="BagPlus_for_EllesmereUI"
ZIP_NAME="${ADDON_NAME}.zip"
TAG_PREFIX="v"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)"
SRC_DIR="${ROOT_DIR}/src/${ADDON_NAME}"
TOC_FILE="${SRC_DIR}/${ADDON_NAME}.toc"
TOC_PATH="src/${ADDON_NAME}/${ADDON_NAME}.toc"

ALLOW_DIRTY=0
CHECK_TAG=1
CREATE_TAG=0
FORCE=0
FETCH_TAGS=0

usage() {
    cat <<USAGE
Usage: scripts/release.sh [options]

Builds releases/<toc-version>/${ZIP_NAME}.

Options:
  --fetch-tags      Fetch remote tags before validating v<toc-version>.
  --tag             Create the expected Git tag if it does not already exist.
  --no-tag-check    Build without requiring HEAD to be tagged v<toc-version>.
  --allow-dirty     Build even when the working tree has uncommitted changes.
  --force           Overwrite an existing release zip.
  -h, --help        Show this help.

Release flow:
  1. Update ${TOC_PATH} and changelog.md.
  2. Commit the release changes.
  3. Run scripts/release.sh --tag.
USAGE
}

die() {
    printf 'release: %s\n' "$*" >&2
    exit 1
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --fetch-tags)
            FETCH_TAGS=1
            ;;
        --tag)
            CREATE_TAG=1
            ;;
        --no-tag-check)
            CHECK_TAG=0
            ;;
        --allow-dirty)
            ALLOW_DIRTY=1
            ;;
        --force)
            FORCE=1
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

cd "$ROOT_DIR"

[ -f "$TOC_FILE" ] || die "missing ${TOC_PATH}"

VERSION="$(awk -F':[[:space:]]*' '/^## Version:/ { print $2; exit }' "$TOC_FILE")"
[ -n "$VERSION" ] || die "could not read ## Version from ${TOC_FILE}"
case "$VERSION" in
    *[!A-Za-z0-9._-]*)
        die "version '${VERSION}' contains characters that are unsafe for paths or tags"
        ;;
esac

EXPECTED_TAG="${TAG_PREFIX}${VERSION}"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a Git work tree"

if [ "$FETCH_TAGS" -eq 1 ]; then
    git fetch --tags --quiet
fi

if [ "$ALLOW_DIRTY" -ne 1 ]; then
    STATUS="$(git status --porcelain --untracked-files=all)"
    [ -z "$STATUS" ] || die "working tree is not clean; commit changes or pass --allow-dirty for a test build"
fi

if [ "$CHECK_TAG" -eq 1 ]; then
    HEAD_COMMIT="$(git rev-parse HEAD)"
    if git rev-parse "${EXPECTED_TAG}^{commit}" >/dev/null 2>&1; then
        TAG_COMMIT="$(git rev-parse "${EXPECTED_TAG}^{commit}")"
        [ "$TAG_COMMIT" = "$HEAD_COMMIT" ] || die "tag ${EXPECTED_TAG} exists but does not point at HEAD"
    else
        if [ "$CREATE_TAG" -eq 1 ]; then
            git tag -a "$EXPECTED_TAG" -m "Release ${VERSION}"
        else
            die "missing tag ${EXPECTED_TAG}; run again with --tag after committing, or use --no-tag-check for a test build"
        fi
    fi
fi

ADDON_FILES="
${ADDON_NAME}.toc
${ADDON_NAME}.lua
README.md
"

ROOT_DOC_FILES="
LICENSE
changelog.md
"

for file in $ADDON_FILES; do
    [ -f "${SRC_DIR}/${file}" ] || die "addon source file is missing: src/${ADDON_NAME}/${file}"
done

for file in $ROOT_DOC_FILES; do
    [ -f "$file" ] || die "package file is missing: $file"
done

RELEASE_DIR="${ROOT_DIR}/releases/${VERSION}"
ZIP_PATH="${RELEASE_DIR}/${ZIP_NAME}"

mkdir -p "$RELEASE_DIR"
if [ -e "$ZIP_PATH" ] && [ "$FORCE" -ne 1 ]; then
    die "${ZIP_PATH} already exists; pass --force to replace it"
fi

STAGING_DIR="$(mktemp -d)"
cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

PACKAGE_DIR="${STAGING_DIR}/${ADDON_NAME}"
mkdir -p "$PACKAGE_DIR"

for file in $ADDON_FILES; do
    cp "${SRC_DIR}/${file}" "${PACKAGE_DIR}/${file}"
done

for file in $ROOT_DOC_FILES; do
    cp "$file" "${PACKAGE_DIR}/${file}"
done

rm -f "$ZIP_PATH"
if command -v zip >/dev/null 2>&1; then
    (
        cd "$STAGING_DIR"
        zip -qr "$ZIP_PATH" "$ADDON_NAME"
    )
elif command -v python3 >/dev/null 2>&1; then
    python3 - "$PACKAGE_DIR" "$ZIP_PATH" "$ADDON_NAME" <<'PY'
import os
import sys
import zipfile

package_dir, zip_path, addon_name = sys.argv[1:4]
with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
    for root, _, files in os.walk(package_dir):
        for name in sorted(files):
            path = os.path.join(root, name)
            rel = os.path.relpath(path, package_dir)
            zf.write(path, os.path.join(addon_name, rel))
PY
else
    die "need either zip or python3 to build the archive"
fi

printf 'Created %s\n' "$ZIP_PATH"
printf 'Version %s\n' "$VERSION"
if [ "$CHECK_TAG" -eq 1 ]; then
    printf 'Git tag %s\n' "$EXPECTED_TAG"
else
    printf 'Git tag check skipped\n'
fi
