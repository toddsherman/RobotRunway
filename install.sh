#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────────────────
# RobotRunway Installer
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/toddsherman/RobotRunway/main/install.sh | bash
#
# Downloads a pre-built universal binary from GitHub Releases.
# Falls back to building from source if no release is available.
# ─────────────────────────────────────────────────────────

APP_NAME="RobotRunway"
INSTALL_DIR="/Applications"
REPO="toddsherman/RobotRunway"
APP_PATH="${INSTALL_DIR}/${APP_NAME}.app"

info()  { echo "==> $*"; }
warn()  { echo "==> $*"; }
error() { echo "==> ERROR: $*"; exit 1; }

# Clean up temp directory on exit
TMPDIR_INSTALL=""
cleanup() {
    if [ -n "${TMPDIR_INSTALL}" ] && [ -d "${TMPDIR_INSTALL}" ]; then
        rm -rf "${TMPDIR_INSTALL}"
    fi
}
trap cleanup EXIT

# ─── Check for existing installation ───────────────────
if [ -d "${APP_PATH}" ]; then
    warn "${APP_NAME} is already installed. This will replace it."
    if [ -t 0 ]; then
        read -r -p "    Continue? [Y/n] " response
        case "${response}" in
            [nN]*) echo "Cancelled."; exit 0 ;;
        esac
    fi
fi

# ─── Try downloading pre-built release ─────────────────
install_from_release() {
    info "Checking for pre-built release..."

    RELEASE_URL=$(curl -fsSL \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null \
        | grep -o '"browser_download_url": *"[^"]*\.zip"' \
        | head -1 \
        | sed 's/"browser_download_url": *"//;s/"$//' \
    ) || return 1

    if [ -z "${RELEASE_URL}" ]; then
        return 1
    fi

    info "Downloading ${APP_NAME}..."
    TMPDIR_INSTALL=$(mktemp -d)

    curl -fsSL -o "${TMPDIR_INSTALL}/${APP_NAME}.zip" "${RELEASE_URL}" || return 1

    info "Extracting..."
    unzip -q "${TMPDIR_INSTALL}/${APP_NAME}.zip" -d "${TMPDIR_INSTALL}" || return 1

    if [ ! -d "${TMPDIR_INSTALL}/${APP_NAME}.app" ]; then
        return 1
    fi

    return 0
}

# ─── Build from source (fallback) ─────────────────────
install_from_source() {
    info "Building from source..."

    if ! xcode-select -p &>/dev/null; then
        info "Installing Xcode Command Line Tools..."
        xcode-select --install
        error "Please re-run this script after Xcode Command Line Tools finish installing."
    fi

    if ! command -v swiftc &>/dev/null; then
        error "swiftc not found. Please install Xcode or Xcode Command Line Tools."
    fi

    TMPDIR_INSTALL=$(mktemp -d)

    info "Cloning repository..."
    git clone --depth 1 "https://github.com/${REPO}.git" "${TMPDIR_INSTALL}/repo" || \
        error "Failed to clone repository."

    info "Compiling..."
    cd "${TMPDIR_INSTALL}/repo"
    bash build.sh || error "Build failed."

    cp -r "build/${APP_NAME}.app" "${TMPDIR_INSTALL}/${APP_NAME}.app"
    return 0
}

# ─── Main ──────────────────────────────────────────────

if install_from_release; then
    info "Downloaded pre-built release."
else
    warn "No pre-built release available. Building from source..."
    install_from_source
fi

# Install
info "Installing to ${INSTALL_DIR}..."
[ -d "${APP_PATH}" ] && rm -rf "${APP_PATH}"
cp -r "${TMPDIR_INSTALL}/${APP_NAME}.app" "${APP_PATH}"

# Remove quarantine attribute (unsigned app downloaded from internet)
xattr -cr "${APP_PATH}" 2>/dev/null || true

echo ""
echo "✅ Installed ${APP_NAME} to ${APP_PATH}"
echo ""
echo "To run:"
echo "  open ${APP_PATH}"
echo ""
echo "To launch at login:"
echo "  System Settings → General → Login Items → add ${APP_NAME}"
echo ""
