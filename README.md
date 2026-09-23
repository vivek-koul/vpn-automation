# VPN CLI Automation — Setup Guide

Automate VPN connections from the terminal. Zero manual password/OTP entry.
Uses Viscosity + AppleScript UI scripting + macOS Keychain + auto-generated HOTP codes.

## How It Works

Viscosity's proprietary OpenVPN binary is required by certain VPN servers — standard `openvpn` CLI fails authentication. This automation:
1. Tells Viscosity to connect via AppleScript
2. Waits for the auth dialog to appear
3. Auto-fills password+OTP using UI scripting
4. Clicks OK

## Prerequisites

- macOS with [Homebrew](https://brew.sh/) installed
- [Viscosity](https://www.sparklabs.com/viscosity/) installed and configured with your VPN connections
- Your VPN username, password, and OTP QR code image
- Terminal (or your terminal app) must have **Accessibility** permissions (see Step 7)

## Step 1: Install Dependencies

```bash
brew install oath-toolkit zbar
```

- `oath-toolkit` — generates 6-digit HOTP codes
- `zbar` — decodes QR codes to extract your HOTP secret

## Step 2: Clone and Install the Script

```bash
git clone https://github.com/vivek-koul/vpn-automation.git /tmp/vpn-automation
cp /tmp/vpn-automation/vpn.sh ~/.vpn.sh
```

## Step 3: Source the Script in Your Shell

For bash:
```bash
echo 'source ~/.vpn.sh' >> ~/.bashrc
source ~/.bashrc
```

For zsh:
```bash
echo 'source ~/.vpn.sh' >> ~/.zshrc
source ~/.zshrc
```

## Step 4: Extract Your HOTP Secret from the QR Code

Save your OTP QR code image as `~/Downloads/QR.png`, then:

```bash
zbarimg --quiet --raw ~/Downloads/QR.png
```

This prints a URI like:
```
otpauth://hotp/OATH12345678?secret=ABCDEFGHIJK...&counter=1&digits=6&issuer=YourOrg
```

Note both the `secret=` value and the **`counter=`** value. You'll need them in Step 6.

## Step 5: Find Your Current HOTP Counter

> **Skip this step if you just generated a fresh QR code.** Use the `counter=` value from Step 4 directly.

If you've been using the token from your phone authenticator, the counter on the server has advanced beyond the QR code's initial value. To find your current counter:

1. Open your authenticator app and note the current 6-digit code for your VPN token
2. Run:

```bash
SECRET="YOUR_SECRET_FROM_STEP_4"
TARGET="THE_6_DIGIT_CODE_FROM_YOUR_PHONE"
for i in $(seq 0 10000); do
    code=$(oathtool --hotp -b -c "$i" "$SECRET" 2>/dev/null)
    if [ "$code" = "$TARGET" ]; then
        echo "Counter match: $i"
        break
    fi
done
```

Your next unused counter = that number + 1.

## Step 6: Store Credentials in Keychain

You can use the interactive setup:

```bash
vpn setup
```

Or set each value manually:

```bash
# Username (your Kerberos ID)
security add-generic-password -a "viscosity-vpn" -s "vpn-username" -w "YOUR_USERNAME"

# Password (hidden input — will not echo to screen)
read -rsp "VPN Password: " p && security add-generic-password -a "viscosity-vpn" -s "vpn-password" -w "$p" && unset p && echo ""

# HOTP secret (from Step 4)
security add-generic-password -a "viscosity-vpn" -s "vpn-totp-secret" -w "YOUR_HOTP_SECRET"

# HOTP counter (from Step 4 or Step 5)
security add-generic-password -a "viscosity-vpn" -s "vpn-hotp-counter" -w "COUNTER_VALUE"

# Auth mode: "combined" = password+OTP in one field
security add-generic-password -a "viscosity-vpn" -s "vpn-auth-mode" -w "combined"
```

**Auth modes:**
- `combined` — password and OTP are concatenated into a single string (e.g., `MyPassword123456`). This is the most common mode.
- `separate` — only the password is sent in the auth field. Use this if combined mode fails.

## Step 7: Grant Accessibility Access

The automation fills Viscosity's auth dialog via macOS UI scripting, which requires Accessibility permissions.

1. Open **System Settings** > **Privacy & Security** > **Accessibility**
2. Click **+** and add your terminal app (Terminal.app, iTerm2, etc.)
3. Make sure the toggle is enabled

## Step 8: Test

Make sure Viscosity is running (menu bar icon), then:

```bash
vpn up pune
```

Expected output:
```
Connecting to: Pune (PNQ2)
OTP: 123456 (counter: N)
Waiting for auth dialog... filling credentials...
Connecting.....
Connected!
```

## Available Commands

| Command | Description |
|---|---|
| `vpn up pune` | Connect (fuzzy, case-insensitive match) |
| `vpn up global` | Connect to Global VPN |
| `vpn down` | Disconnect all connections |
| `vpn down pune` | Disconnect a specific connection |
| `vpn status` | Show all connections with status |
| `vpn list` | List available connection names |
| `vpn otp` | Preview next OTP without consuming it |
| `vpn setup` | Interactive credential setup |

## Troubleshooting

- **Auth fails with "dialog reappeared"** — most likely HOTP counter desync. Generate a fresh QR code from your identity management portal, then repeat Steps 4-6.
- **Auth dialog does not appear** — make sure Viscosity is running and no other VPN connections are active (`vpn down` first).
- **"osascript is not allowed assistive access"** — your terminal app needs Accessibility permissions (Step 7).
- **Try "separate" auth mode** if combined mode consistently fails:
  ```bash
  security delete-generic-password -a "viscosity-vpn" -s "vpn-auth-mode" 2>/dev/null
  security add-generic-password -a "viscosity-vpn" -s "vpn-auth-mode" -w "separate"
  ```
- **Reset counter manually:**
  ```bash
  security delete-generic-password -a "viscosity-vpn" -s "vpn-hotp-counter" 2>/dev/null
  security add-generic-password -a "viscosity-vpn" -s "vpn-hotp-counter" -w "NEW_COUNTER"
  ```

## Important Notes

- **Do NOT use your phone authenticator app for this token after setup.** HOTP counters must stay in sync — using two devices will cause desync and auth failures.
- **Use YOUR OWN credentials.** Do not copy someone else's password, QR code, or counter.
- **Viscosity must be running** for connections to work. It runs as a menu bar app.
