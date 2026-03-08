#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────────────────
# RobotRunway Test Runner
# Compiles and runs XCTest tests using swiftc directly
# ─────────────────────────────────────────────────────────

APP_NAME="RobotRunwayTests"
BUILD_DIR="build/tests"
SRC_DIR="."
TEST_DIR="Tests"

echo "🧪 Building ${APP_NAME}..."

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

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

SDK_PATH=$(xcrun --sdk macosx --show-sdk-path)

# Find XCTest.framework and Swift module — prefers Xcode.app, falls back to CommandLineTools
PLATFORM_DIR=""
if [ -d "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform" ]; then
    PLATFORM_DIR="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform"
else
    XCODE_PATH=$(xcode-select -p)
    PLATFORM_DIR="${XCODE_PATH}/Platforms/MacOSX.platform"
fi

XCTEST_FRAMEWORK="${PLATFORM_DIR}/Developer/Library/Frameworks"
XCTEST_SWIFT_LIB="${PLATFORM_DIR}/Developer/usr/lib"

if [ ! -d "${XCTEST_FRAMEWORK}/XCTest.framework" ]; then
    echo "❌ XCTest.framework not found. Install Xcode."
    exit 1
fi
if [ ! -d "${XCTEST_SWIFT_LIB}/XCTest.swiftmodule" ]; then
    echo "❌ XCTest.swiftmodule not found at ${XCTEST_SWIFT_LIB}. Install Xcode."
    exit 1
fi
echo "   XCTest framework: ${XCTEST_FRAMEWORK}"
echo "   XCTest Swift lib: ${XCTEST_SWIFT_LIB}"

# Source files to include in tests (exclude main.swift and UI-only controllers)
TESTABLE_SOURCES=(
    "${SRC_DIR}/ProcessUtils.swift"
    "${SRC_DIR}/ActivityMonitor.swift"
    "${SRC_DIR}/HostApp.swift"
    "${SRC_DIR}/SleepManager.swift"
    "${SRC_DIR}/Logging.swift"
)

# Test source files
TEST_SOURCES=$(find "${TEST_DIR}" -name "*.swift" | sort)

echo "   Testable sources:"
for src in "${TESTABLE_SOURCES[@]}"; do
    echo "     - ${src}"
done
echo "   Test sources:"
for src in $TEST_SOURCES; do
    echo "     - ${src}"
done

# Compile
swiftc \
    -target "${TARGET}" \
    -sdk "${SDK_PATH}" \
    -F "${XCTEST_FRAMEWORK}" \
    -I "${XCTEST_SWIFT_LIB}" \
    -L "${XCTEST_SWIFT_LIB}" \
    -lXCTestSwiftSupport \
    -framework Cocoa \
    -framework IOKit \
    -framework XCTest \
    -Xlinker -rpath -Xlinker "${XCTEST_FRAMEWORK}" \
    -Xlinker -rpath -Xlinker "${XCTEST_SWIFT_LIB}" \
    -o "${BUILD_DIR}/${APP_NAME}" \
    "${TESTABLE_SOURCES[@]}" \
    $TEST_SOURCES

echo ""
echo "🏃 Running tests..."
echo ""

# Run tests
"${BUILD_DIR}/${APP_NAME}"
