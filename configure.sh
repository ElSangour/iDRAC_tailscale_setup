#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration file
CONFIG_FILE="network.conf"

# Function to print colored output
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }

# Function to validate IP address
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        IFS='.' read -ra ADDR <<< "$ip"
        for i in "${ADDR[@]}"; do
            if [ "$i" -gt 255 ]; then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# Function to validate CIDR notation
validate_cidr() {
    local cidr=$1
    if [[ $cidr =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        local prefix="${cidr#*/}"
        if [ "$prefix" -ge 0 ] && [ "$prefix" -le 32 ]; then
            return 0
        fi
    fi
    return 1
}

# Function to detect network interfaces
detect_interfaces() {
    print_info "Detecting network interfaces..."
    echo
    local interfaces=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo)
    local count=1
    declare -g -A INTERFACE_MAP
    
    for iface in $interfaces; do
        local status=$(ip link show "$iface" | grep -o "state [A-Z]*" | awk '{print $2}')
        local ip_addr=$(ip -4 addr show "$iface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
        
        INTERFACE_MAP[$count]=$iface
        
        printf "%d) %-10s [%s]" "$count" "$iface" "$status"
        if [ -n "$ip_addr" ]; then
            printf " - IP: %s" "$ip_addr"
        fi
        echo
        ((count++))
    done
    echo
}

# Function to get network info from interface
get_network_info() {
    local iface=$1
    local ip=$(ip -4 addr show "$iface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}/\d+' | head -1)
    local gateway=$(ip route | grep default | grep "$iface" | awk '{print $3}' | head -1)
    
    if [ -n "$ip" ]; then
        echo "DETECTED_IP=$ip"
        echo "DETECTED_GATEWAY=$gateway"
    fi
}

# Function to calculate network address from IP/CIDR
calculate_network() {
    local ip_cidr=$1
    python3 -c "
import ipaddress
net = ipaddress.ip_network('$ip_cidr', strict=False)
print(str(net))
" 2>/dev/null
}

# Banner
clear
echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║         iDRAC Tailscale Gateway Configuration            ║"
echo "║              Interactive Network Setup                    ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo

# Check if config exists
if [ -f "$CONFIG_FILE" ]; then
    print_warning "Existing configuration found: $CONFIG_FILE"
    read -p "Do you want to use existing config? (y/n): " use_existing
    if [[ $use_existing =~ ^[Yy]$ ]]; then
        source "$CONFIG_FILE"
        print_success "Loaded existing configuration"
        echo
        print_info "Current Configuration:"
        cat "$CONFIG_FILE"
        echo
        read -p "Continue with these settings? (y/n): " confirm
        if [[ $confirm =~ ^[Yy]$ ]]; then
            exec ./setup.sh
            exit 0
        fi
    fi
fi

echo "This script will help you configure Tailscale gateway for iDRAC access."
echo "Please have the following information ready:"
echo "  - Network interface name (e.g., eth0, enp0s3)"
echo "  - Your LAN subnet (e.g., 192.168.0.0/24)"
echo "  - iDRAC IP address"
echo "  - Gateway IP address"
echo
read -p "Press Enter to continue..."
echo

# Step 1: Select Network Interface
echo -e "${BLUE}═══ Step 1: Network Interface Selection ═══${NC}"
detect_interfaces

while true; do
    read -p "Select network interface number: " iface_num
    if [ -n "${INTERFACE_MAP[$iface_num]}" ]; then
        NETWORK_INTERFACE="${INTERFACE_MAP[$iface_num]}"
        print_success "Selected interface: $NETWORK_INTERFACE"
        break
    else
        print_error "Invalid selection. Please try again."
    fi
done
echo

# Try to detect current network configuration
print_info "Attempting to detect network configuration on $NETWORK_INTERFACE..."
eval $(get_network_info "$NETWORK_INTERFACE")

# Step 2: Network Configuration
echo -e "${BLUE}═══ Step 2: Network Configuration ═══${NC}"

# Get subnet
while true; do
    if [ -n "$DETECTED_IP" ]; then
        detected_network=$(calculate_network "$DETECTED_IP")
        read -p "Enter LAN subnet in CIDR notation [detected: $detected_network]: " SUBNET
        SUBNET=${SUBNET:-$detected_network}
    else
        read -p "Enter LAN subnet in CIDR notation (e.g., 192.168.0.0/24): " SUBNET
    fi
    
    if validate_cidr "$SUBNET"; then
        print_success "Subnet validated: $SUBNET"
        break
    else
        print_error "Invalid CIDR notation. Please use format: x.x.x.x/yy"
    fi
done
echo

# Get gateway
while true; do
    if [ -n "$DETECTED_GATEWAY" ]; then
        read -p "Enter gateway IP address [detected: $DETECTED_GATEWAY]: " GATEWAY
        GATEWAY=${GATEWAY:-$DETECTED_GATEWAY}
    else
        read -p "Enter gateway IP address (e.g., 192.168.0.1): " GATEWAY
    fi
    
    if validate_ip "$GATEWAY"; then
        print_success "Gateway validated: $GATEWAY"
        break
    else
        print_error "Invalid IP address format"
    fi
done
echo

# Step 3: iDRAC Configuration
echo -e "${BLUE}═══ Step 3: iDRAC Configuration ═══${NC}"

while true; do
    read -p "Enter iDRAC IP address: " IDRAC_IP
    if validate_ip "$IDRAC_IP"; then
        print_success "iDRAC IP validated: $IDRAC_IP"
        break
    else
        print_error "Invalid IP address format"
    fi
done
echo

# Optional: iDRAC MAC address for documentation
read -p "Enter iDRAC MAC address (optional, for documentation): " IDRAC_MAC
echo

# Step 4: Additional Options
echo -e "${BLUE}═══ Step 4: Additional Options ═══${NC}"

read -p "Enable Tailscale SSH access? (y/n) [y]: " enable_ssh
ENABLE_SSH=${enable_ssh:-y}

read -p "Enable NAT/Masquerading? (recommended) (y/n) [y]: " enable_nat
ENABLE_NAT=${enable_nat:-y}

read -p "Install iptables-persistent for firewall rules? (y/n) [y]: " install_iptables
INSTALL_IPTABLES=${install_iptables:-y}
echo

# Step 5: Summary
echo -e "${BLUE}═══ Configuration Summary ═══${NC}"
echo "Network Interface:  $NETWORK_INTERFACE"
echo "LAN Subnet:         $SUBNET"
echo "Gateway:            $GATEWAY"
echo "iDRAC IP:           $IDRAC_IP"
echo "iDRAC MAC:          ${IDRAC_MAC:-N/A}"
echo "Enable SSH:         $ENABLE_SSH"
echo "Enable NAT:         $ENABLE_NAT"
echo "Install iptables:   $INSTALL_IPTABLES"
echo

read -p "Is this configuration correct? (y/n): " confirm
if [[ ! $confirm =~ ^[Yy]$ ]]; then
    print_error "Configuration cancelled. Please run the script again."
    exit 1
fi

# Save configuration
echo "# iDRAC Tailscale Gateway Configuration" > "$CONFIG_FILE"
echo "# Generated on: $(date)" >> "$CONFIG_FILE"
echo >> "$CONFIG_FILE"
echo "NETWORK_INTERFACE=\"$NETWORK_INTERFACE\"" >> "$CONFIG_FILE"
echo "SUBNET=\"$SUBNET\"" >> "$CONFIG_FILE"
echo "GATEWAY=\"$GATEWAY\"" >> "$CONFIG_FILE"
echo "IDRAC_IP=\"$IDRAC_IP\"" >> "$CONFIG_FILE"
echo "IDRAC_MAC=\"$IDRAC_MAC\"" >> "$CONFIG_FILE"
echo "ENABLE_SSH=\"$ENABLE_SSH\"" >> "$CONFIG_FILE"
echo "ENABLE_NAT=\"$ENABLE_NAT\"" >> "$CONFIG_FILE"
echo "INSTALL_IPTABLES=\"$INSTALL_IPTABLES\"" >> "$CONFIG_FILE"

print_success "Configuration saved to $CONFIG_FILE"
echo

# Generate setup script
print_info "Generating setup_tailscale_gateway.sh..."

cat > setup_tailscale_gateway.sh << 'EOFSETUP'
#!/bin/bash

# Load configuration
if [ ! -f "network.conf" ]; then
    echo "Error: network.conf not found. Please run configure.sh first."
    exit 1
fi

source network.conf

echo "Starting Tailscale Gateway Setup..."
echo "Using configuration:"
echo "  Interface: $NETWORK_INTERFACE"
echo "  Subnet: $SUBNET"
echo "  Gateway: $GATEWAY"
echo "  iDRAC IP: $IDRAC_IP"
echo

# Update system
echo "Updating system packages..."
sudo apt update && sudo apt upgrade -y

# Install Tailscale
echo "Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh

# Enable IP forwarding
echo "Enabling IP forwarding..."
sudo sed -i '/net.ipv4.ip_forward/s/^#//g' /etc/sysctl.conf
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
fi
sudo sysctl -p

# Build Tailscale command
TAILSCALE_CMD="sudo tailscale up --advertise-routes=$SUBNET --accept-routes=true"
if [[ $ENABLE_SSH =~ ^[Yy]$ ]]; then
    TAILSCALE_CMD="$TAILSCALE_CMD --ssh"
fi

# Start Tailscale and advertise subnet
echo "Starting Tailscale and advertising subnet $SUBNET..."
$TAILSCALE_CMD

# Configure firewall rules
echo "Configuring firewall rules..."
sudo iptables -A FORWARD -i tailscale0 -o $NETWORK_INTERFACE -j ACCEPT
sudo iptables -A FORWARD -i $NETWORK_INTERFACE -o tailscale0 -m state --state RELATED,ESTABLISHED -j ACCEPT

# Optional: NAT
if [[ $ENABLE_NAT =~ ^[Yy]$ ]]; then
    echo "Enabling NAT/Masquerading..."
    sudo iptables -t nat -A POSTROUTING -o $NETWORK_INTERFACE -j MASQUERADE
fi

# Save iptables rules
if [[ $INSTALL_IPTABLES =~ ^[Yy]$ ]]; then
    echo "Installing and saving iptables rules..."
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
echo "2. Find your device and approve the advertised route: $SUBNET"
echo "3. Run ./verify.sh to test connectivity"
echo
echo "Your iDRAC should be accessible at: https://$IDRAC_IP"
echo
EOFSETUP

chmod +x setup_tailscale_gateway.sh
print_success "Generated setup_tailscale_gateway.sh"

# Generate verification script
print_info "Generating verify.sh..."

cat > verify.sh << EOFVERIFY
#!/bin/bash

# Load configuration
if [ ! -f "network.conf" ]; then
    echo "Error: network.conf not found."
    exit 1
fi

source network.conf

echo "========================================="
echo "Tailscale Gateway Verification"
echo "========================================="
echo
echo "IMPORTANT: Use a different internet connection to ensure valid verification!"
echo
echo "Press Enter to continue..."
read

echo "1. Checking Tailscale status..."
sudo tailscale status
echo

echo "2. Testing connectivity to iDRAC ($IDRAC_IP)..."
ping -c 4 $IDRAC_IP
echo

echo "3. Testing HTTPS access to iDRAC..."
curl -k https://$IDRAC_IP
echo

echo "========================================="
echo "Verification complete!"
echo "========================================="
echo
echo "If all tests passed, you can access iDRAC at:"
echo "  https://$IDRAC_IP"
echo
echo "From any device on your Tailscale network."
EOFVERIFY

chmod +x verify.sh
print_success "Generated verify.sh"

# Generate README
print_info "Generating dynamic README.md..."

cat > README.md << EOFREADME
# Dell iDRAC Remote Access via Tailscale Gateway

This repository provides an automated setup for secure remote access to Dell iDRAC management interfaces using Tailscale VPN and a Linux gateway (e.g., Raspberry Pi).

## Your Current Configuration

| Component | Value |
|-----------|-------|
| Network Interface | $NETWORK_INTERFACE |
| LAN Subnet | $SUBNET |
| Gateway | $GATEWAY |
| iDRAC IP | $IDRAC_IP |
| iDRAC MAC | ${IDRAC_MAC:-Not specified} |

## Quick Start

### 1. Configure Your Setup

Run the interactive configuration:

\`\`\`bash
chmod +x configure.sh
./configure.sh
\`\`\`

This will:
- Detect your network interfaces
- Prompt for network settings
- Validate all inputs
- Generate configuration files

### 2. Run the Setup

Execute the generated setup script:

\`\`\`bash
./setup.sh
\`\`\`

This will:
- Install Tailscale
- Configure IP forwarding
- Set up firewall rules
- Advertise your subnet to Tailscale

### 3. Approve the Route

1. Visit [Tailscale Admin Console](https://login.tailscale.com/admin/machines)
2. Find your gateway device
3. Approve the advertised route: **$SUBNET**

### 4. Verify Connectivity

From a different network:

\`\`\`bash
./verify.sh
\`\`\`

Or manually test:

\`\`\`bash
# Check Tailscale status
tailscale status

# Ping iDRAC
ping $IDRAC_IP

# Access web interface
curl -k https://$IDRAC_IP
\`\`\`

## Files in This Repository

- **configure.sh** - Interactive configuration wizard
- **setup.sh** - Main setup orchestrator
- **setup_tailscale_gateway.sh** - Generated setup script
- **verify.sh** - Connection verification script
- **network.conf** - Your network configuration (auto-generated)
- **README.md** - This file (auto-generated)

## Reconfiguration

To change your network settings:

\`\`\`bash
./configure.sh
\`\`\`

The script will detect existing configuration and offer to update it.

## Security Recommendations

✓ Use Tailscale ACLs to restrict access
✓ Keep iDRAC firmware updated
✓ Use strong passwords
✓ Enable MFA on Tailscale
✓ Regularly review Tailscale device list

### Example Tailscale ACL

\`\`\`json
{
  "acls": [
    {
      "action": "accept",
      "src": ["user@example.com"],
      "dst": ["$IDRAC_IP:443"]
    }
  ]
}
\`\`\`

## Troubleshooting

### Route not working
\`\`\`bash
# Check Tailscale status
sudo tailscale status

# Verify IP forwarding
cat /proc/sys/net/ipv4/ip_forward  # Should be 1

# Check iptables rules
sudo iptables -L -n -v
sudo iptables -t nat -L -n -v
\`\`\`

### Can't reach iDRAC
\`\`\`bash
# From gateway, test local connectivity
ping $IDRAC_IP
curl -k https://$IDRAC_IP

# Check if route is approved in Tailscale admin
tailscale status --peers
\`\`\`

### Restart services
\`\`\`bash
# Restart Tailscale
sudo systemctl restart tailscaled

# Reapply firewall rules
sudo netfilter-persistent reload
\`\`\`

## License

Apache License 2.0 - See LICENSE file for details.

## Configuration Date

Generated on: $(date)

---

**Note:** This README and configuration were automatically generated by configure.sh
EOFREADME

print_success "Generated README.md"
echo

# Generate setup.sh wrapper
cat > setup.sh << 'EOFWRAPPER'
#!/bin/bash

# Check if configuration exists
if [ ! -f "network.conf" ]; then
    echo "Configuration not found. Running configure.sh first..."
    ./configure.sh
else
    # Run the setup
    ./setup_tailscale_gateway.sh
fi
EOFWRAPPER

chmod +x setup.sh
print_success "Updated setup.sh"

# Final message
echo
echo -e "${GREEN}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║            Configuration Complete!                        ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo
print_info "Generated files:"
echo "  ✓ network.conf - Your configuration"
echo "  ✓ setup_tailscale_gateway.sh - Dynamic setup script"
echo "  ✓ verify.sh - Verification script"
echo "  ✓ README.md - Updated documentation"
echo
print_info "Next steps:"
echo "  1. Review network.conf"
echo "  2. Run ./setup.sh to install and configure"
echo "  3. Approve the route in Tailscale admin console"
echo "  4. Run ./verify.sh to test connectivity"
echo
print_warning "Make sure to approve the subnet route in Tailscale!"
echo "  URL: https://login.tailscale.com/admin/machines"
echo "  Route to approve: $SUBNET"
echo