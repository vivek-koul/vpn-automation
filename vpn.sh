#!/usr/bin/env bash
# VPN CLI — fully automated Red Hat VPN connection (HOTP)
# Uses openvpn CLI directly, no GUI

_VPN_KEYCHAIN_ACCOUNT="viscosity-vpn"
_VPN_KEYCHAIN_PASSWORD="vpn-password"
_VPN_KEYCHAIN_SECRET="vpn-totp-secret"
_VPN_KEYCHAIN_USER="vpn-username"
_VPN_KEYCHAIN_AUTHMODE="vpn-auth-mode"
_VPN_KEYCHAIN_COUNTER="vpn-hotp-counter"
_VPN_CONFIG_DIR="$HOME/Library/Application Support/Viscosity/OpenVPN"
_VPN_OPENVPN="/opt/homebrew/opt/openvpn/sbin/openvpn"
_VPN_PID_DIR="/tmp/.vpn-pids"

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

            # Check if already connected
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

            echo "Connecting to: $match"
            echo "OTP: $otp (counter: $counter)"

            local config_id
            config_id=$(_vpn_config_id "$match")
            if [ -z "$config_id" ]; then
                echo "Could not find config for '$match'."; return 1
            fi

            if _vpn_connect "$match" "$config_id" "$username" "$password" "$otp" "$auth_mode"; then
                _vpn_keychain_set "$_VPN_KEYCHAIN_COUNTER" "$next_counter" 2>/dev/null
            fi
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
            printf "%-40s %s\n" "CONNECTION" "STATUS"
            printf "%-40s %s\n" "----------" "------"
            mkdir -p "$_VPN_PID_DIR"
            for conf in "$_VPN_CONFIG_DIR"/*/config.conf; do
                local name
                name=$(grep '#viscosity name' "$conf" | sed 's/#viscosity name "//' | sed 's/"$//')
                [ -z "$name" ] && continue
                if _vpn_is_running "$name"; then
                    printf "%-40s \033[32m%s\033[0m\n" "$name" "Connected"
                else
                    printf "%-40s %s\n" "$name" "Disconnected"
                fi
            done
            ;;

        list|ls)
            for conf in "$_VPN_CONFIG_DIR"/*/config.conf; do
                local name
                name=$(grep '#viscosity name' "$conf" | sed 's/#viscosity name "//' | sed 's/"$//')
                [ -z "$name" ] && continue
                echo "  $name"
            done
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

        log)
            local query="${1:-global}"
            local match
            match=$(_vpn_find "$query")
            if [ -z "$match" ]; then
                echo "No connection matching '$query'."; return 1
            fi
            local slug
            slug=$(_vpn_slug "$match")
            local logfile="/tmp/.vpn-${slug}.log"
            if [ -f "$logfile" ]; then
                tail -30 "$logfile"
            else
                echo "No log file for '$match'."
            fi
            ;;

        help|--help|-h)
            echo "Usage: vpn <command> [connection-name]"
            echo ""
            echo "Commands:"
            echo "  up <name>      Connect with auto-auth (no GUI)"
            echo "  down [name]    Disconnect specific or all"
            echo "  status         Show connection states"
            echo "  list           List available connections"
            echo "  otp            Show next OTP (without consuming)"
            echo "  log [name]     Show recent connection log"
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

_vpn_slug() {
    echo "$1" | tr '[:upper:] ()' '[:lower:]---' | tr -s '-' | sed 's/-$//'
}

