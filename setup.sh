#!/bin/bash
# VPN Automation — one-step setup
# Installs the vpn script, creates desktop apps, and runs credential setup

set -e

echo "=== VPN Automation Setup ==="
echo ""

# 1. Install dependencies
echo "[1/5] Installing dependencies..."
if ! command -v brew &>/dev/null; then
    echo "Homebrew not found. Install it from https://brew.sh/ and re-run this script."
    exit 1
fi
brew install oath-toolkit zbar 2>/dev/null || true

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

# 3. Create desktop apps
echo "[3/5] Creating desktop apps..."

# VPN Connect app
osacompile -o ~/Desktop/"VPN Connect.app" <<'APPLESCRIPT'
on run
    set vpnScript to (POSIX path of (path to home folder)) & ".vpn.sh"

    tell application "Terminal"
        activate
        do script "source " & quoted form of vpnScript & " && vpn up pune"
    end tell
end run
APPLESCRIPT

# VPN Disconnect app
osacompile -o ~/Desktop/"VPN Disconnect.app" <<'APPLESCRIPT'
on run
    do shell script "osascript -e 'tell application \"Viscosity\" to disconnectall'"
    display notification "All VPN connections disconnected" with title "VPN"
end run
APPLESCRIPT

# VPN Status app
osacompile -o ~/Desktop/"VPN Status.app" <<'APPLESCRIPT'
on run
    set vpnScript to (POSIX path of (path to home folder)) & ".vpn.sh"

    tell application "Terminal"
        activate
        do script "source " & quoted form of vpnScript & " && vpn status"
    end tell
end run
APPLESCRIPT

echo "  Created: VPN Connect.app, VPN Disconnect.app, VPN Status.app on Desktop"

# 4. Check Accessibility permissions
echo "[4/5] Checking permissions..."
echo "  Your terminal app needs Accessibility access for auto-fill to work."
echo "  Go to: System Settings > Privacy & Security > Accessibility"
echo "  Add and enable your terminal app (Terminal.app, iTerm2, etc.)"
echo ""

# 5. Run credential setup
echo "[5/5] Credential setup..."
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
