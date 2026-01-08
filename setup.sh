#!/bin/bash

if [ ! -f "network.conf" ]; then
    echo "Configuration not found. Running configure.sh..."
    ./configure.sh
fi

./setup_tailscale_gateway.sh