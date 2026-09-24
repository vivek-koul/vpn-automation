#!/usr/bin/env bash
# VPN CLI — fully automated VPN via Viscosity + HOTP
# Uses Viscosity for connection, auto-fills credentials via UI scripting

_VPN_KEYCHAIN_ACCOUNT="viscosity-vpn"
_VPN_KEYCHAIN_PASSWORD="vpn-password"
_VPN_KEYCHAIN_SECRET="vpn-totp-secret"
_VPN_KEYCHAIN_USER="vpn-username"
_VPN_KEYCHAIN_AUTHMODE="vpn-auth-mode"
_VPN_KEYCHAIN_COUNTER="vpn-hotp-counter"
_VPN_CONFIG_DIR="$HOME/Library/Application Support/Viscosity/OpenVPN"

vpn() {
    local cmd="${1:-status}"
    shift 2>/dev/null

    case "$cmd" in
        up|connect)
            if [ -z "$1" ]; then
                echo "Usage: vpn up <name>"
                echo "Run 'vpn list' to see available connections."
                return 1
            fi
            local query="$*"
            local match
            match=$(_vpn_find "$query")
            if [ -z "$match" ]; then
                echo "No connection matching '$query'. Run 'vpn list' to see options."
                return 1
            fi

            if _vpn_is_running "$match"; then
                echo "'$match' is already connected."
                return 0
            fi

            local password username secret otp counter auth_mode
            username=$(_vpn_keychain_get "$_VPN_KEYCHAIN_USER") || {
                echo "No credentials stored. Run 'vpn setup' first."; return 1
            }
            password=$(_vpn_keychain_get "$_VPN_KEYCHAIN_PASSWORD") || {
                echo "No password stored. Run 'vpn setup' first."; return 1
            }
            secret=$(_vpn_keychain_get "$_VPN_KEYCHAIN_SECRET") || {
                echo "No OTP secret stored. Run 'vpn setup' first."; return 1
            }
            counter=$(_vpn_keychain_get "$_VPN_KEYCHAIN_COUNTER") || {
                echo "No HOTP counter stored. Run 'vpn setup' first."; return 1
            }
            auth_mode=$(_vpn_keychain_get "$_VPN_KEYCHAIN_AUTHMODE" 2>/dev/null)
            auth_mode="${auth_mode:-combined}"

            otp=$(oathtool --hotp -b -c "$counter" "$secret" 2>/dev/null)
            if [ -z "$otp" ]; then
                echo "Failed to generate OTP."; return 1
            fi

            local next_counter=$((counter + 1))
            _vpn_keychain_set "$_VPN_KEYCHAIN_COUNTER" "$next_counter" 2>/dev/null

            echo "Connecting to: $match"
            echo "OTP: $otp (counter: $counter)"

            _vpn_connect "$match" "$username" "$password" "$otp" "$auth_mode"
            ;;

        down|disconnect)
            if [ -n "$1" ]; then
                local query="$*"
                local match
                match=$(_vpn_find "$query")
                if [ -z "$match" ]; then
                    echo "No connection matching '$query'."; return 1
                fi
                _vpn_disconnect "$match"
            else
                _vpn_disconnect_all
            fi
            ;;

        status|s)
            _vpn_status
            ;;

        list|ls)
            _vpn_list
            ;;

        otp)
            local secret counter otp
            secret=$(_vpn_keychain_get "$_VPN_KEYCHAIN_SECRET") || {
                echo "No OTP secret stored."; return 1
            }
            counter=$(_vpn_keychain_get "$_VPN_KEYCHAIN_COUNTER") || {
                echo "No counter stored."; return 1
            }
            otp=$(oathtool --hotp -b -c "$counter" "$secret" 2>/dev/null)
            echo "$otp (counter: $counter, not consumed)"
            ;;

        setup)
            _vpn_setup
            ;;

        help|--help|-h)
            echo "Usage: vpn <command> [connection-name]"
            echo ""
            echo "Commands:"
            echo "  up <name>      Connect via Viscosity with auto-auth"
            echo "  down [name]    Disconnect specific or all"
            echo "  status         Show connection states"
            echo "  list           List available connections"
            echo "  otp            Show next OTP (without consuming)"
            echo "  setup          Store credentials in Keychain"
            echo "  help           Show this help"
            echo ""
            echo "Examples:"
            echo "  vpn up pune        vpn up global"
            echo "  vpn down           vpn down pune"
            echo "  vpn status         vpn otp"
            ;;

        *)
            echo "Unknown command: $cmd. Run 'vpn help' for usage."
            return 1
            ;;
    esac
}

