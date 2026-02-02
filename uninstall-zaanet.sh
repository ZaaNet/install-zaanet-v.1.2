#!/bin/bash
# ZaaNet Uninstallation Script
# Completely removes ZaaNet and restores router to clean state

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() {
	printf "%b" "${GREEN}✓${NC} $1\n"
}

print_error() {
	printf "%b" "${RED}✗${NC} $1\n"
}

print_warning() {
	printf "%b" "${YELLOW}⚠${NC} $1\n"
}

print_info() {
	printf "%b" "${BLUE}ℹ${NC} $1\n"
}

print_header() {
	echo ""
	echo "=================================="
	echo "$1"
	echo "=================================="
	echo ""
}

# Check if running as root (POSIX compatible)
if [ "$(id -u)" -ne 0 ]; then
	print_error "This script must be run as root"
	print_info "Please SSH into the router first: ssh root@192.168.8.1"
	exit 1
fi

# Warning
clear
print_header "ZaaNet Uninstallation Script"
echo "This script will:"
echo "  1. Stop and disable nodogsplash"
echo "  2. Remove ZaaNet configuration files"
echo "  3. Remove ZaaNet splash pages"
echo "  4. Restore original nodogsplash config"
echo "  5. Reset WiFi configuration"
echo "  6. Clean up all ZaaNet files"
echo ""
print_warning "WARNING: This will remove ALL ZaaNet configuration!"
print_warning "Your router settings will be reset."
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
	print_info "Uninstallation cancelled"
	exit 0
fi

echo ""
read -p "Do you also want to remove nodogsplash package? (y/n): " remove_package

# Step 1: Stop nodogsplash service
print_header "Step 1: Stopping Services"

if /etc/init.d/nodogsplash status | grep -q "running"; then
	/etc/init.d/nodogsplash stop
	print_success "Stopped nodogsplash service"
else
	print_info "Nodogsplash already stopped"
fi

sleep 2

# Step 2: Disable nodogsplash from boot
print_header "Step 2: Disabling Services"

/etc/init.d/nodogsplash disable 2>/dev/null || true
print_success "Disabled nodogsplash from boot"

# Step 3: Remove ZaaNet configuration and scripts
print_header "Step 3: Removing ZaaNet Configuration and Scripts"

if [ -d /etc/zaanet ]; then
	# Backup before removing
	if [ -f /etc/zaanet/config ]; then
		cp /etc/zaanet/config /tmp/zaanet-config-backup-$(date +%Y%m%d-%H%M%S).txt
		print_info "Backed up config to /tmp/"
	fi
	# Remove update-network-info.sh and collect-metrics.sh if present
	rm -f /etc/zaanet/update-network-info.sh 2>/dev/null
	rm -f /etc/zaanet/collect-metrics.sh 2>/dev/null
	rm -rf /etc/zaanet
	print_success "Removed /etc/zaanet directory and scripts"
else
	print_info "ZaaNet config directory not found"
fi

# Remove cron jobs for ZaaNet scripts
print_info "Cleaning up ZaaNet cron jobs (network info, metrics)..."
if [ -f /etc/crontabs/root ]; then
	grep -v '/etc/zaanet/update-network-info.sh' /etc/crontabs/root |
		grep -v '/etc/zaanet/collect-metrics.sh' >/tmp/root.cron 2>/dev/null || true
	cp /tmp/root.cron /etc/crontabs/root
	rm -f /tmp/root.cron
	print_success "Removed ZaaNet cron jobs from root crontab"
else
	print_info "No root crontab found"
fi

# Step 4: Remove ZaaNet splash pages, assets, and network info
print_header "Step 4: Removing Splash Pages and Assets"

# Backup original splash pages if they exist
if [ -f /etc/nodogsplash/htdocs/splash.html.backup ]; then
	print_info "Original splash page backup found"
fi

# Remove ZaaNet files and new assets
ZAANET_FILES="splash.html session.html config.js script.js session.js styles.css network-info.json"
for file in $ZAANET_FILES; do
	if [ -f "/etc/nodogsplash/htdocs/$file" ]; then
		rm -f "/etc/nodogsplash/htdocs/$file"
		print_success "Removed: $file"
	fi
