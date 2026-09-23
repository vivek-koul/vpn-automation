# Red Hat VPN CLI Automation — Setup Guide

Automate Red Hat VPN connections from the terminal. Zero manual password/OTP entry.
Uses Viscosity + AppleScript UI scripting + macOS Keychain + auto-generated HOTP codes.

## How It Works

Viscosity's proprietary OpenVPN binary is required by the Red Hat VPN server — standard `openvpn` CLI fails authentication. This automation:
1. Tells Viscosity to connect via AppleScript
2. Waits for the auth dialog to appear
3. Auto-fills password+OTP using UI scripting
4. Clicks OK

## Prerequisites

- macOS with Homebrew installed
- **Viscosity** already installed and configured with Red Hat VPN connections
- Your Red Hat VPN username, password, and OTP QR code image
- **Terminal** (or your terminal app) must have **Accessibility** permissions:
  System Settings > Privacy & Security > Accessibility > enable your terminal app

## Step 1: Install Dependencies

```bash
brew install oath-toolkit zbar
```

- `oath-toolkit` — generates 6-digit OTP codes from your HOTP secret
- `zbar` — decodes QR codes to extract your HOTP secret

## Step 2: Clone and Install Scripts

```bash
git clone https://github.com/vivek-koul/vpn-automation.git /tmp/vpn-automation
cp /tmp/vpn-automation/vpn.sh ~/.vpn.sh
```

## Step 3: Source the Script and Add Aliases

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

Save your OTP QR code image (from Red Hat IdM) as `~/Downloads/QR.png`, then:

```bash
zbarimg --quiet --raw ~/Downloads/QR.png
```

This prints a URI like:
```
otpauth://hotp/OATH12345678?secret=ABCDEFGHIJK...&counter=1&digits=6&issuer=Red%20Hat
```

Copy the `secret=` value (e.g., `ABCDEFGHIJK...`). That is your HOTP secret.

## Step 5: Find Your Current HOTP Counter

If you've been using the token from your phone authenticator, the counter has advanced beyond 1.

Open your authenticator app, find the Red Hat token, and note the current 6-digit code. Then run:

```bash
SECRET="YOUR_SECRET_FROM_STEP_4"
TARGET="THE_6_DIGIT_CODE"
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

Replace the values with YOUR OWN credentials:

```bash
# Username
security add-generic-password -a "viscosity-vpn" -s "vpn-username" -w "YOUR_KERBEROS_USERNAME"

# Password (hidden input)
read -rsp "VPN Password: " p && security add-generic-password -a "viscosity-vpn" -s "vpn-password" -w "$p" && unset p && echo ""

# HOTP secret (from Step 4)
security add-generic-password -a "viscosity-vpn" -s "vpn-totp-secret" -w "YOUR_HOTP_SECRET"

# Counter (from Step 5 — use match + 1)
security add-generic-password -a "viscosity-vpn" -s "vpn-hotp-counter" -w "NEXT_COUNTER_VALUE"

# Auth mode
security add-generic-password -a "viscosity-vpn" -s "vpn-auth-mode" -w "combined"
```

Or use the interactive setup: `vpn setup`

## Step 7: Grant Accessibility Access

The automation needs to fill Viscosity's auth dialog via UI scripting.

1. Open **System Settings** > **Privacy & Security** > **Accessibility**
2. Add and enable your terminal app (Terminal.app, iTerm2, etc.)

## Step 8: Test

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
| `vpn up global` | Connect to Red Hat Global VPN |
| `vpn down` | Disconnect all connections |
| `vpn down pune` | Disconnect a specific connection |
| `vpn status` | Show all connections with status |
| `vpn list` | List available connection names |
| `vpn otp` | Preview next OTP without consuming it |
| `vpn setup` | Interactive credential setup |

## Important Notes

- **Do NOT use your phone authenticator app for this token after setup.** HOTP counters must stay in sync — using two devices will cause failures.
- **Use YOUR OWN credentials.** Do not copy someone else's password, QR code, or counter.
- **If auth fails**, try switching to "separate" auth mode:
  ```bash
  security delete-generic-password -a "viscosity-vpn" -s "vpn-auth-mode" 2>/dev/null
  security add-generic-password -a "viscosity-vpn" -s "vpn-auth-mode" -w "separate"
  ```
- **If counter gets out of sync**, repeat Step 5, then:
  ```bash
  security delete-generic-password -a "viscosity-vpn" -s "vpn-hotp-counter" 2>/dev/null
  security add-generic-password -a "viscosity-vpn" -s "vpn-hotp-counter" -w "NEW_COUNTER"
  ```
- **Viscosity must be running** for connections to work. It runs as a menu bar app.