_vpn_connect() {
    local conn_name="$1" username="$2" password="$3" otp="$4" auth_mode="$5"

    local auth_password
    if [ "$auth_mode" = "separate" ]; then
        auth_password="$password"
    else
        auth_password="${password}${otp}"
    fi

    osascript -e "tell application \"Viscosity\" to connect \"$conn_name\"" 2>/dev/null

    echo -n "Waiting for auth dialog"
    local waited=0
    local dialog_found=0
    while [ $waited -lt 15 ]; do
        sleep 1
        waited=$((waited + 1))

        local state
        state=$(_vpn_viscosity_state "$conn_name")
        if [ "$state" = "Connected" ]; then
            echo ""
            echo "Connected!"
            return 0
        fi

        local has_dialog
        has_dialog=$(_vpn_check_dialog)
        if [ "$has_dialog" = "yes" ]; then
            dialog_found=1
            break
        fi
        printf "."
    done

    if [ $dialog_found -eq 0 ]; then
        echo ""
        local state
        state=$(_vpn_viscosity_state "$conn_name")
        if [ "$state" = "Connected" ]; then
            echo "Connected!"
            return 0
        fi
        echo "Auth dialog did not appear. State: $state"
        return 1
    fi

    echo " filling credentials..."
    _vpn_fill_dialog "$auth_password" "$conn_name"

    echo -n "Connecting"
    waited=0
    while [ $waited -lt 30 ]; do
        sleep 1
        waited=$((waited + 1))
        local state
        state=$(_vpn_viscosity_state "$conn_name")
        case "$state" in
            Connected)
                echo ""
                echo "Connected!"
                return 0
                ;;
            Disconnected)
                echo ""
                echo "Connection failed (auth rejected)."
                return 1
                ;;
        esac
        local has_dialog
        has_dialog=$(_vpn_check_dialog)
        if [ "$has_dialog" = "yes" ]; then
            echo ""
            echo "Auth failed — dialog reappeared (wrong OTP or password)."
            osascript -e "tell application \"System Events\" to tell process \"Viscosity\" to click button \"Cancel\" of window \"Viscosity - $conn_name\"" 2>/dev/null
            sleep 0.5
            osascript -e "tell application \"Viscosity\" to disconnect \"$conn_name\"" 2>/dev/null
            return 1
        fi
        printf "."
    done

    echo ""
    echo "Timed out. State: $(_vpn_viscosity_state "$conn_name")"
    return 1
}

_vpn_check_dialog() {
    osascript 2>/dev/null <<'APPLESCRIPT'
tell application "System Events"
    tell process "Viscosity"
        if (count of windows) > 0 then
            repeat with w in windows
                try
                    if (count of text fields of w) >= 2 then
                        return "yes"
                    end if
                end try
            end repeat
        end if
    end tell
end tell
return "no"
APPLESCRIPT
}

_vpn_fill_dialog() {
    local pw="$1" conn_name="$2"
    local win_name="Viscosity - ${conn_name}"
    VPN_AUTH_PW="$pw" VPN_WIN="$win_name" osascript 2>/dev/null <<'APPLESCRIPT'
set authPw to system attribute "VPN_AUTH_PW"
set winName to system attribute "VPN_WIN"
tell application "System Events"
    tell process "Viscosity"
        tell window winName
            set value of text field 1 to authPw
            delay 0.3
            click button "OK"
        end tell
    end tell
end tell
APPLESCRIPT
}

