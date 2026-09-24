#!/bin/bash
# VPN Automation — one-step setup
# Installs the vpn script, creates desktop shortcuts, and runs credential setup

set -e

echo "=== VPN Automation Setup ==="
echo ""

# 0. Check for Xcode Command Line Tools (needed for git, brew, etc.)
if ! xcode-select -p &>/dev/null; then
    echo "Xcode Command Line Tools not found. Installing..."
    xcode-select --install
    echo ""
    echo "  A popup will appear — click Install and wait for it to finish."
    echo "  Then re-run this script: bash /tmp/vpn-automation/setup.sh"
    exit 1
fi

# 1. Install dependencies
echo "[1/6] Installing dependencies..."
if ! command -v brew &>/dev/null; then
    echo "Homebrew not found. Install it from https://brew.sh/ and re-run this script."
    exit 1
fi
brew install oath-toolkit zbar || true

# 2. Copy vpn script
echo "[2/6] Installing vpn.sh..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cp "$SCRIPT_DIR/vpn.sh" ~/.vpn.sh

# Add to shell config if not already there
SHELL_RC=""
if [ -n "$ZSH_VERSION" ] || [ "$SHELL" = "/bin/zsh" ]; then
    SHELL_RC="$HOME/.zshrc"
else
    SHELL_RC="$HOME/.bashrc"
fi

if ! grep -q 'source ~/.vpn.sh' "$SHELL_RC" 2>/dev/null; then
    echo 'source ~/.vpn.sh' >> "$SHELL_RC"
    echo "  Added 'source ~/.vpn.sh' to $SHELL_RC"
else
    echo "  Already in $SHELL_RC"
fi

# 3. Create desktop shortcuts
echo "[3/6] Creating desktop shortcuts..."
echo ""
echo "  Available VPN connections:"
source ~/.vpn.sh
vpn list 2>/dev/null
echo ""
printf "  Default connection name for desktop shortcut [pune]: "
read -r default_conn
default_conn="${default_conn:-pune}"

cp "$SCRIPT_DIR/VPN Connect.command" ~/Desktop/
cp "$SCRIPT_DIR/VPN Disconnect.command" ~/Desktop/
cp "$SCRIPT_DIR/VPN Status.command" ~/Desktop/
chmod +x ~/Desktop/"VPN Connect.command" ~/Desktop/"VPN Disconnect.command" ~/Desktop/"VPN Status.command"

if ! grep -q 'VPN_DEFAULT_CONNECTION' "$SHELL_RC" 2>/dev/null; then
    echo "export VPN_DEFAULT_CONNECTION=\"$default_conn\"" >> "$SHELL_RC"
fi

echo "  Created: VPN Connect, VPN Disconnect, VPN Status on Desktop"
echo "  Default connection: $default_conn"

# 4. Check Accessibility permissions
echo "[4/6] Checking permissions..."
echo "  Your terminal app needs Accessibility access for auto-fill to work."
echo "  Go to: System Settings > Privacy & Security > Accessibility"
echo "  Add and enable your terminal app (Terminal.app, iTerm2, etc.)"
echo ""

# 5. Run credential setup
echo "[5/6] Credential setup..."
echo ""
echo "  Have your QR code image ready (download from your identity management portal)."
echo ""
source ~/.vpn.sh
set +e
_vpn_setup
set -e

# 6. Set desktop icons
echo "[6/6] Setting desktop icons..."
if command -v fileicon &>/dev/null; then
    ICON_DIR="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources"
    fileicon set ~/Desktop/"VPN Connect.command" "$ICON_DIR/ConnectToIcon.icns" 2>/dev/null
    fileicon set ~/Desktop/"VPN Disconnect.command" "$ICON_DIR/LockedIcon.icns" 2>/dev/null
    fileicon set ~/Desktop/"VPN Status.command" "$ICON_DIR/GenericNetworkIcon.icns" 2>/dev/null
    echo "  Desktop icons set."
else
    brew install fileicon 2>/dev/null && {
        ICON_DIR="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources"
        fileicon set ~/Desktop/"VPN Connect.command" "$ICON_DIR/ConnectToIcon.icns" 2>/dev/null
        fileicon set ~/Desktop/"VPN Disconnect.command" "$ICON_DIR/LockedIcon.icns" 2>/dev/null
        fileicon set ~/Desktop/"VPN Status.command" "$ICON_DIR/GenericNetworkIcon.icns" 2>/dev/null
        echo "  Desktop icons set."
    } || echo "  Skipped icons (fileicon not available)."
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "You can now:"
echo "  - Double-click 'VPN Connect' on your Desktop to connect"
echo "  - Double-click 'VPN Disconnect' to disconnect"
echo "  - Double-click 'VPN Status' to check connection status"
echo "  - Or use the terminal: vpn up pune / vpn down / vpn status"
