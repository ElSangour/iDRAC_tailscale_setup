#!/bin/bash

if [ ! -f "network.conf" ]; then
    echo "Error: network.conf not found. Run configure.sh first."
    exit 1
fi

source network.conf

echo "Starting setup with:"
echo "  Interface: $NETWORK_INTERFACE"
echo "  Subnet: $SUBNET"
echo "  iDRAC: $IDRAC_IP"
echo

sudo apt update && sudo apt upgrade -y
curl -fsSL https://tailscale.com/install.sh | sh

sudo sed -i '/net.ipv4.ip_forward/s/^#//g' /etc/sysctl.conf
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
fi
sudo sysctl -p

TAILSCALE_CMD="sudo tailscale up --advertise-routes=$SUBNET --accept-routes=true"
if [[ $ENABLE_SSH =~ ^[Yy]$ ]]; then
    TAILSCALE_CMD="$TAILSCALE_CMD --ssh"
fi

echo "Starting Tailscale..."
$TAILSCALE_CMD

sudo iptables -A FORWARD -i tailscale0 -o $NETWORK_INTERFACE -j ACCEPT
sudo iptables -A FORWARD -i $NETWORK_INTERFACE -o tailscale0 -m state --state RELATED,ESTABLISHED -j ACCEPT

if [[ $ENABLE_NAT =~ ^[Yy]$ ]]; then
    sudo iptables -t nat -A POSTROUTING -o $NETWORK_INTERFACE -j MASQUERADE
fi

if [[ $INSTALL_IPTABLES =~ ^[Yy]$ ]]; then
    sudo apt install -y iptables-persistent
    sudo netfilter-persistent save
fi

echo
echo "========================================="
echo "Setup complete!"
echo "========================================="
echo
echo "Next steps:"
echo "1. Go to https://login.tailscale.com/admin/machines"
echo "2. Approve the route: $SUBNET"
echo "3. Run ./verify.sh"
echo