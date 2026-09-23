#!/bin/bash
source ~/.vpn.sh
vpn down
sleep 3
vpn up pune
echo ""
echo "Press any key to close this window..."
read -n 1
