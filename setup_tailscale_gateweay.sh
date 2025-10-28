#!/bin/bash
sudo apt update && sudo apt upgrade -y

curl -fsSL https://tailscale.com/install.sh | sh

sudo sed -i '/net.ipv4.ip_forward/s/^#//g' /etc/sysctl.conf
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

sudo tailscale up --advertise-routes=192.168.0.0/24 --accept-routes=true --ssh

# Optional: firewall rules to forward traffic
sudo iptables -A FORWARD -i tailscale0 -o eth0 -j ACCEPT
sudo iptables -A FORWARD -i eth0 -o tailscale0 -m state --state RELATED,ESTABLISHED -j ACCEPT

# Optional: NAT if needed
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# Save iptables rules
sudo apt install -y iptables-persistent
sudo netfilter-persistent save

echo "Setup complete. Please approve the advertised route in the Tailscale Admin Console."
