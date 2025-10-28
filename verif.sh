echo "You should use a different internet connection to ensure that this verification is valid!"
sudo tailscale status
ping 192.168.0.118
curl -k https://192.168.0.118
