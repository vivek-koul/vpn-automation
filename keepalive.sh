#!/usr/bin/env bash
# VPN keepalive daemon — auto-reconnects if VPN drops
# Runs as a LaunchAgent on login

source "$HOME/.vpn.sh"

VPN_TARGET="${1:-pune}"
CHECK_INTERVAL=30
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

log "Keepalive started for: $CONN_NAME (checking every ${CHECK_INTERVAL}s)"

# Initial delay on boot to let network come up
sleep 10

while true; do
    if _vpn_is_running "$CONN_NAME"; then
        : # connected, do nothing
    else
        log "VPN disconnected. Reconnecting to: $CONN_NAME"
        vpn up "$VPN_TARGET" >> "$LOG" 2>&1
        if _vpn_is_running "$CONN_NAME"; then
            log "Reconnected successfully."
        else
            log "Reconnect failed. Will retry in ${CHECK_INTERVAL}s."
        fi
    fi
    sleep "$CHECK_INTERVAL"
done
