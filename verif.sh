#!/bin/bash

if [ ! -f "network.conf" ]; then
    echo "Error: network.conf not found"
    exit 1
fi

source network.conf

echo "Verifying configuration for $IDRAC_IP"
echo "Use different network for valid test!"
echo
read -p "Press Enter to continue..."

echo "Checking Tailscale..."
sudo tailscale status
echo

echo "Testing iDRAC connectivity..."
ping -c 4 $IDRAC_IP
echo

echo "Testing HTTPS..."
curl -k https://$IDRAC_IP
echo

echo "Access iDRAC at: https://$IDRAC_IP"