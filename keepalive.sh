#!/usr/bin/env bash
# VPN keepalive daemon — auto-reconnects if VPN drops
# Runs as a LaunchAgent on login

source "$HOME/.vpn.sh"

VPN_TARGET="${1:-pune}"
CHECK_INTERVAL=30
FAIL_WAIT=300
MAX_RETRIES=3
LOG="/tmp/.vpn-keepalive.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"
}

# Resolve the connection name once
CONN_NAME=$(_vpn_find "$VPN_TARGET")
if [ -z "$CONN_NAME" ]; then
    log "ERROR: No connection matching '$VPN_TARGET'. Exiting."
    exit 1
fi

log "Keepalive started for: $CONN_NAME (check: ${CHECK_INTERVAL}s, backoff: ${FAIL_WAIT}s after ${MAX_RETRIES} failures)"

# Initial delay on boot to let network come up
sleep 15

fail_count=0

while true; do
    if _vpn_is_running "$CONN_NAME"; then
        fail_count=0
    else
        # Check if network is actually available before trying
        if ! ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
            log "Network not available. Waiting..."
            sleep "$CHECK_INTERVAL"
            continue
        fi

        fail_count=$((fail_count + 1))

        if [ $fail_count -gt $MAX_RETRIES ]; then
            log "Failed $((fail_count - 1)) times. Backing off for ${FAIL_WAIT}s."
            sleep "$FAIL_WAIT"
            fail_count=1
        fi

        log "VPN disconnected. Reconnecting to: $CONN_NAME (attempt $fail_count/$MAX_RETRIES)"
        _vpn_disconnect_all >> "$LOG" 2>&1
        sleep 2
        vpn up "$VPN_TARGET" >> "$LOG" 2>&1

        if _vpn_is_running "$CONN_NAME"; then
            log "Reconnected successfully."
            fail_count=0
        else
            log "Reconnect failed."
        fi
    fi
    sleep "$CHECK_INTERVAL"
done
