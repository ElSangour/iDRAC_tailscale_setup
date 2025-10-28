# Dell PowerEdge T630 – Remote iDRAC Access via Raspberry Pi and Tailscale
This is repo is designed as a guided roadmap to configure remote access to DELL servers using iDRAC inside a secure VPN with tailscale and using a cheap RasberryPI as an internet gateway.

## Objective
Enable secure remote access to the Dell PowerEdge T630 iDRAC management interface from any network using a Tailscale VPN and a Raspberry Pi configured as a subnet gateway.

---

## 1. Environment Overview

| Component | Description |
|------------|-------------|
| Server | Dell PowerEdge T630 |
| Management Controller | iDRAC with dedicated NIC |
| Router | Ooredoo Router (192.168.0.1) |
| LAN Subnet | 192.168.0.0/24 (mask 255.255.255.0) |
| iDRAC IP | 192.168.0.118 |
| iDRAC MAC Address | 44:A8:42:0C:11:02 |
| Raspberry Pi | Connected to the same LAN (Ethernet) |
| VPN Solution | Tailscale |
| Goal | Access iDRAC securely from any external network |

---

## 2. iDRAC Configuration

1. Boot the Dell T630 and press **F2** to enter **System Setup**.
2. Navigate to **iDRAC Settings → Network**.
3. Ensure the following parameters:

| Setting | Value | Description |
|----------|--------|-------------|
| Enable NIC | Enabled | Activates iDRAC network interface |
| NIC Selection | Dedicated | Uses the dedicated iDRAC port |
| IPv4 Setting | DHCP or Static | DHCP if router reserved, static preferred |
| Static IP (optional) | 192.168.0.118 | Recommended for stability |
| Subnet Mask | 255.255.255.0 | Matches LAN range |
| Gateway | 192.168.0.1 | Router address |

4. Apply and save the configuration.
5. Reboot the server and confirm network link on the iDRAC Ethernet port.

---

## 3. Router Configuration

1. Log in to the router at `http://192.168.0.1`.
2. Reserve IPs for:
   - iDRAC: MAC `44:A8:42:0C:11:02` → 192.168.0.118
   - Raspberry Pi: Example 192.168.0.120
3. Save and reboot if necessary.

---

## 4. Raspberry Pi Setup Script

Save the following as `setup_tailscale_gateway.sh` and run on the Raspberry Pi:

```bash
#!/bin/bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# Enable IP forwarding
sudo sed -i '/net.ipv4.ip_forward/s/^#//g' /etc/sysctl.conf
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Start Tailscale and advertise LAN subnet
sudo tailscale up --advertise-routes=192.168.0.0/24 --accept-dns=false

# Optional: firewall rules to forward traffic
sudo iptables -A FORWARD -i tailscale0 -o eth0 -j ACCEPT
sudo iptables -A FORWARD -i eth0 -o tailscale0 -m state --state RELATED,ESTABLISHED -j ACCEPT

# Optional: NAT if needed
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# Save iptables rules
sudo apt install -y iptables-persistent
sudo netfilter-persistent save

echo "Setup complete. Please approve the advertised route in the Tailscale Admin Console."
```

**Usage:**
```bash
chmod +x setup_tailscale_gateway.sh
./setup_tailscale_gateway.sh
```

---

## 5. Tailscale Admin Console

1. Go to [https://login.tailscale.com/admin/machines](https://login.tailscale.com/admin/machines)
2. Find your Raspberry Pi.
3. Approve the advertised route `192.168.0.0/24`.
4. Confirm the route is **Enabled**.

---

## 6. Verification

### On Raspberry Pi:
```bash
sudo tailscale status
ping 192.168.0.118
curl -k https://192.168.0.118
```

### On Remote Device:
1. Install and log in to Tailscale.
2. Ensure the Raspberry Pi appears in device list.
3. Open in browser:
```
https://192.168.0.118
```
4. Login using iDRAC credentials.

---

## 7. Security Recommendations

- iDRAC access restricted to Tailnet devices only.
- Consider Tailscale ACLs to limit access. Example ACL:

```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["laptop@yourdomain.com"],
      "dst": ["192.168.0.118:443"]
    }
  ]
}
```

- Keep iDRAC and Raspberry Pi firmware updated.
- Use strong passwords and dedicated iDRAC admin accounts.

---

## 8. Maintenance Commands

```bash
# Restart Tailscale service
sudo systemctl restart tailscaled

# Check Tailscale routes and connectivity
tailscale status --peers
tailscale netcheck
```

---

**End of Guide**

This Markdown file includes all scripts and instructions to deploy the Raspberry Pi gateway and can be added to a GitHub repository for reproducible setup.