done
# Remove assets and images directories if present
if [ -d /etc/nodogsplash/htdocs/assets ]; then
	rm -rf /etc/nodogsplash/htdocs/assets
	print_success "Removed: assets directory"
fi
if [ -d /etc/nodogsplash/htdocs/images ]; then
	rm -rf /etc/nodogsplash/htdocs/images
	print_success "Removed: images directory"
fi

# Restore original splash page if backup exists
if ls /etc/nodogsplash/htdocs/splash.html.backup* 1>/dev/null 2>&1; then
	LATEST_BACKUP=$(ls -t /etc/nodogsplash/htdocs/splash.html.backup* 2>/dev/null | head -1)
	if [ -n "$LATEST_BACKUP" ]; then
		cp "$LATEST_BACKUP" /etc/nodogsplash/htdocs/splash.html
		print_success "Restored original splash page from backup"
	fi
else
	print_warning "No original splash page backup found"
fi

# Remove all backups
rm -f /etc/nodogsplash/htdocs/splash.html.backup* 2>/dev/null
rm -f /etc/nodogsplash/htdocs/*.backup.* 2>/dev/null
print_success "Cleaned up backup files"

# Step 5: Remove CGI scripts
print_header "Step 5: Removing CGI Scripts"

if [ -d /www/cgi-bin ]; then
	rm -f /www/cgi-bin/validate-voucher 2>/dev/null
	rm -f /www/cgi-bin/auth 2>/dev/null
	print_success "Removed CGI scripts"
fi

# Step 6: Reset nodogsplash configuration
print_header "Step 6: Resetting Nodogsplash Configuration"

# Backup current config
if [ -f /etc/config/nodogsplash ]; then
	cp /etc/config/nodogsplash /tmp/nodogsplash-config-backup-$(date +%Y%m%d-%H%M%S).txt
	print_info "Backed up nodogsplash config to /tmp/"
fi

# Check if original backup exists
if [ -f /etc/config/nodogsplash.backup ]; then
	cp /etc/config/nodogsplash.backup /etc/config/nodogsplash
	print_success "Restored original nodogsplash configuration"
else
	# Create minimal default config
	cat >/etc/config/nodogsplash <<'EOF'
config nodogsplash
    option enabled '0'
    option gatewayname 'OpenWrt Nodogsplash'
    option gatewayinterface 'br-lan'
    option maxclients '250'
    list authenticated_users 'allow all'
EOF
	print_success "Created minimal nodogsplash configuration (disabled)"
fi

uci commit nodogsplash
print_success "Applied nodogsplash configuration"

# Step 7: Reset WiFi configuration
print_header "Step 7: Resetting WiFi Configuration"

print_warning "This will reset WiFi to require a password"
read -p "Reset WiFi settings? (y/n): " reset_wifi

if [ "$reset_wifi" = "y" ] || [ "$reset_wifi" = "Y" ]; then
	# Check if backup exists
	if [ -f /etc/config/wireless.backup ]; then
		cp /etc/config/wireless.backup /etc/config/wireless
		print_success "Restored original WiFi configuration"
	else
		# Set encryption back to WPA2
		uci set wireless.@wifi-iface[0].encryption='psk2'
		uci set wireless.@wifi-iface[0].key='goodlife'
		uci set wireless.@wifi-iface[0].ssid='GL-XE300'

		uci set wireless.@wifi-iface[1].encryption='psk2' 2>/dev/null
		uci set wireless.@wifi-iface[1].key='goodlife' 2>/dev/null
		uci set wireless.@wifi-iface[1].ssid='GL-XE300-5G' 2>/dev/null

		print_success "Reset WiFi to default settings"
		print_warning "Default password: goodlife"
	fi

	uci commit wireless
	wifi reload
	print_success "Reloaded WiFi configuration"
else
	print_info "Skipped WiFi reset"
fi

# Step 8: Clean up temporary files
print_header "Step 8: Cleaning Up"

rm -rf /tmp/zaanet-install 2>/dev/null
rm -rf /tmp/zaanet-project 2>/dev/null
print_success "Removed temporary files"

# Step 9: Remove nodogsplash package (optional)
if [ "$remove_package" = "y" ] || [ "$remove_package" = "Y" ]; then
	print_header "Step 9: Removing Nodogsplash Package"

	if opkg list-installed | grep -q "^nodogsplash"; then
		opkg remove nodogsplash
		print_success "Removed nodogsplash package"
	else
		print_info "Nodogsplash package not installed"
	fi
else
	print_info "Keeping nodogsplash package installed"
fi

# Step 10: Restart network services
print_header "Step 10: Restarting Network Services"

/etc/init.d/network restart
sleep 5
print_success "Network services restarted"

/etc/init.d/firewall restart
sleep 3
print_success "Firewall restarted"

# Step 11: Create uninstallation log
print_header "Step 11: Creating Uninstallation Log"

cat >/tmp/zaanet-uninstall-$(date +%Y%m%d-%H%M%S).log <<EOF
ZaaNet Uninstallation Log
=========================

Uninstallation Date: $(date)

Removed Items:
--------------
- ZaaNet configuration directory: /etc/zaanet
- ZaaNet splash pages and scripts
- CGI scripts
- Nodogsplash configuration reset
- WiFi configuration reset: $([ "$reset_wifi" = "y" ] && echo "Yes" || echo "No")
- Nodogsplash package removed: $([ "$remove_package" = "y" ] && echo "Yes" || echo "No")

Backups Created:
----------------
$(ls -lh /tmp/*backup* 2>/dev/null | tail -5)

System Status:
--------------
Nodogsplash: $([ "$remove_package" = "y" ] && echo "Removed" || echo "Disabled")
Network: Restarted
Firewall: Restarted

Next Steps:
-----------
1. Verify WiFi connectivity
2. Access admin panel: http://192.168.8.1
3. Reconfigure router settings if needed

Restoration:
------------
If you need to restore ZaaNet:
- Configuration backup: /tmp/zaanet-config-backup-*.txt
- Nodogsplash backup: /tmp/nodogsplash-config-backup-*.txt
- Re-run installation script

EOF

print_success "Uninstallation log created"

# Final status
print_header "Uninstallation Complete!"

echo ""
echo "==========================================="
echo "   ZaaNet Successfully Uninstalled"
echo "==========================================="
echo ""
echo "WHAT WAS REMOVED:"
echo "-----------------"
echo "✓ ZaaNet configuration files"
echo "✓ ZaaNet splash pages"
echo "✓ ZaaNet scripts and assets"
echo "✓ Nodogsplash configuration reset"
if [ "$reset_wifi" = "y" ]; then
	echo "✓ WiFi settings reset"
fi
if [ "$remove_package" = "y" ]; then
	echo "✓ Nodogsplash package removed"
fi
echo ""
echo "BACKUPS CREATED:"
echo "----------------"
ls /tmp/*backup*.txt 2>/dev/null | while read file; do
	echo "  - $(basename $file)"
done
echo ""
echo "CURRENT STATUS:"
echo "---------------"
echo "Network: Running"
echo "Firewall: Running"
echo "Nodogsplash: $([ "$remove_package" = "y" ] && echo "Removed" || echo "Disabled")"
if [ "$reset_wifi" = "y" ]; then
	echo "WiFi: Reset to default (password: goodlife)"
else
	echo "WiFi: Unchanged"
fi
echo ""
echo "ACCESS ROUTER:"
echo "--------------"
echo "Admin Panel: http://192.168.8.1"
if [ "$reset_wifi" = "y" ]; then
	echo "WiFi SSID: GL-XE300 / GL-XE300-5G"
	echo "WiFi Password: goodlife"
fi
echo ""
echo "LOGS:"
echo "-----"
echo "Uninstallation log: $(ls -t /tmp/zaanet-uninstall-*.log 2>/dev/null | head -1)"
echo ""
echo "TO REINSTALL ZAANET:"
echo "--------------------"
echo "Run: sh /tmp/install-zaanet.sh"
echo ""
echo "Thank you for using ZaaNet!"
echo ""