_vpn_config_id() {
    local target_name="$1"
    for conf in "$_VPN_CONFIG_DIR"/*/config.conf; do
        local name
        name=$(grep '#viscosity name' "$conf" | sed 's/#viscosity name "//' | sed 's/"$//')
        if [ "$name" = "$target_name" ]; then
            basename "$(dirname "$conf")"
            return 0
        fi
    done
    return 1
}

_vpn_is_running() {
    local name="$1"
    local slug
    slug=$(_vpn_slug "$name")
    local pidfile="$_VPN_PID_DIR/${slug}.pid"
    if [ -f "$pidfile" ]; then
        local pid
        pid=$(cat "$pidfile" 2>/dev/null || sudo cat "$pidfile" 2>/dev/null)
        if [ -n "$pid" ] && ps -p "$pid" >/dev/null 2>&1; then
            return 0
        else
            sudo rm -f "$pidfile" 2>/dev/null
        fi
    fi
    return 1
}

_vpn_connect() {
    local conn_name="$1" config_id="$2" username="$3" password="$4" otp="$5" auth_mode="$6"
    local config_file="$_VPN_CONFIG_DIR/$config_id/config.conf"
    local slug
    slug=$(_vpn_slug "$conn_name")
    local auth_file="/tmp/.vpn-auth-${slug}"
    local logfile="/tmp/.vpn-${slug}.log"
    local pidfile="$_VPN_PID_DIR/${slug}.pid"

    mkdir -p "$_VPN_PID_DIR"

    # Build auth file
    local auth_password
    if [ "$auth_mode" = "separate" ]; then
        auth_password="$password"
    else
        auth_password="${password}${otp}"
    fi

    umask 077
    printf '%s\n%s\n' "$username" "$auth_password" > "$auth_file"
    chmod 600 "$auth_file"

    local config_dir
    config_dir="$_VPN_CONFIG_DIR/$config_id"

    # Clean up old root-owned files
    sudo rm -f "$logfile" "$pidfile" 2>/dev/null
    touch "$logfile" "$pidfile"

    # Build openvpn command
    echo "Starting OpenVPN..."
    sudo "$_VPN_OPENVPN" \
        --cd "$config_dir" \
        --config "$config_file" \
        --auth-user-pass "$auth_file" \
        --daemon "vpn-${slug}" \
        --log "$logfile" \
        --writepid "$pidfile" \
        --auth-nocache \
        --script-security 2 \
        --up "$HOME/.vpn-dns.sh" \
        --down "$HOME/.vpn-dns.sh" \
        2>&1

    # Make log/pid readable
    sudo chmod 644 "$logfile" "$pidfile" 2>/dev/null

    local rc=$?
    # Clean up auth file immediately
    rm -f "$auth_file"

    if [ $rc -ne 0 ]; then
        echo "Failed to start OpenVPN (exit code: $rc)."
        [ -f "$logfile" ] && echo "Check: vpn log $slug"
        return 1
    fi

    # Wait for connection
    echo -n "Waiting"
    local waited=0
    while [ $waited -lt 20 ]; do
        sleep 1
        waited=$((waited + 1))
        if [ -f "$logfile" ] && grep -q "Initialization Sequence Completed" "$logfile" 2>/dev/null; then
            echo ""
            echo "Connected!"
            return 0
        fi
        if [ -f "$logfile" ] && grep -q "AUTH_FAILED" "$logfile" 2>/dev/null; then
            echo ""
            echo "Authentication failed. Check password/OTP."
            echo "Run 'vpn log ${slug}' for details."
            sudo kill "$(cat "$pidfile" 2>/dev/null)" 2>/dev/null
            rm -f "$pidfile"
            return 1
        fi
        printf "."
    done

    echo ""
    if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
        echo "Still connecting... check 'vpn log ${slug}' or 'vpn status'."
        return 0
    else
        echo "Connection failed. Run 'vpn log ${slug}' for details."
        return 1
    fi
}

_vpn_disconnect() {
    local name="$1"
    local slug
    slug=$(_vpn_slug "$name")
    local pidfile="$_VPN_PID_DIR/${slug}.pid"

    if [ -f "$pidfile" ]; then
        local pid
        pid=$(cat "$pidfile" 2>/dev/null || sudo cat "$pidfile" 2>/dev/null)
        if [ -n "$pid" ] && ps -p "$pid" >/dev/null 2>&1; then
            echo "Disconnecting: $name"
            sudo kill "$pid"
            sleep 1
            sudo rm -f "$pidfile" 2>/dev/null
            echo "Done."
            return 0
        fi
        sudo rm -f "$pidfile" 2>/dev/null
    fi
    echo "'$name' is not connected."
}

_vpn_disconnect_all() {
    local found=0
    mkdir -p "$_VPN_PID_DIR"
    for pidfile in "$_VPN_PID_DIR"/*.pid; do
        [ -f "$pidfile" ] || continue
        local pid
        pid=$(cat "$pidfile" 2>/dev/null || sudo cat "$pidfile" 2>/dev/null)
        if [ -n "$pid" ] && ps -p "$pid" >/dev/null 2>&1; then
            local slug
            slug=$(basename "$pidfile" .pid)
            echo "Disconnecting: $slug"
            sudo kill "$pid"
            found=1
        fi
        sudo rm -f "$pidfile" 2>/dev/null
    done
    if [ $found -eq 0 ]; then
        echo "No active connections."
    else
        sleep 1
        echo "Done."
    fi
}

_vpn_setup() {
    echo "=== VPN Credential Setup ==="
    echo ""

    local current_user
    current_user=$(_vpn_keychain_get "$_VPN_KEYCHAIN_USER" 2>/dev/null)
    printf "Username [%s]: " "${current_user:-vkoul}"
    read -r username
    username="${username:-${current_user:-vkoul}}"

    printf "Password (hidden): "
    read -rs password
    echo ""
    if [ -z "$password" ]; then echo "Password is required."; return 1; fi

    local current_secret
    current_secret=$(_vpn_keychain_get "$_VPN_KEYCHAIN_SECRET" 2>/dev/null)
    if [ -n "$current_secret" ]; then
        printf "OTP secret [****saved****]: "
    else
        printf "OTP secret (base32): "
    fi
    read -r secret
    secret="${secret:-$current_secret}"
    if [ -z "$secret" ]; then echo "OTP secret is required."; return 1; fi

    local current_counter
    current_counter=$(_vpn_keychain_get "$_VPN_KEYCHAIN_COUNTER" 2>/dev/null)
    printf "HOTP counter [%s]: " "${current_counter:-1}"
    read -r counter
    counter="${counter:-${current_counter:-1}}"

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

    echo "Saved. Try: vpn up global"
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

    for conf in "$_VPN_CONFIG_DIR"/*/config.conf; do
        local name
        name=$(grep '#viscosity name' "$conf" | sed 's/#viscosity name "//' | sed 's/"$//')
        [ -z "$name" ] && continue
        local name_lower
        name_lower=$(echo "$name" | tr '[:upper:]' '[:lower:]')
        if [[ "$name_lower" == "$query_lower" ]]; then
            echo "$name"; return 0
        fi
    done

    for conf in "$_VPN_CONFIG_DIR"/*/config.conf; do
        local name
        name=$(grep '#viscosity name' "$conf" | sed 's/#viscosity name "//' | sed 's/"$//')
        [ -z "$name" ] && continue
        local name_lower
        name_lower=$(echo "$name" | tr '[:upper:]' '[:lower:]')
        if [[ "$name_lower" == *"$query_lower"* ]]; then
            echo "$name"; return 0
        fi
    done
}

_vpn_completions() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"

    if [ "$COMP_CWORD" -eq 1 ]; then
        COMPREPLY=($(compgen -W "up down status list otp log setup help" -- "$cur"))
    elif [[ "$prev" == "up" || "$prev" == "down" || "$prev" == "log" ]]; then
        local conns=""
        for conf in "$HOME/Library/Application Support/Viscosity/OpenVPN"/*/config.conf; do
            local name
            name=$(grep '#viscosity name' "$conf" 2>/dev/null | sed 's/#viscosity name "//' | sed 's/"$//')
            [ -n "$name" ] && conns="$conns $name"
        done
        COMPREPLY=($(compgen -W "$conns" -- "$cur"))
    fi
}
complete -F _vpn_completions vpn
