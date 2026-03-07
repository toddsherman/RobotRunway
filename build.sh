#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────────────────
# RobotRunway Build Script
# ─────────────────────────────────────────────────────────

APP_NAME="RobotRunway"
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"
SRC_DIR="."

echo "🔨 Building ${APP_NAME}..."

# Clean
rm -rf "${BUILD_DIR}"
mkdir -p "${MACOS}" "${RESOURCES}"

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    TARGET="arm64-apple-macos13.0"
elif [ "$ARCH" = "x86_64" ]; then
    TARGET="x86_64-apple-macos13.0"
else
    echo "❌ Unknown architecture: $ARCH"
    exit 1
fi
echo "   Architecture: ${ARCH} → target ${TARGET}"

# Collect all Swift source files
SOURCES=$(find "${SRC_DIR}" -maxdepth 1 -name "*.swift" | sort)
echo "   Sources:"
for src in $SOURCES; do
    echo "     - ${src}"
done

# Compile
swiftc \
    -O \
    -target "${TARGET}" \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -framework Cocoa \
    -framework IOKit \
    -o "${MACOS}/${APP_NAME}" \
    $SOURCES

# Copy Info.plist
cp "${SRC_DIR}/Info.plist" "${CONTENTS}/Info.plist"

# Copy icon resources
cp "${SRC_DIR}/resources/robot-sleep.png" "${RESOURCES}/robot-sleep.png"
cp "${SRC_DIR}/resources/robot-wake-1.png" "${RESOURCES}/robot-wake-1.png"
cp "${SRC_DIR}/resources/robot-wake-2.png" "${RESOURCES}/robot-wake-2.png"

echo ""
echo "✅ Built: ${APP_BUNDLE}"
echo ""
echo "To install:"
echo "  cp -r ${APP_BUNDLE} /Applications/"
echo ""
echo "To run:"
echo "  open ${APP_BUNDLE}"
echo ""
echo "To launch at login:"
echo "  System Settings → General → Login Items → add RobotRunway"
