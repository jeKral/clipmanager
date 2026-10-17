#!/usr/bin/env bash
# Build ClipManager.app bundle from Swift Package Manager output.
# Usage: ./Scripts/build-app.sh [debug|release] [arm64|x86_64|universal]

set -euo pipefail

CONFIG="${1:-release}"
ARCH="${2:-universal}"
PRODUCT_NAME="ClipManager"
BUNDLE_ID="io.clipmanager.app"
PLIST_SRC="Sources/ClipManager/Resources/Info.plist"
ENTITLEMENTS="Sources/ClipManager/Resources/ClipManager.entitlements"
OUTPUT_DIR="build"
APP_DIR="${OUTPUT_DIR}/${PRODUCT_NAME}.app/Contents"

echo "→ Building ${PRODUCT_NAME} (config=${CONFIG}, arch=${ARCH})"

# ---- License secret (build-time) ----
bash "$(dirname "$0")/inject-secret.sh"

# ---- Build binary ----
if [ "$ARCH" = "universal" ]; then
    swift build -c "$CONFIG" --arch arm64 --arch x86_64
    BINARY=".build/apple/Products/${CONFIG^}/${PRODUCT_NAME}"
elif [ "$ARCH" = "arm64" ]; then
    swift build -c "$CONFIG" --arch arm64
    BINARY=".build/arm64-apple-macosx/${CONFIG}/${PRODUCT_NAME}"
else
    swift build -c "$CONFIG" --arch x86_64
    BINARY=".build/x86_64-apple-macosx/${CONFIG}/${PRODUCT_NAME}"
fi

# ---- Assemble .app bundle ----
rm -rf "${OUTPUT_DIR}/${PRODUCT_NAME}.app"
mkdir -p "${APP_DIR}/MacOS"
mkdir -p "${APP_DIR}/Resources"

# Binary
cp "$BINARY" "${APP_DIR}/MacOS/${PRODUCT_NAME}"

# Info.plist
cp "$PLIST_SRC" "${APP_DIR}/Info.plist"

# App icon (if built)
if [ -f "${OUTPUT_DIR}/AppIcon.icns" ]; then
    cp "${OUTPUT_DIR}/AppIcon.icns" "${APP_DIR}/Resources/AppIcon.icns"
fi

echo "→ .app bundle assembled at ${OUTPUT_DIR}/${PRODUCT_NAME}.app"

# ---- Remove extended attributes (common issue on external/network volumes) ----
xattr -cr "${OUTPUT_DIR}/${PRODUCT_NAME}.app" 2>/dev/null || true

# ---- Code signing ----
IDENTITY="${CODESIGN_IDENTITY:-}"

if [ -n "$IDENTITY" ]; then
    echo "→ Signing with identity: ${IDENTITY}"
    codesign \
        --force \
        --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --sign "$IDENTITY" \
        --timestamp \
        "${OUTPUT_DIR}/${PRODUCT_NAME}.app"
    echo "→ Signed successfully"
else
    # Ad-hoc sign for local testing
    echo "→ No CODESIGN_IDENTITY set — using ad-hoc signature"
    codesign \
        --force \
        --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --sign "-" \
        "${OUTPUT_DIR}/${PRODUCT_NAME}.app"
fi

echo "✓ Build complete: ${OUTPUT_DIR}/${PRODUCT_NAME}.app"