_vpn_viscosity_state() {
    local conn_name="$1"
    osascript 2>/dev/null <<APPLESCRIPT
tell application "Viscosity"
    repeat with c in connections
        if name of c is "$conn_name" then
            return state of c as text
        end if
    end repeat
end tell
return "Unknown"
APPLESCRIPT
}

_vpn_is_running() {
    local name="$1"
    local state
    state=$(_vpn_viscosity_state "$name")
    [ "$state" = "Connected" ]
}

_vpn_disconnect() {
    local name="$1"
    if _vpn_is_running "$name"; then
        echo "Disconnecting: $name"
        osascript -e "tell application \"Viscosity\" to disconnect \"$name\"" 2>/dev/null
        sleep 1
        echo "Done."
    else
        echo "'$name' is not connected."
    fi
}

_vpn_disconnect_all() {
    osascript -e 'tell application "Viscosity" to disconnectall' 2>/dev/null
    echo "Disconnected all."
}

_vpn_status() {
    printf "%-40s %s\n" "CONNECTION" "STATUS"
    printf "%-40s %s\n" "----------" "------"
    local names
    names=$(osascript -e 'tell application "Viscosity"
        set output to ""
        repeat with c in connections
            set output to output & name of c & tab & state of c & linefeed
        end repeat
        return output
    end tell' 2>/dev/null)

    while IFS=$'\t' read -r name state; do
        [ -z "$name" ] && continue
        if [ "$state" = "Connected" ]; then
            printf "%-40s \033[32m%s\033[0m\n" "$name" "$state"
        else
            printf "%-40s %s\n" "$name" "$state"
        fi
    done <<< "$names"
}

_vpn_list() {
    osascript -e 'tell application "Viscosity"
        repeat with c in connections
            log "  " & name of c
        end repeat
    end tell' 2>&1 | sed 's/^.*: //'
}

_vpn_setup() {
    echo "=== VPN Credential Setup ==="
    echo ""

    local current_user
    current_user=$(_vpn_keychain_get "$_VPN_KEYCHAIN_USER" 2>/dev/null)
    printf "Username [%s]: " "${current_user}"
    read -r username
    username="${username:-${current_user}}"
    if [ -z "$username" ]; then echo "Username is required."; return 1; fi

    printf "Password (hidden): "
    read -rs password
    echo ""
    if [ -z "$password" ]; then echo "Password is required."; return 1; fi

    local current_secret secret counter
    current_secret=$(_vpn_keychain_get "$_VPN_KEYCHAIN_SECRET" 2>/dev/null)
    local current_counter
    current_counter=$(_vpn_keychain_get "$_VPN_KEYCHAIN_COUNTER" 2>/dev/null)

    if [ -n "$current_secret" ]; then
        printf "OTP secret [****saved****]: "
        read -r secret
        secret="${secret:-$current_secret}"
        printf "HOTP counter [%s]: " "${current_counter:-1}"
        read -r counter
        counter="${counter:-${current_counter:-1}}"
    else
        echo ""
        echo "To extract your OTP secret, provide the path to your QR code image."
        echo "  (Download it from your identity management portal first)"
        echo ""
        printf "Path to QR code image [~/Downloads/QR.png]: "
        read -r qr_path
        qr_path="${qr_path:-$HOME/Downloads/QR.png}"
        qr_path="${qr_path/#\~/$HOME}"

        if [ ! -f "$qr_path" ]; then
            echo "File not found: $qr_path"
            echo "  Download your QR code image and try again, or enter the secret manually."
            printf "OTP secret (base32): "
            read -r secret
            if [ -z "$secret" ]; then echo "OTP secret is required."; return 1; fi
            printf "HOTP counter [1]: "
            read -r counter
            counter="${counter:-1}"
        else
            echo "  Reading QR code..."
            local qr_uri
            qr_uri=$(zbarimg --quiet --raw "$qr_path" 2>/dev/null)
            if [ -z "$qr_uri" ] || [[ "$qr_uri" != otpauth://* ]]; then
                echo "  Could not decode QR code. Enter the secret manually."
                printf "OTP secret (base32): "
                read -r secret
                if [ -z "$secret" ]; then echo "OTP secret is required."; return 1; fi
                printf "HOTP counter [1]: "
                read -r counter
                counter="${counter:-1}"
            else
                secret=$(echo "$qr_uri" | sed -n 's/.*secret=\([^&]*\).*/\1/p')
                counter=$(echo "$qr_uri" | sed -n 's/.*counter=\([^&]*\).*/\1/p')
                counter="${counter:-1}"
                echo "  Extracted secret: ${secret:0:4}****${secret: -4}"
                echo "  Extracted counter: $counter"
                echo ""
            fi
        fi
    fi
    if [ -z "$secret" ]; then echo "OTP secret is required."; return 1; fi

    echo "Auth mode: 1) combined (password+OTP)  2) separate"
    local current_mode
    current_mode=$(_vpn_keychain_get "$_VPN_KEYCHAIN_AUTHMODE" 2>/dev/null)
    printf "Mode [%s] (1/2): " "${current_mode:-combined}"
    read -r mode_choice
    case "$mode_choice" in
        2) auth_mode="separate" ;; *) auth_mode="${current_mode:-combined}" ;;
    esac

    _vpn_keychain_set "$_VPN_KEYCHAIN_USER" "$username" 2>/dev/null
    _vpn_keychain_set "$_VPN_KEYCHAIN_PASSWORD" "$password" 2>/dev/null
    _vpn_keychain_set "$_VPN_KEYCHAIN_SECRET" "$secret" 2>/dev/null
    _vpn_keychain_set "$_VPN_KEYCHAIN_COUNTER" "$counter" 2>/dev/null
    _vpn_keychain_set "$_VPN_KEYCHAIN_AUTHMODE" "$auth_mode" 2>/dev/null

    echo "Saved. Try: vpn up pune"
}

_vpn_keychain_set() {
    local service="$1" value="$2"
    security delete-generic-password -a "$_VPN_KEYCHAIN_ACCOUNT" -s "$service" >/dev/null 2>&1
    security add-generic-password -a "$_VPN_KEYCHAIN_ACCOUNT" -s "$service" -w "$value" 2>/dev/null
}

_vpn_keychain_get() {
    local service="$1"
    security find-generic-password -a "$_VPN_KEYCHAIN_ACCOUNT" -s "$service" -w 2>/dev/null
}

_vpn_find() {
    local query="$*"
    local query_lower
    query_lower=$(echo "$query" | tr '[:upper:]' '[:lower:]')

    # Get connection names from Viscosity
    local names
    names=$(osascript -e 'tell application "Viscosity"
        set output to ""
        repeat with c in connections
            set output to output & name of c & linefeed
        end repeat
        return output
    end tell' 2>/dev/null)

    # Exact match first
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        local name_lower
        name_lower=$(echo "$name" | tr '[:upper:]' '[:lower:]')
        if [[ "$name_lower" == "$query_lower" ]]; then
            echo "$name"; return 0
        fi
    done <<< "$names"

    # Partial match
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        local name_lower
        name_lower=$(echo "$name" | tr '[:upper:]' '[:lower:]')
        if [[ "$name_lower" == *"$query_lower"* ]]; then
            echo "$name"; return 0
        fi
    done <<< "$names"
}

_vpn_completions() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"

    if [ "$COMP_CWORD" -eq 1 ]; then
        COMPREPLY=($(compgen -W "up down status list otp setup help" -- "$cur"))
    elif [[ "$prev" == "up" || "$prev" == "down" ]]; then
        local conns
        conns=$(osascript -e 'tell application "Viscosity"
            set output to ""
            repeat with c in connections
                set output to output & name of c & linefeed
            end repeat
            return output
        end tell' 2>/dev/null)
        COMPREPLY=($(compgen -W "$conns" -- "$cur"))
    fi
}
complete -F _vpn_completions vpn
