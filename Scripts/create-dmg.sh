#!/usr/bin/env bash
# Creates a distributable DMG from ClipManager.app.
# Requires: create-dmg (brew install create-dmg)

set -euo pipefail

PRODUCT_NAME="ClipManager"
VERSION="${CLIPMANAGER_VERSION:-1.0.0}"
SUFFIX="${DMG_SUFFIX:-}"
OUTPUT_DIR="build"
APP="${OUTPUT_DIR}/${PRODUCT_NAME}.app"
DMG_NAME="${PRODUCT_NAME}-${VERSION}${SUFFIX}.dmg"
DMG_OUT="${OUTPUT_DIR}/${DMG_NAME}"

if ! command -v create-dmg &>/dev/null; then
    echo "Error: create-dmg not found. Run: brew install create-dmg"
    exit 1
fi

[ -d "$APP" ] || { echo "Error: ${APP} not found. Run build-app.sh first."; exit 1; }

echo "→ Creating DMG: ${DMG_NAME}"

VOLICON=""
if [ -f "${OUTPUT_DIR}/AppIcon.icns" ]; then
    VOLICON="--volicon ${OUTPUT_DIR}/AppIcon.icns"
fi

# create-dmg has a flaky AppleScript layout step (Finder error -1728) that
# can abort before the final file is renamed. Retry a few times and always
# verify the final DMG exists.
for attempt in 1 2 3; do
    create-dmg \
        --volname "${PRODUCT_NAME} ${VERSION}" \
        $VOLICON \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 128 \
        --icon "${PRODUCT_NAME}.app" 150 190 \
        --hide-extension "${PRODUCT_NAME}.app" \
        --app-drop-link 450 190 \
        --no-internet-enable \
        "${DMG_OUT}" \
        "$APP" || true

    [ -s "${DMG_OUT}" ] && break
    echo "Attempt ${attempt}: final DMG missing, retrying..."
    rm -f "${OUTPUT_DIR}"/rw.*.dmg
    sleep 2
done

[ -s "${DMG_OUT}" ] || { echo "Error: DMG was not created after 3 attempts."; exit 1; }

echo "✓ DMG: ${DMG_OUT}"
