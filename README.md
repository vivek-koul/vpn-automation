# Red Hat VPN CLI Automation — Setup Guide

Automate Red Hat VPN connections from the terminal. No GUI, no manual password/OTP entry.
Uses Viscosity's config files + OpenVPN CLI + macOS Keychain + auto-generated HOTP codes.

## Prerequisites

- macOS with Homebrew installed
- Viscosity already installed and configured with Red Hat VPN connections
- Your Red Hat VPN username, password, and OTP QR code image

## Step 1: Install Dependencies

```bash
brew install oath-toolkit openvpn zbar
```

- `oath-toolkit` — generates 6-digit OTP codes from your HOTP secret
- `openvpn` — the same VPN engine Viscosity uses internally, installed as a standalone CLI
- `zbar` — decodes QR codes to extract your HOTP secret

## Step 2: Create ~/.vpn-dns.sh

```bash
cat > ~/.vpn-dns.sh << 'SCRIPT'
#!/bin/bash
# OpenVPN DNS update script for macOS

SCUTIL=/usr/sbin/scutil

case "$script_type" in
    up)
        declare -a dns_servers
        declare -a dns_domains

        for opt in ${!foreign_option_*}; do
            val="${!opt}"
            case "$val" in
                *DNS\ *)    dns_servers+=("${val##* }") ;;
                *DOMAIN\ *) dns_domains+=("${val##* }") ;;
            esac
        done

        if [ ${#dns_servers[@]} -gt 0 ]; then
            $SCUTIL <<-EOF
				d.init
				d.add ServerAddresses * ${dns_servers[*]}
				d.add SupplementalMatchDomains * ${dns_domains[*]}
				d.add SupplementalMatchDomainsNoSearch # 1
				set State:/Network/Service/openvpn/DNS
			EOF
        fi
        ;;

    down)
        $SCUTIL <<-EOF
			remove State:/Network/Service/openvpn/DNS
		EOF
        ;;
esac
SCRIPT
chmod +x ~/.vpn-dns.sh
```

## Step 3: Create ~/.vpn.sh

Copy the file `~/.vpn.sh` from my machine (or use `vpn setup` after creating it).

The full script is large — get it from me directly or from: `scp vkoul@<my-mac>:~/.vpn.sh ~/`

## Step 4: Source the Script

For bash:
```bash
echo 'source ~/.vpn.sh' >> ~/.bashrc
source ~/.vpn.sh
```

For zsh:
```bash
echo 'source ~/.vpn.sh' >> ~/.zshrc
source ~/.vpn.sh
```

## Step 5: Set Up Passwordless sudo for OpenVPN

```bash
echo "$USER ALL=(ALL) NOPASSWD: /opt/homebrew/opt/openvpn/sbin/openvpn, /bin/kill, /bin/rm -f /tmp/.vpn-*, /bin/chmod 644 /tmp/.vpn-*" | sudo tee /etc/sudoers.d/openvpn
sudo chmod 440 /etc/sudoers.d/openvpn
```

You'll be prompted for your Mac password once — never again after that.

## Step 6: Extract Your HOTP Secret from the QR Code

Save your OTP QR code image (from Red Hat IdM) as `~/Downloads/QR.png`, then:

```bash
zbarimg --quiet --raw ~/Downloads/QR.png
```

This prints a URI like:
```
otpauth://hotp/OATH12345678?secret=ABCDEFGHIJK...&counter=1&digits=6&issuer=Red%20Hat
```

Copy the `secret=` value (e.g., `ABCDEFGHIJK...`). That is your HOTP secret.

## Step 7: Find Your Current HOTP Counter

If you've been using the token from your phone authenticator, the counter has advanced beyond 1.

Open your authenticator app, find the Red Hat token (look for the name like `OATH........`), and note the current 6-digit code. Then run:

```bash
SECRET="YOUR_SECRET_FROM_STEP_6"
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

## Step 8: Store Credentials in Keychain

Replace the values with YOUR OWN credentials:

```bash
# Username
security add-generic-password -a "viscosity-vpn" -s "vpn-username" -w "YOUR_KERBEROS_USERNAME"

# Password (hidden input)
read -rsp "VPN Password: " p && security add-generic-password -a "viscosity-vpn" -s "vpn-password" -w "$p" && unset p && echo ""

# HOTP secret (from Step 6)
security add-generic-password -a "viscosity-vpn" -s "vpn-totp-secret" -w "YOUR_HOTP_SECRET"

# Counter (from Step 7 — use match + 1)
security add-generic-password -a "viscosity-vpn" -s "vpn-hotp-counter" -w "NEXT_COUNTER_VALUE"

# Auth mode
security add-generic-password -a "viscosity-vpn" -s "vpn-auth-mode" -w "combined"
```

## Step 9: Test

```bash
vpn up global
```

Expected output:
```
Connecting to: Red Hat Global VPN
OTP: 123456 (counter: N)
Starting OpenVPN...
Waiting...........
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
| `vpn log global` | View connection log (troubleshooting) |

## Important Notes

- **Do NOT use your phone authenticator app for this token after setup.** HOTP counters must stay in sync — using two devices will cause failures.
- **Use YOUR OWN credentials.** Do not copy someone else's password, QR code, or counter.
- **If auth fails**, try switching to "separate" auth mode:
  ```bash
  security delete-generic-password -a "viscosity-vpn" -s "vpn-auth-mode" 2>/dev/null
  security add-generic-password -a "viscosity-vpn" -s "vpn-auth-mode" -w "separate"
  ```
- **If counter gets out of sync**, repeat Step 7, then:
  ```bash
  security delete-generic-password -a "viscosity-vpn" -s "vpn-hotp-counter" 2>/dev/null
  security add-generic-password -a "viscosity-vpn" -s "vpn-hotp-counter" -w "NEW_COUNTER"
  ```
