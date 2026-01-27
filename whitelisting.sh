# On router, create helper script
cat > /usr/bin/zaanet-whitelist << 'EOF'
#!/bin/bash
# ZaaNet Device Whitelisting Helper

if [ -z "$1" ]; then
    echo "Usage: zaanet-whitelist <MAC_ADDRESS>"
    echo ""
    echo "Currently connected devices:"
    arp -a | grep -v "incomplete" | awk '{print "  " $2 " - " $4}'
    echo ""
    echo "Currently whitelisted:"
    uci show nodogsplash | grep trustedmac | cut -d"'" -f2
    exit 1
fi

MAC="$1"

# Validate MAC format
if ! echo "$MAC" | grep -qE '^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$'; then
    echo "Error: Invalid MAC address format"
    echo "Expected: AA:BB:CC:DD:EE:FF"
    exit 1
fi

# Check if already whitelisted
if uci show nodogsplash | grep -q "trustedmac='$MAC'"; then
    echo "Device $MAC is already whitelisted"
    exit 0
fi

# Add to whitelist
uci add_list nodogsplash.@nodogsplash[0].trustedmac="$MAC"
uci commit nodogsplash
/etc/init.d/nodogsplash restart

echo "✓ Device $MAC whitelisted successfully"
echo "This device now has full access without captive portal"
EOF

chmod +x /usr/bin/zaanet-whitelist
