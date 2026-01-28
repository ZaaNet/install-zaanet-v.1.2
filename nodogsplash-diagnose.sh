#!/bin/sh
# Nodogsplash quick diagnostic script

set -e

print_section() {
  echo "\n=============================="
  echo "$1"
  echo "==============================\n"
}

print_section "1. Nodogsplash Service Status"
/etc/init.d/nodogsplash status

print_section "2. Gateway Interface"
echo -n "gatewayinterface: "
uci get nodogsplash.@nodogsplash[0].gatewayinterface 2>/dev/null || echo "Not set! Should be br-lan or your LAN interface."

print_section "3. WiFi Network Mode"
echo -n "encryption: "
uci get wireless.@wifi-iface[0].encryption 2>/dev/null

print_section "4. Splash Page File"
ls -lh /etc/nodogsplash/htdocs/splash.html 2>/dev/null || echo "splash.html is missing!"

print_section "5. Authenticated/Whitelisted Clients"
ndsctl clients 2>/dev/null || echo "ndsctl not found or not running."

print_section "6. Nodogsplash Firewall Rules"
iptables -L | grep -i nodogsplash || echo "No Nodogsplash rules found in iptables."

print_section "7. Nodogsplash Log Messages (last 20)"
logread | grep nodogsplash | tail -20

print_section "8. UCI Config Dump (nodogsplash)"
cat /etc/config/nodogsplash

echo "\nDiagnostics complete. Review output above for errors or misconfigurations."
