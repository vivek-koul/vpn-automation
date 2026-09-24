#!/bin/bash
# VPN Automation — one-step setup
# Installs the vpn script, creates desktop shortcuts, and runs credential setup

set -e

echo "=== VPN Automation Setup ==="
echo ""

# 1. Install dependencies
echo "[1/5] Installing dependencies..."
if ! command -v brew &>/dev/null; then
    echo "Homebrew not found. Install it from https://brew.sh/ and re-run this script."
    exit 1
fi
brew install oath-toolkit zbar || true

# 2. Copy vpn script
echo "[2/5] Installing vpn.sh..."
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
echo "[3/5] Creating desktop shortcuts..."
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
echo "[4/5] Checking permissions..."
echo "  Your terminal app needs Accessibility access for auto-fill to work."
echo "  Go to: System Settings > Privacy & Security > Accessibility"
echo "  Add and enable your terminal app (Terminal.app, iTerm2, etc.)"
echo ""

# 5. Run credential setup
echo "[5/5] Credential setup..."
echo ""
echo "  You'll need your VPN credentials. To get your OTP secret:"
echo "    1. Download your OTP QR code image from your identity management portal"
echo "    2. Run: zbarimg --quiet --raw ~/Downloads/QR.png"
echo "    3. Copy the 'secret=' value from the output"
echo "    4. The 'counter=' value is your HOTP counter (use as-is for a fresh QR code)"
echo ""
echo "  Auth mode: choose 'combined' (default) — it concatenates password+OTP into one field."
echo ""
source ~/.vpn.sh
_vpn_setup

echo ""
echo "=== Setup Complete ==="
echo ""
echo "You can now:"
echo "  - Double-click 'VPN Connect' on your Desktop to connect"
echo "  - Double-click 'VPN Disconnect' to disconnect"
echo "  - Double-click 'VPN Status' to check connection status"
echo "  - Or use the terminal: vpn up pune / vpn down / vpn status"
