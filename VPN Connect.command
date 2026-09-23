#!/bin/bash
source ~/.vpn.sh
VPN_NAME="${VPN_DEFAULT_CONNECTION:-pune}"
vpn down
sleep 3
vpn up "$VPN_NAME"
echo ""
echo "Press any key to close this window..."
read -n 1
