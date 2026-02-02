#!/bin/bash
set -eu # Exit on any error and treat unset variables as errors
# ZaaNet Router Installation Script
# Version: 1.4.1 - GitHub Download (Fixed)
# Platform: GL.iNet GL-XE300 with OpenWrt 22.03.4

# Configuration
GITHUB_REPO="ZaaNet/public-splash" # Public splash page repository
GITHUB_BRANCH="main"
GITHUB_RAW_BASE="https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}"
TMP_DIR="/tmp/zaanet-install"
PROJECT_DIR="${TMP_DIR}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions for colored output
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

# Cleanup function
cleanup() {
	print_info "Cleaning up temporary files..."
	rm -rf "$TMP_DIR"
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Check if running as root (POSIX compatible)
if [ "$(id -u)" -ne 0 ]; then
	print_error "This script must be run as root"
	print_info "Please SSH into the router first: ssh root@192.168.8.1"
	exit 1
fi

# Welcome message
clear
print_header "ZaaNet Router Installation Script v1.4.1"
echo "This script will:"
echo "  1. Download ZaaNet project files from GitHub"
echo "  2. Install and configure nodogsplash"
echo "  3. Set up your router with your credentials"
echo ""
echo "GitHub Repository: ${GITHUB_REPO}"
echo "Branch: ${GITHUB_BRANCH}"
echo ""
read -rp "Press Enter to continue or Ctrl+C to cancel..."

# Step 1: Verify internet connection
print_header "Step 1: Verifying Internet Connection"

if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
	print_success "Internet connection verified"
else
	print_error "No internet connection detected"
	print_info "Please configure internet access first:"
	print_info "  - Web Interface: http://192.168.8.1"
	print_info "  - Go to: Internet → Ethernet or Cellular"
	exit 1
fi

# Step 2: Check for required tools
print_header "Step 2: Checking Required Tools"

# Check for wget or curl
if command -v wget >/dev/null 2>&1; then
	DOWNLOAD_CMD="wget -O"
	print_success "wget found"
elif command -v curl >/dev/null 2>&1; then
	DOWNLOAD_CMD="curl -L -o"
	print_success "curl found"
else
	print_error "Neither wget nor curl found"
	print_info "Installing wget..."
	if opkg update >/dev/null 2>&1 && opkg install wget >/dev/null 2>&1; then
		DOWNLOAD_CMD="wget -O"
		print_success "wget installed"
	else
		print_error "Failed to install wget"
		exit 1
	fi
fi

# Note: tar is not required for direct file downloads

# Step 3: Download project files from GitHub
print_header "Step 3: Downloading Project Files"

# Create temporary directory
mkdir -p "${PROJECT_DIR}"
print_success "Created temporary directory"

# List of files to download from the repository (space-separated, POSIX-compatible)
FILES_TO_DOWNLOAD="splash.html session.html config.js script.js session.js styles.css collect-metrics.sh"

print_info "Downloading files from GitHub..."
print_info "Repository: ${GITHUB_REPO}"
print_info "Branch: ${GITHUB_BRANCH}"
echo ""

# Download each file
FAILED_FILES=""

for file in ${FILES_TO_DOWNLOAD}; do
	FILE_URL="${GITHUB_RAW_BASE}/${file}"
	FILE_PATH="${PROJECT_DIR}/${file}"

	print_info "Downloading: $file"

	if ${DOWNLOAD_CMD} "${FILE_PATH}" "${FILE_URL}" >/dev/null 2>&1; then
		# Verify file was downloaded and is not empty
		if [ -f "${FILE_PATH}" ] && [ -s "$FILE_PATH" ]; then
			# Additional validation: check if file looks valid based on extension
			case "$file" in
			*.html)
				if grep -q "<html" "$FILE_PATH" 2>/dev/null || grep -q "<!DOCTYPE" "$FILE_PATH" 2>/dev/null; then
					print_success "Downloaded: $file"
				else
					print_warning "Downloaded $file but content looks invalid"
					FAILED_FILES="$FAILED_FILES $file"
				fi
				;;
			*.js)
				if grep -qE "(function|const|let|var|//)" "$FILE_PATH" 2>/dev/null; then
					print_success "Downloaded: $file"
				else
					print_warning "Downloaded $file but content looks invalid"
					FAILED_FILES="$FAILED_FILES $file"
				fi
				;;
			*.css)
				if grep -qE "(\{|\}|:|;)" "$FILE_PATH" 2>/dev/null; then
					print_success "Downloaded: $file"
				else
					print_warning "Downloaded $file but content looks invalid"
					FAILED_FILES="$FAILED_FILES $file"
				fi
				;;
			*)
				print_success "Downloaded: $file"
				;;
			esac
		else
			print_error "Failed: $file (file is empty or missing)"
			FAILED_FILES="$FAILED_FILES $file"
			rm -f "$FILE_PATH"
		fi
	else
		print_error "Failed: $file"
		FAILED_FILES="$FAILED_FILES $file"
	fi
done

echo ""

# Check if all files were downloaded successfully
if [ -n "$FAILED_FILES" ]; then
	print_error "Failed to download some files"
	print_info "Failed files:${FAILED_FILES}"
	print_info "Please check:"
	print_info "  - Repository exists: $GITHUB_REPO"
	print_info "  - Branch exists: $GITHUB_BRANCH"
	print_info "  - Repository is public"
	print_info "  - Files exist in the repository"
	exit 1
fi

# Verify required files exist
REQUIRED_FILES="splash.html config.js script.js"
MISSING_FILES=""

for file in $REQUIRED_FILES; do
	if [ -f "$PROJECT_DIR/$file" ]; then
		print_success "Required file found: $file"
	else
		print_warning "Required file missing: $file"
		MISSING_FILES="$MISSING_FILES $file"
	fi
done

if [ -n "$MISSING_FILES" ]; then
	print_error "Required files are missing"
	print_info "Missing files:${MISSING_FILES}"
	exit 1
fi

# List downloaded files
print_info "Downloaded files:"
for file in "$PROJECT_DIR"/*.{html,js,css,sh}; do
	if [ -f "$file" ]; then
		size=$(stat -c '%s' "${file}" 2>/dev/null || stat -f '%z' "${file}" 2>/dev/null || echo 0)
		size=$(awk -v s="$size" 'BEGIN {
			if (s>=1024*1024*1024) printf "%.1fG", s/1024/1024/1024
			else if (s>=1024*1024) printf "%.1fM", s/1024/1024
			else if (s>=1024) printf "%.1fK", s/1024
			else printf "%s", s
		}')
		echo "  $(basename "$file") ($size)"
	fi
done

# Step 4: Update package lists
print_header "Step 4: Updating Package Lists"

print_info "Running: opkg update"
if opkg update >/dev/null 2>&1; then
	print_success "Package lists updated"
else
	print_warning "Failed to update package lists (continuing anyway)"
fi

# Step 5: Check available space
print_header "Step 5: Checking Available Space"

AVAILABLE_KB=$(df /overlay | awk 'NR==2 {print $4}')
AVAILABLE_MB=$((AVAILABLE_KB / 1024))

if [ "$AVAILABLE_MB" -lt 3 ]; then
	print_error "Insufficient space: ${AVAILABLE_MB}MB available"
	print_info "At least 3MB free space required on /overlay"
	exit 1
else
	print_success "Available space: ${AVAILABLE_MB}MB"
fi

# Step 6: Install nodogsplash
print_header "Step 6: Installing Nodogsplash"

if opkg list-installed 2>/dev/null | grep -q "^nodogsplash"; then
	print_warning "Nodogsplash already installed"
	NODOGSPLASH_VERSION=$(opkg list-installed | grep nodogsplash | awk '{print $3}')
	print_info "Version: $NODOGSPLASH_VERSION"
else
	print_info "Installing nodogsplash..."
	if opkg install nodogsplash >/dev/null 2>&1; then
		print_success "Nodogsplash installed successfully"
		NODOGSPLASH_VERSION=$(opkg list-installed | grep nodogsplash | awk '{print $3}')
		print_info "Installed version: $NODOGSPLASH_VERSION"
	else
		print_error "Failed to install nodogsplash"
		exit 1
	fi
fi

# Step 6.5: Fix iptables-legacy for Nodogsplash
print_header "Step 6.5: Applying iptables-legacy Fix"

fix_iptables_legacy() {
	print_info "Ensuring legacy iptables binaries are installed..."

	# Install legacy packages if missing
	for pkg in iptables-legacy ip6tables-legacy arptables-legacy ebtables-legacy; do
		if ! opkg list-installed 2>/dev/null | grep -q "^$pkg"; then
			print_info "Installing $pkg..."
			if opkg install "$pkg" >/dev/null 2>&1; then
				print_success "$pkg installed"
			else
				print_warning "Failed to install $pkg"
			fi
		fi
	done

	print_info "Updating symlinks to use legacy binaries..."
	ln -sf /usr/sbin/iptables-legacy /usr/sbin/iptables
	ln -sf /usr/sbin/iptables-legacy /usr/sbin/iptables-restore
	ln -sf /usr/sbin/iptables-legacy /usr/sbin/iptables-save
	ln -sf /usr/sbin/ip6tables-legacy /usr/sbin/ip6tables
	ln -sf /usr/sbin/ip6tables-legacy /usr/sbin/ip6tables-restore
	ln -sf /usr/sbin/ip6tables-legacy /usr/sbin/ip6tables-save
	ln -sf /usr/sbin/arptables-legacy /usr/sbin/arptables
	ln -sf /usr/sbin/arptables-legacy /usr/sbin/arptables-restore
	ln -sf /usr/sbin/arptables-legacy /usr/sbin/arptables-save
	ln -sf /usr/sbin/ebtables-legacy /usr/sbin/ebtables
	ln -sf /usr/sbin/ebtables-legacy /usr/sbin/ebtables-restore
	ln -sf /usr/sbin/ebtables-legacy /usr/sbin/ebtables-save

	# Optional: Comment out problematic VPN rules if present
	FW_SCRIPT="/etc/firewall.vpn_server_policy.sh"
	if [ -f "$FW_SCRIPT" ]; then
		sed -i 's/^\(.*-j VPN_SER_POLICY.*\)$/#\1/' "$FW_SCRIPT"
		print_info "Commented VPN rules in firewall script to prevent conflicts"
	fi

	# Restart firewall and Nodogsplash
	/etc/init.d/firewall restart >/dev/null 2>&1 && print_success "Firewall restarted"
	/etc/init.d/nodogsplash restart >/dev/null 2>&1 && print_success "Nodogsplash restarted"
}

# Execute the fix
fix_iptables_legacy

# Step 7: Generate Router ID
print_header "Step 7: Generating Router Identifier"

# Detect first non-loopback interface with carrier
MAIN_IFACE=""
if command -v ip >/dev/null 2>&1; then
	MAIN_IFACE=$(ip -o link show up | awk -F': ' '$2!="lo"{print $2; exit}')
fi

# Fallback: use eth0 if detection fails
if [ -z "$MAIN_IFACE" ]; then
	if [ -d /sys/class/net/eth0 ]; then
		MAIN_IFACE="eth0"
	else
		# Last resort: iterate through available interfaces
		for iface in /sys/class/net/*/; do
			iface_name=$(basename "$iface")
			if [ "$iface_name" != "lo" ]; then
				MAIN_IFACE="$iface_name"
				break
			fi
		done
	fi
fi

# Fallback to hostname hash if MAC address unavailable
MAC_ADDR=""
if [ -n "$MAIN_IFACE" ] && [ -f "/sys/class/net/$MAIN_IFACE/address" ]; then
	MAC_ADDR=$(cat "/sys/class/net/$MAIN_IFACE/address")
else
	# Fallback: use hostname hash
	MAC_ADDR=$(hostname)
fi

# Use md5sum or sha1sum for hash
HASH_CMD=""
if command -v md5sum >/dev/null 2>&1; then
	HASH_CMD="md5sum"
elif command -v md5 >/dev/null 2>&1; then
	HASH_CMD="md5"
elif command -v sha1sum >/dev/null 2>&1; then
	HASH_CMD="sha1sum"
else
	print_warning "No hash command found, using simple timestamp-based ID"
	ROUTER_ID="ZN-$(date +%s | tail -c 12)"
fi

# Generate router ID from MAC or hostname hash
if [ -n "$HASH_CMD" ]; then
	if [ "$HASH_CMD" = "md5" ]; then
		ROUTER_ID="ZN-$(echo -n "$MAC_ADDR" | md5 | cut -c1-12 | tr '[:lower:]' '[:upper:]')"
	else
		ROUTER_ID="ZN-$(echo -n "$MAC_ADDR" | $HASH_CMD | cut -c1-12 | tr '[:lower:]' '[:upper:]')"
	fi
fi

print_success "Generated Router ID: $ROUTER_ID"
echo ""
print_warning "IMPORTANT: Save this Router ID!"
print_info "You will need it to register on the ZaaNet platform"
echo ""

# Step 8: Collect user configuration
print_header "Step 8: Configuration Information"

echo "Please provide your ZaaNet credentials."
echo ""

# Contract ID
while true; do
	echo -n "Enter your Smart Contract ID: "
	read -r CONTRACT_ID

	if [ -z "${CONTRACT_ID}" ]; then
		print_error "Contract ID cannot be empty"
		continue
	fi

	# Contract ID accepted (no format validation)
	print_success "Contract ID accepted"
	break
done

echo ""

# ZaaNet Secret
while true; do
	echo -n "Enter your ZaaNet Secret Key: "
	# Use stty for password input if available
	if command -v stty >/dev/null 2>&1; then
		stty -echo
		read -r ZAANET_SECRET
		stty echo
		echo ""
	else
		# Fallback to regular read if stty not available
		read -r ZAANET_SECRET
	fi

	if [ -z "$ZAANET_SECRET" ]; then
		print_error "Secret key cannot be empty"
		continue
	fi

	# Get string length (POSIX-compatible)
	SECRET_LEN=$(printf '%s' "${ZAANET_SECRET}" | wc -c)
	if [ "${SECRET_LEN}" -lt 16 ]; then
		print_warning "Secret key is too short (less than 16 characters)"
		echo -n "Use anyway? (y/n): "
		read -r confirm
		if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
			break
		fi
	else
		print_success "Secret key accepted"
		break
	fi
done

echo ""

# Main Server URL (auto-set)
MAIN_SERVER="https://api.zaanet.xyz"
print_info "Main Server: $MAIN_SERVER"

echo ""

# WiFi SSID
echo -n "Enter WiFi SSID [ZaaNet]: "
read -r WIFI_SSID
WIFI_SSID=${WIFI_SSID:-ZaaNet}
print_info "Using SSID: $WIFI_SSID"

echo ""

# Confirmation
print_header "Configuration Summary"
echo "Router ID:   $ROUTER_ID"
echo "Contract ID: $CONTRACT_ID"
echo "Secret Key:  [hidden for security]"
echo "Main Server: $MAIN_SERVER"
echo "WiFi SSID:   $WIFI_SSID"
echo ""
echo -n "Is this correct? (y/n): "
read -r confirm

if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
	print_error "Installation cancelled"
	exit 1
fi

# Step 8.5: Identify Admin Device
print_header "Step 8.5: Admin Device Whitelisting"

echo "Do you want to whitelist this device (admin access)?"
echo "Whitelisted devices bypass captive portal and access admin panel directly."
echo ""

# Try to detect the device making the SSH connection
ADMIN_MAC=""
ADMIN_IP=""

# Get SSH client IP from SSH_CONNECTION environment variable or WHO output
if [ -n "${SSH_CONNECTION-}" ]; then
	ADMIN_IP=$(echo "$SSH_CONNECTION" | awk '{print $1}')
	print_info "Detected SSH connection from: $ADMIN_IP"
elif command -v who >/dev/null 2>&1; then
	ADMIN_IP=$(who -m | awk '{print $5}' | tr -d '()')
	if [ -n "$ADMIN_IP" ]; then
		print_info "Detected connection from: $ADMIN_IP"
	fi
fi

# Try to get MAC address if we have IP
if [ -n "$ADMIN_IP" ]; then
	# Try multiple methods to get MAC address
	ADMIN_MAC=""

	# Method 1: Try ip neigh show (neighbor table)
	if command -v ip >/dev/null 2>&1; then
		ADMIN_MAC=$(ip neigh show | grep "$ADMIN_IP" | grep -v "FAILED" | awk '{print $5}' | head -1)
	fi

	# Method 2: If not found, try to ping and refresh neighbor table
	if [ -z "$ADMIN_MAC" ] || [ "$ADMIN_MAC" = "00:00:00:00:00:00" ]; then
		print_info "Refreshing neighbor table..."
		ping -c 2 -W 2 "$ADMIN_IP" >/dev/null 2>&1 || true
		sleep 2
		if command -v ip >/dev/null 2>&1; then
			ADMIN_MAC=$(ip neigh show | grep "$ADMIN_IP" | grep -v "FAILED" | awk '{print $5}' | head -1)
		fi
	fi

	# Method 3: Try /proc/net/arp (ARP cache)
	if [ -z "$ADMIN_MAC" ] || [ "$ADMIN_MAC" = "00:00:00:00:00:00" ]; then
		ADMIN_MAC=$(cat /proc/net/arp 2>/dev/null | grep "$ADMIN_IP" | awk '{print $4}' | head -1)
	fi

	# Method 4: Try DHCP leases (if device got IP via DHCP)
	if [ -z "$ADMIN_MAC" ] || [ "$ADMIN_MAC" = "00:00:00:00:00:00" ]; then
		if [ -f /tmp/dhcp.leases ]; then
			ADMIN_MAC=$(grep "$ADMIN_IP" /tmp/dhcp.leases | awk '{print $2}' | head -1)
		elif [ -f /var/lib/dhcp/dhcpd.leases ]; then
			ADMIN_MAC=$(grep -A 10 "$ADMIN_IP" /var/lib/dhcp/dhcpd.leases | grep "hardware ethernet" | awk '{print $3}' | tr -d ';' | head -1)
		fi
	fi

	# Validate MAC address format
	if [ -n "$ADMIN_MAC" ] && [ "$ADMIN_MAC" != "00:00:00:00:00:00" ]; then
		# Check if it's a valid MAC format (simple pattern matching)
		case "$ADMIN_MAC" in
		[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F])
			# Convert to lowercase for consistency
			ADMIN_MAC=$(printf '%s' "$ADMIN_MAC" | tr '[:upper:]' '[:lower:]')
			print_success "Detected device MAC: $ADMIN_MAC"
			echo ""
			echo "Device Information:"
			echo "  IP Address: $ADMIN_IP"
			echo "  MAC Address: $ADMIN_MAC"
			echo ""
			echo -n "Whitelist this device? (y/n): "
			read -r whitelist_confirm

			if [ "$whitelist_confirm" = "y" ] || [ "$whitelist_confirm" = "Y" ]; then
				print_success "Admin device will be whitelisted"
			else
				ADMIN_MAC=""
				print_info "Admin device will NOT be whitelisted"
			fi
			;;
		*)
			print_warning "Invalid MAC format detected: $ADMIN_MAC"
			ADMIN_MAC=""
			;;
		esac
	fi
fi

# If still not found, offer manual entry
if [ -z "$ADMIN_MAC" ] || [ "$ADMIN_MAC" = "00:00:00:00:00:00" ]; then
	print_warning "Could not detect MAC address automatically"
	echo ""
	echo "Currently connected devices:"
	if command -v ip >/dev/null 2>&1; then
		ip neigh show | grep -v "FAILED" | awk '{print "  IP: " $1 " - MAC: " $5}' || echo "  No devices detected"
	else
		cat /proc/net/arp 2>/dev/null | awk 'NR>1 {print "  IP: " $1 " - MAC: " $4}' || echo "  No devices detected"
	fi
	echo ""
	echo -n "Enter MAC address to whitelist (format: aa:bb:cc:dd:ee:ff) or press Enter to skip: "
	read -r ADMIN_MAC

	# If user entered something, validate it
	if [ -n "$ADMIN_MAC" ]; then
		# Convert to lowercase for consistency
		ADMIN_MAC=$(printf '%s' "$ADMIN_MAC" | tr '[:upper:]' '[:lower:]')

		# Basic MAC validation - accept both uppercase and lowercase
		case "$ADMIN_MAC" in
		[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f])
			print_success "MAC address accepted: $ADMIN_MAC"
			;;
		*)
			print_warning "Invalid MAC format, skipping whitelisting"
			ADMIN_MAC=""
			;;
		esac
	else
		print_info "Skipping admin device whitelisting"
	fi
fi

echo ""

# Step 9: Create directory structure
print_header "Step 9: Creating Directory Structure"

mkdir -p /etc/zaanet
chmod 755 /etc/zaanet
print_success "Created /etc/zaanet"

# Step 10: Create configuration file
print_header "Step 10: Creating Configuration File"

cat >/etc/zaanet/config <<EOF
# ZaaNet Router Configuration
# Generated: $(date)

# Unique router identifier
ROUTER_ID="$ROUTER_ID"

# ZaaNet smart contract ID
CONTRACT_ID="$CONTRACT_ID"

# Main server URL
MAIN_SERVER="$MAIN_SERVER"

# ZaaNet secret key (keep secure!)
ZAANET_SECRET="$ZAANET_SECRET"

# WiFi SSID
WIFI_SSID="$WIFI_SSID"
EOF

chmod 600 /etc/zaanet/config
print_success "Configuration file created"
print_info "Location: /etc/zaanet/config"

# Step 11: Deploy project files
print_header "Step 11: Deploying Project Files"

# Create backup directory for htdocs (if any previous files exist)
BACKUP_DIR="/etc/nodogsplash/htdocs.backup.$(date +%Y%m%d-%H%M%S)"
if [ -d /etc/nodogsplash/htdocs ] && [ "$(find /etc/nodogsplash/htdocs -mindepth 1 2>/dev/null | wc -l)" -gt 0 ]; then
	cp -r /etc/nodogsplash/htdocs "$BACKUP_DIR"
	print_info "Previous htdocs backed up to: $BACKUP_DIR"
fi

# Clear htdocs before deploying new files (BusyBox compatible)
print_info "Clearing /etc/nodogsplash/htdocs/ before deploying new files..."
if [ -d /etc/nodogsplash/htdocs ]; then
	find /etc/nodogsplash/htdocs/ -mindepth 1 ! -name ".gitkeep" -exec rm -rf {} + 2>/dev/null || true
fi
print_success "/etc/nodogsplash/htdocs/ cleared."

# Ensure directory exists
mkdir -p /etc/nodogsplash/htdocs

print_info "Copying project files to /etc/nodogsplash/htdocs/..."

DEPLOYMENT_FAILED=false

# Copy all HTML files
for file in "$PROJECT_DIR"/*.html; do
	if [ -f "$file" ]; then
		filename=$(basename "$file")
		if cp "$file" /etc/nodogsplash/htdocs/; then
			if [ -f "/etc/nodogsplash/htdocs/$filename" ] && [ -s "/etc/nodogsplash/htdocs/$filename" ]; then
				print_success "Deployed: $filename"
			else
				print_error "Failed to deploy: $filename (file empty or missing after copy)"
				DEPLOYMENT_FAILED=true
			fi
		else
			print_error "Failed to copy: $filename"
			DEPLOYMENT_FAILED=true
		fi
	fi
done

# Copy all JS files
for file in "$PROJECT_DIR"/*.js; do
	if [ -f "$file" ]; then
		filename=$(basename "$file")
		if cp "$file" /etc/nodogsplash/htdocs/; then
			if [ -f "/etc/nodogsplash/htdocs/$filename" ] && [ -s "/etc/nodogsplash/htdocs/$filename" ]; then
				print_success "Deployed: $filename"
			else
				print_error "Failed to deploy: $filename (file empty or missing after copy)"
				DEPLOYMENT_FAILED=true
			fi
		else
			print_error "Failed to copy: $filename"
			DEPLOYMENT_FAILED=true
		fi
	fi
done

# Copy all CSS files
for file in "$PROJECT_DIR"/*.css; do
	if [ -f "$file" ]; then
		filename=$(basename "$file")
		if cp "$file" /etc/nodogsplash/htdocs/; then
			if [ -f "/etc/nodogsplash/htdocs/$filename" ] && [ -s "/etc/nodogsplash/htdocs/$filename" ]; then
				print_success "Deployed: $filename"
			else
				print_error "Failed to deploy: $filename (file empty or missing after copy)"
				DEPLOYMENT_FAILED=true
			fi
		else
			print_error "Failed to copy: $filename"
			DEPLOYMENT_FAILED=true
		fi
	fi
done

# Copy shell scripts if any
for file in "$PROJECT_DIR"/*.sh; do
	if [ -f "$file" ]; then
		filename=$(basename "$file")
		# Skip the install script itself
		if [ "$filename" != "install.sh" ] && [ "$filename" != "install-zaanet.sh" ]; then
			if cp "$file" /etc/nodogsplash/htdocs/; then
				chmod 755 "/etc/nodogsplash/htdocs/$filename"
				print_success "Deployed: $filename"
			else
				print_warning "Failed to copy: $filename (non-critical)"
			fi
		fi
	fi
done

# If deployment failed, try direct download as fallback
if [ "$DEPLOYMENT_FAILED" = "true" ] || [ ! -f "/etc/nodogsplash/htdocs/splash.html" ]; then
	print_warning "Direct file copy failed, attempting direct download fallback..."

	# Critical files to download directly from GitHub if local copy fails
	CRITICAL_FILES="splash.html styles.css script.js session.html session.js config.js"

	for file in $CRITICAL_FILES; do
		if [ ! -f "/etc/nodogsplash/htdocs/$file" ] || [ ! -s "/etc/nodogsplash/htdocs/$file" ]; then
			print_info "Downloading $file from GitHub..."
			FILE_URL="${GITHUB_RAW_BASE}/${file}"

			if $DOWNLOAD_CMD "/etc/nodogsplash/htdocs/$file" "$FILE_URL" >/dev/null 2>&1; then
				if [ -f "/etc/nodogsplash/htdocs/$file" ] && [ -s "/etc/nodogsplash/htdocs/$file" ]; then
					print_success "Downloaded and deployed: $file"
				else
					print_error "Downloaded file is empty: $file"
				fi
			else
				print_warning "Failed to download: $file (continuing anyway)"
			fi
		fi
	done
fi

# Copy assets directory if exists
if [ -d "$PROJECT_DIR/assets" ]; then
	mkdir -p /etc/nodogsplash/htdocs/assets
	if cp -r "$PROJECT_DIR/assets"/* /etc/nodogsplash/htdocs/assets/ 2>/dev/null; then
		print_success "Deployed: assets directory"
	else
		print_warning "Failed to deploy assets directory (may not exist)"
	fi
fi

# Copy images directory if exists
if [ -d "$PROJECT_DIR/images" ]; then
	mkdir -p /etc/nodogsplash/htdocs/images
	if cp -r "$PROJECT_DIR/images"/* /etc/nodogsplash/htdocs/images/ 2>/dev/null; then
		print_success "Deployed: images directory"
	else
		print_warning "Failed to deploy images directory (may not exist)"
	fi
fi

# Strictly require splash.html to exist after deployment
if [ ! -f /etc/nodogsplash/htdocs/splash.html ] || [ ! -s /etc/nodogsplash/htdocs/splash.html ]; then
	print_error "splash.html is missing or empty after deployment. Aborting."
	print_info "Deployment backup available at: $BACKUP_DIR"
	exit 1
fi

print_success "All critical files deployed successfully"

# Step 12: Inject configuration into files
print_header "Step 12: Injecting Configuration"

print_info "Replacing configuration placeholders in files..."

# Use perl for safe variable substitution (avoids sed escaping issues)
for file in /etc/nodogsplash/htdocs/*.html /etc/nodogsplash/htdocs/*.js /etc/nodogsplash/htdocs/*.css; do
	if [ -f "$file" ]; then
		filename=$(basename "$file")

		# Create a backup before modification
		cp "$file" "${file}.tmp"

		# Use perl for safe substitution if available
		if command -v perl >/dev/null 2>&1; then
			perl -pi -e "s/ROUTER_ID_PLACEHOLDER/$ROUTER_ID/g" "$file" 2>/dev/null || true
			perl -pi -e "s/CONTRACT_ID_PLACEHOLDER/$CONTRACT_ID/g" "$file" 2>/dev/null || true
			perl -pi -e "s/MAIN_SERVER_PLACEHOLDER/$MAIN_SERVER/g" "$file" 2>/dev/null || true
			perl -pi -e "s/WIFI_SSID_PLACEHOLDER/$WIFI_SSID/g" "$file" 2>/dev/null || true
		else
			# Fallback to sed with | delimiter for URLs
			sed -i "s/ROUTER_ID_PLACEHOLDER/$ROUTER_ID/g" "$file" 2>/dev/null || true
			sed -i "s/CONTRACT_ID_PLACEHOLDER/$CONTRACT_ID/g" "$file" 2>/dev/null || true
			sed -i "s|MAIN_SERVER_PLACEHOLDER|$MAIN_SERVER|g" "$file" 2>/dev/null || true
			sed -i "s/WIFI_SSID_PLACEHOLDER/$WIFI_SSID/g" "$file" 2>/dev/null || true
		fi

		# Verify file is still valid after replacement
		if [ ! -s "$file" ]; then
			print_error "File became empty after replacement: $filename - restoring backup"
			mv "${file}.tmp" "$file"
		else
			print_success "Updated: $filename"
			rm -f "${file}.tmp"
		fi
	fi
done

# Final verification of critical files
if [ ! -f /etc/nodogsplash/htdocs/splash.html ] || [ ! -s /etc/nodogsplash/htdocs/splash.html ]; then
	print_error "splash.html is missing or empty after configuration injection"
	exit 1
fi

print_success "Configuration injected successfully"
print_success "All deployed files have correct permissions"

# Step 12.2: Fetch and cache network info for captive portal (recommended)
print_header "Step 12.4: Caching Network Info (Recommended)"

echo "The splash page loads network details from a local file: /network-info.json"
echo "Blocked clients cannot reach the internet, so the router should fetch and cache it."
echo ""
echo -n "Fetch & cache network info now (and keep it refreshed)? (y/n) [y]: "
read -r cache_confirm
cache_confirm=${cache_confirm:-y}

if [ "$cache_confirm" = "y" ] || [ "$cache_confirm" = "Y" ]; then
	NETWORK_INFO_URL="${MAIN_SERVER}/api/v1/portal/network/${CONTRACT_ID}"
	NETWORK_INFO_TMP="/tmp/network-info.json"
	NETWORK_INFO_DEST="/etc/nodogsplash/htdocs/network-info.json"

	print_info "Fetching network info from: $NETWORK_INFO_URL"

	# Fetch into temp file first
	if $DOWNLOAD_CMD "$NETWORK_INFO_TMP" "$NETWORK_INFO_URL" >/dev/null 2>&1; then
		# Enhanced validation: file exists, non-empty, and looks like valid JSON with success field
		if [ -s "$NETWORK_INFO_TMP" ]; then
			# Check for various JSON success patterns (more flexible)
			if grep -qE '"success"[[:space:]]*:[[:space:]]*(true|"true")' "$NETWORK_INFO_TMP" 2>/dev/null; then
				cp "$NETWORK_INFO_TMP" "$NETWORK_INFO_DEST"
				chmod 644 "$NETWORK_INFO_DEST"
				print_success "Cached network info to: $NETWORK_INFO_DEST"
			elif grep -q '"success":true' "$NETWORK_INFO_TMP" 2>/dev/null; then
				cp "$NETWORK_INFO_TMP" "$NETWORK_INFO_DEST"
				chmod 644 "$NETWORK_INFO_DEST"
				print_success "Cached network info to: $NETWORK_INFO_DEST"
			else
				print_warning "Network info response doesn't look valid; skipping cache write"
				print_info "Response preview: $(head -c 200 "$NETWORK_INFO_TMP" 2>/dev/null)"
			fi
		else
			print_warning "Network info fetch returned empty response"
		fi
		rm -f "$NETWORK_INFO_TMP"
	else
		print_warning "Failed to fetch network info (continuing without it)"
		print_info "URL: $NETWORK_INFO_URL"
	fi

	# Create updater script for periodic refresh
	print_info "Creating network info refresh script..."
	cat >/etc/zaanet/update-network-info.sh <<'EOF'
#!/bin/sh
set -e

# Load router config
if [ -f /etc/zaanet/config ]; then
  . /etc/zaanet/config
else
  exit 0
fi

NETWORK_INFO_URL="${MAIN_SERVER}/api/v1/portal/network/${CONTRACT_ID}"
TMP_FILE="/tmp/network-info.json"
DEST_FILE="/etc/nodogsplash/htdocs/network-info.json"

# Determine download command
if command -v wget >/dev/null 2>&1; then
  wget -q -O "$TMP_FILE" "$NETWORK_INFO_URL" >/dev/null 2>&1 || exit 0
elif command -v curl >/dev/null 2>&1; then
  curl -s -L -o "$TMP_FILE" "$NETWORK_INFO_URL" >/dev/null 2>&1 || exit 0
else
  exit 0
fi

# Only overwrite if response looks valid (flexible JSON check)
if [ -s "$TMP_FILE" ]; then
  if grep -qE '"success"[[:space:]]*:[[:space:]]*(true|"true")' "$TMP_FILE" 2>/dev/null; then
    cp "$TMP_FILE" "$DEST_FILE"
    chmod 644 "$DEST_FILE"
  elif grep -q '"success":true' "$TMP_FILE" 2>/dev/null; then
    cp "$TMP_FILE" "$DEST_FILE"
    chmod 644 "$DEST_FILE"
  fi
fi

# Cleanup
rm -f "$TMP_FILE"
EOF

	chmod 755 /etc/zaanet/update-network-info.sh
	print_success "Created: /etc/zaanet/update-network-info.sh"

	# Install cron job (every 30 minutes) - with deduplication
	print_info "Installing cron job (every 30 minutes)..."
	mkdir -p /etc/crontabs
	touch /etc/crontabs/root

	# Remove any previous entry for this script, then append (atomic update)
	CRON_ENTRY="*/30 * * * * /etc/zaanet/update-network-info.sh >/dev/null 2>&1"
	grep -v "/etc/zaanet/update-network-info.sh" /etc/crontabs/root >/tmp/root.cron.tmp 2>/dev/null || true
	echo "$CRON_ENTRY" >>/tmp/root.cron.tmp
	mv /tmp/root.cron.tmp /etc/crontabs/root
	chmod 600 /etc/crontabs/root

	# Ensure cron is enabled and running (OpenWrt)
	/etc/init.d/cron enable >/dev/null 2>&1 || true
	/etc/init.d/cron restart >/dev/null 2>&1 || true
	print_success "Cron refresh enabled"
else
	print_warning "Skipped network info caching"
	print_info "The splash page will hide network details if /network-info.json is missing."
fi

# Step 12.5: Setup Metrics Collection (Traffic Stats from NoDogSplash)
print_header "Step 12.5: Configuring Metrics Collection"

echo "ZaaNet can collect real-time traffic stats (data usage) from connected users."
echo "This data is used for:"
echo "  - Session page analytics (download/upload stats)"
echo "  - Admin dashboard metrics"
echo "  - Usage-based billing (if enabled)"
echo ""
echo -n "Enable metrics collection? (y/n) [y]: "
read -r metrics_confirm
metrics_confirm=${metrics_confirm:-y}

if [ "$metrics_confirm" = "y" ] || [ "$metrics_confirm" = "Y" ]; then
	print_info "Deploying metrics collection script..."

	# Copy the pre-built metrics script
	if [ -f "$PROJECT_DIR/collect-metrics.sh" ]; then
		if cp "$PROJECT_DIR/collect-metrics.sh" /etc/zaanet/collect-metrics.sh; then
			chmod 755 /etc/zaanet/collect-metrics.sh
			print_success "Deployed: /etc/zaanet/collect-metrics.sh"

			# Install cron job (every 1 minute) - with deduplication
			print_info "Installing metrics collection cron job (every 60 seconds)..."
			mkdir -p /etc/crontabs
			touch /etc/crontabs/root

			# Remove any previous entry for this script, then append (atomic update)
			CRON_ENTRY="* * * * * /etc/zaanet/collect-metrics.sh >/dev/null 2>&1"
			grep -v "/etc/zaanet/collect-metrics.sh" /etc/crontabs/root >/tmp/root.cron.tmp 2>/dev/null || true
			echo "$CRON_ENTRY" >>/tmp/root.cron.tmp
			mv /tmp/root.cron.tmp /etc/crontabs/root
			chmod 600 /etc/crontabs/root

			# Ensure cron is enabled and running
			/etc/init.d/cron enable >/dev/null 2>&1 || true
			/etc/init.d/cron restart >/dev/null 2>&1 || true
			print_success "Metrics collection enabled (runs every 60 seconds)"
			print_info "Script: /etc/zaanet/collect-metrics.sh"
		else
			print_warning "Failed to copy collect-metrics.sh"
			metrics_confirm="n"
		fi
	else
		print_warning "collect-metrics.sh not found in project files, skipping metrics deployment"
		metrics_confirm="n"
	fi
else
	print_warning "Skipped metrics collection"
	print_info "Session analytics will not show real-time data usage"
fi

# Step 13: Configure nodogsplash
print_header "Step 13: Configuring Nodogsplash"

print_warning "IMPORTANT: Ensure you are connected via SSH (not WiFi) before continuing"
print_info "WiFi connectivity may be temporarily interrupted during configuration"
echo ""
read -rp "Press Enter to continue (or Ctrl+C to cancel if not ready)..."

# Hard reset Nodogsplash config for v5/v6 compatibility
print_info "Resetting Nodogsplash config to default (removes legacy/invalid options)..."
/etc/init.d/nodogsplash stop >/dev/null 2>&1 || true

if [ -f /etc/config/nodogsplash ]; then
	NODOGSPLASH_BACKUP="/etc/config/nodogsplash.backup.$(date +%Y%m%d-%H%M%S)"
	cp /etc/config/nodogsplash "$NODOGSPLASH_BACKUP"
	print_info "Backed up nodogsplash configuration to: $NODOGSPLASH_BACKUP"
	rm -f /etc/config/nodogsplash
fi

if opkg update >/dev/null 2>&1 && opkg install --force-reinstall nodogsplash >/dev/null 2>&1; then
	print_success "Nodogsplash config reset and package reinstalled"
else
	print_warning "Failed to reinstall nodogsplash, but continuing with existing installation"
fi

print_info "Setting nodogsplash parameters..."

# Always remove legacy/invalid options before setting new ones
uci -q delete nodogsplash.@nodogsplash[0].checkinterval 2>/dev/null || true

# Set basic parameters (continue on error for individual settings)
uci set nodogsplash.@nodogsplash[0].enabled='1' 2>/dev/null || print_warning "Failed to set enabled parameter"
uci set nodogsplash.@nodogsplash[0].gatewayname='ZaaNet WiFi Hotspot' 2>/dev/null || print_warning "Failed to set gatewayname"
uci set nodogsplash.@nodogsplash[0].gatewayinterface='br-lan' 2>/dev/null || print_warning "Failed to set gatewayinterface"
uci set nodogsplash.@nodogsplash[0].preauthidletimeout='10' 2>/dev/null || print_warning "Failed to set preauthidletimeout"
uci set nodogsplash.@nodogsplash[0].authidletimeout='60' 2>/dev/null || print_warning "Failed to set authidletimeout"
uci set nodogsplash.@nodogsplash[0].sessiontimeout='1440' 2>/dev/null || print_warning "Failed to set sessiontimeout"

# Portal server configuration (CRITICAL for splash page display)
uci set nodogsplash.@nodogsplash[0].gatewayport='2050' 2>/dev/null || print_warning "Failed to set gatewayport"
uci set nodogsplash.@nodogsplash[0].docroot='/etc/nodogsplash/htdocs' 2>/dev/null || print_warning "Failed to set docroot"
uci set nodogsplash.@nodogsplash[0].splashpage='splash.html' 2>/dev/null || print_warning "Failed to set splashpage"
uci set nodogsplash.@nodogsplash[0].loglevel='info' 2>/dev/null || print_warning "Failed to set loglevel"

# Clear existing firewall rules
uci -q delete nodogsplash.@nodogsplash[0].preauthenticated_users 2>/dev/null || true
uci -q delete nodogsplash.@nodogsplash[0].users_to_router 2>/dev/null || true
uci -q delete nodogsplash.@nodogsplash[0].trustedmaclist 2>/dev/null || true

print_success "Basic parameters set"

# Step 13.6: Admin Device Whitelisting
print_header "Step 13.6: Whitelisting Admin Device"

# Add admin device to trusted MAC list FIRST (before firewall rules)
# This ensures admin device has access even if nodogsplash restarts
if [ -n "$ADMIN_MAC" ]; then
	print_info "Adding admin device to trusted list (CRITICAL for maintaining access)..."
	if uci add_list nodogsplash.@nodogsplash[0].trustedmaclist="$ADMIN_MAC" 2>/dev/null; then
		print_success "Admin device whitelisted: $ADMIN_MAC"
		print_info "This device will bypass captive portal"
	else
		print_warning "Failed to whitelist admin device (you may need to add manually later)"
	fi
else
	print_warning "No admin device MAC provided - you may lose WiFi access temporarily"
	print_info "You can add your MAC later: uci add_list nodogsplash.@nodogsplash[0].trustedmaclist='YOUR_MAC'"
fi

# Step 13.7: Configure Firewall Rules
print_header "Step 13.7: Configuring Firewall Rules"

# Add firewall rules for pre-authenticated users (before login)
print_info "Configuring pre-authentication firewall rules..."

# Use more lenient error handling - warn but continue
uci add_list nodogsplash.@nodogsplash[0].preauthenticated_users='allow tcp port 53' 2>/dev/null || print_warning "Failed to add pre-auth rule: tcp 53"
uci add_list nodogsplash.@nodogsplash[0].preauthenticated_users='allow udp port 53' 2>/dev/null || print_warning "Failed to add pre-auth rule: udp 53"
uci add_list nodogsplash.@nodogsplash[0].preauthenticated_users='allow udp port 67' 2>/dev/null || print_warning "Failed to add pre-auth rule: udp 67"
uci add_list nodogsplash.@nodogsplash[0].preauthenticated_users='allow udp port 68' 2>/dev/null || print_warning "Failed to add pre-auth rule: udp 68"
print_success "Pre-auth rules configured"

# Add rules to allow access to router admin panel and services
print_info "Configuring router access rules..."
uci add_list nodogsplash.@nodogsplash[0].users_to_router='allow tcp port 22' 2>/dev/null || print_warning "Failed to add router rule: tcp 22"
uci add_list nodogsplash.@nodogsplash[0].users_to_router='allow tcp port 80' 2>/dev/null || print_warning "Failed to add router rule: tcp 80"
uci add_list nodogsplash.@nodogsplash[0].users_to_router='allow tcp port 443' 2>/dev/null || print_warning "Failed to add router rule: tcp 443"
uci add_list nodogsplash.@nodogsplash[0].users_to_router='allow tcp port 53' 2>/dev/null || print_warning "Failed to add router rule: tcp 53"
uci add_list nodogsplash.@nodogsplash[0].users_to_router='allow udp port 53' 2>/dev/null || print_warning "Failed to add router rule: udp 53"
uci add_list nodogsplash.@nodogsplash[0].users_to_router='allow udp port 67' 2>/dev/null || print_warning "Failed to add router rule: udp 67"
print_success "Router access rules configured"

# Allow ZaaNet API during captive phase (CRITICAL)
# Step 13.75: Resolve ZaaNet API domain and update Nodogsplash
print_header "Step 13.75: Resolving ZaaNet API domain for Nodogsplash"

# Resolve api.zaanet.xyz to IP
API_DOMAIN="api.zaanet.xyz"
API_IP=$(nslookup "$API_DOMAIN" 2>/dev/null | awk '/^Address: / { print $2 }' | head -n1)

if [ -z "$API_IP" ]; then
	print_warning "Failed to resolve $API_DOMAIN, skipping preauth IP update"
else
	print_info "Resolved $API_DOMAIN to IP: $API_IP"

	# Remove previous entry if exists
	uci -q delete_list nodogsplash.@nodogsplash[0].preauthenticated_users="allow tcp port 443 to $API_IP"

	# Add preauth rules with resolved IP
	uci add_list nodogsplash.@nodogsplash[0].preauthenticated_users="allow tcp port 443 to $API_IP"
	print_success "Updated Nodogsplash pre-auth rule for ZaaNet API"

fi

# Step 13.8: Commit Nodogsplash Configuration
print_header "Step 13.8: Committing Nodogsplash Configuration"

# Commit changes
print_info "Committing configuration..."
if uci commit nodogsplash; then
	print_success "Nodogsplash configured successfully"
	print_success "Router admin panel will be accessible at: http://192.168.8.1"
	if [ -n "$ADMIN_MAC" ]; then
		print_success "Admin device ($ADMIN_MAC) has full access"
	fi
else
	print_error "Failed to commit nodogsplash configuration"
	if [ -f "$NODOGSPLASH_BACKUP" ]; then
		print_info "Attempting to restore backup..."
		cp "$NODOGSPLASH_BACKUP" /etc/config/nodogsplash
		print_warning "Configuration restored from backup: $NODOGSPLASH_BACKUP"
	fi
	print_warning "You may need to configure nodogsplash manually"
fi

# Step 14: Configure WiFi
print_header "Step 14: Configuring WiFi Network"

print_warning "⚠️  WARNING: WiFi will be temporarily disconnected during reload!"
print_warning "⚠️  Make sure you are connected via SSH (Ethernet/USB) before continuing!"
print_info "This will configure an open WiFi network (no password)"
print_info "The captive portal will handle authentication"
echo "" # Extra validation: test if portal responds

sleep 2
if command -v curl >/dev/null 2>&1; then
	if curl -s http://127.0.0.1:2050/splash.html | grep -q "ZaaNet\|splash" 2>/dev/null; then
		print_success "Splash page is being served correctly"
	else
		print_warning "Splash page may not be serving (test failed)"
	fi
elif command -v wget >/dev/null 2>&1; then
	if wget -q -O - http://127.0.0.1:2050/splash.html | grep -q "ZaaNet\|splash" 2>/dev/null; then
		print_success "Splash page is being served correctly"
	else
		print_warning "Splash page may not be serving (test failed)"
	fi
fi

echo -n "Continue with WiFi configuration? (y/n): "
read -r confirm

if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
	# Backup wireless config
	if [ -f /etc/config/wireless ]; then
		WIRELESS_BACKUP="/etc/config/wireless.backup.$(date +%Y%m%d-%H%M%S)"
		cp /etc/config/wireless "$WIRELESS_BACKUP"
		print_info "Backed up wireless configuration to: $WIRELESS_BACKUP"
	fi

	# Configure 2.4GHz WiFi
	uci set wireless.@wifi-iface[0].encryption='none' 2>/dev/null || print_warning "Failed to set encryption"
	uci set wireless.@wifi-iface[0].ssid="$WIFI_SSID" 2>/dev/null || print_warning "Failed to set SSID"
	uci set wireless.@wifi-iface[0].disabled='0' 2>/dev/null || print_warning "Failed to enable WiFi"
	uci -q delete wireless.@wifi-iface[0].key 2>/dev/null || true

	# Try to configure 5GHz if available
	uci set wireless.@wifi-iface[1].encryption='none' 2>/dev/null || true
	uci set wireless.@wifi-iface[1].ssid="${WIFI_SSID}-5G" 2>/dev/null || true
	uci set wireless.@wifi-iface[1].disabled='0' 2>/dev/null || true
	uci -q delete wireless.@wifi-iface[1].key 2>/dev/null || true

	# Commit wireless configuration
	if uci commit wireless; then
		print_success "WiFi configuration committed"
	else
		print_error "Failed to commit WiFi configuration"
		print_warning "Continuing anyway - you may need to configure WiFi manually"
	fi

	print_warning "Reloading WiFi - all WiFi connections will drop temporarily!"
	print_info "This may take 15-20 seconds..."
	echo ""

	# Reload WiFi with better timeout handling
	print_info "Reloading WiFi (this may take 15-20 seconds)..."

	# Run wifi reload in background with timeout
	(wifi reload >/dev/null 2>&1) &
	WIFI_PID=$!

	# Wait up to 30 seconds for completion
	WAIT_COUNT=0
	while [ $WAIT_COUNT -lt 30 ]; do
		if ! kill -0 $WIFI_PID 2>/dev/null; then
			# Process finished
			wait $WIFI_PID 2>/dev/null
			WIFI_RESULT=$?
			if [ $WIFI_RESULT -eq 0 ]; then
				print_success "WiFi reloaded successfully"
			else
				print_warning "WiFi reload finished with warnings (code: $WIFI_RESULT)"
			fi
			break
		fi
		sleep 1
		WAIT_COUNT=$((WAIT_COUNT + 1))

		# Show progress every 5 seconds
		if [ $((WAIT_COUNT % 5)) -eq 0 ]; then
			print_info "Still waiting... ($WAIT_COUNT seconds elapsed)"
		fi
	done

	# If still running after timeout, kill it
	if kill -0 $WIFI_PID 2>/dev/null; then
		print_warning "WiFi reload timed out after 30 seconds"
		kill -9 $WIFI_PID 2>/dev/null || true
		wait $WIFI_PID 2>/dev/null || true
		print_info "WiFi configuration saved but may require manual reload: wifi reload"
	fi

	# Wait a bit for WiFi to stabilize
	sleep 3

	print_success "WiFi configuration complete"
	print_info "New SSID: $WIFI_SSID (open network)"
	print_info "If WiFi didn't reload automatically, run: wifi reload"
else
	print_warning "Skipped WiFi configuration"
	print_info "You must manually configure an open WiFi network later"
fi

# Step 15: Enable and start services
print_header "Step 15: Starting Services"

# Enable nodogsplash on boot
if /etc/init.d/nodogsplash enable >/dev/null 2>&1; then
	print_success "Nodogsplash enabled on boot"
else
	print_warning "Failed to enable nodogsplash on boot (may already be enabled)"
fi

# Restart nodogsplash
print_info "Starting nodogsplash..."
if [ -n "$ADMIN_MAC" ]; then
	print_info "Admin device whitelisted - you should maintain access"
fi

if /etc/init.d/nodogsplash restart >/dev/null 2>&1; then
	sleep 5

	# Check status
	if /etc/init.d/nodogsplash status 2>/dev/null | grep -q "running"; then
		print_success "Nodogsplash is running"
		if [ -n "$ADMIN_MAC" ]; then
			print_success "Admin device ($ADMIN_MAC) should have full access"
		fi
	else
		print_warning "Nodogsplash may not be running correctly"
		print_info "Check logs: logread | grep nodogsplash"
	fi
else
	print_error "Failed to start nodogsplash"
	print_info "Check logs: logread | grep nodogsplash"
	print_warning "You may need to manually restart: /etc/init.d/nodogsplash restart"
fi

# Step 16: Verify installation
print_header "Step 16: Verifying Installation"

# Check nodogsplash listening
if netstat -tuln 2>/dev/null | grep -q ":2050" || ss -tuln 2>/dev/null | grep -q ":2050"; then
	print_success "Nodogsplash listening on port 2050"
else
	print_warning "Nodogsplash may not be listening on port 2050"
	print_info "Check status: /etc/init.d/nodogsplash status"
fi

# Verify deployed files
VERIFY_FILES="splash.html config.js script.js"
ALL_FILES_OK=true
for file in $VERIFY_FILES; do
	if [ -f "/etc/nodogsplash/htdocs/$file" ] && [ -s "/etc/nodogsplash/htdocs/$file" ]; then
		print_success "$file deployed and valid"
	else
		print_warning "$file not found or empty"
		ALL_FILES_OK=false
	fi
done

# Check configuration file
if [ -f /etc/zaanet/config ] && [ -s /etc/zaanet/config ]; then
	print_success "Configuration file exists and is valid"
else
	print_error "Configuration file missing or empty"
	ALL_FILES_OK=false
fi

if [ "$ALL_FILES_OK" = true ]; then
	print_success "All critical files verified successfully"
else
	print_warning "Some files may be missing - installation may be incomplete"
fi

# Step 17: Create installation log
cat >/etc/zaanet/installation.log <<EOF
ZaaNet Installation Log
=======================

Installation Date: $(date)
Script Version: 1.4.1 (GitHub Download - Fixed)

GitHub Repository:
------------------
Repository: $GITHUB_REPO
Branch: $GITHUB_BRANCH
Base URL: $GITHUB_RAW_BASE

Configuration:
--------------
Router ID: $ROUTER_ID
Contract ID: $CONTRACT_ID
Main Server: $MAIN_SERVER
WiFi SSID: $WIFI_SSID
Admin MAC: ${ADMIN_MAC:-Not configured}

System Information:
-------------------
OpenWrt Version: $(cat /etc/openwrt_release 2>/dev/null | grep DISTRIB_DESCRIPTION | cut -d"'" -f2 || echo "Unknown")
Nodogsplash Version: $(opkg list-installed 2>/dev/null | grep nodogsplash | awk '{print $3}' || echo "Unknown")
Available Space: ${AVAILABLE_MB}MB

Deployed Files:
---------------
$(find /etc/nodogsplash/htdocs/ -maxdepth 1 -type f \( -name '*.html' -o -name '*.js' -o -name '*.css' \) -exec ls -lh {} \; 2>/dev/null | awk '{print $9, $5}' || echo "No files found")

Backup Locations:
-----------------
Nodogsplash Config: ${NODOGSPLASH_BACKUP:-None}
Wireless Config: ${WIRELESS_BACKUP:-None}
Htdocs Directory: ${BACKUP_DIR:-None}

Status:
-------
Installation completed.
Nodogsplash service: $(if /etc/init.d/nodogsplash status 2>/dev/null | grep -q "running"; then echo "running"; else echo "stopped or error"; fi)

Notes:
------
- All backups are timestamped and preserved
- Check logs with: logread | grep nodogsplash
- View this log: cat /etc/zaanet/installation.log
EOF

chmod 644 /etc/zaanet/installation.log
print_success "Installation log saved: /etc/zaanet/installation.log"

# Final success message
print_header "Installation Complete!"

echo ""
echo "==========================================="
echo "   ZaaNet Successfully Installed!"
echo "==========================================="
echo ""
echo "ROUTER INFORMATION:"
echo "-------------------"
echo "Router ID:   $ROUTER_ID"
echo "WiFi SSID:   $WIFI_SSID (2.4GHz)"
echo "WiFi SSID:   ${WIFI_SSID}-5G (5GHz)"
echo "Gateway:     ZaaNet WiFi Hotspot"
if [ -n "$ADMIN_MAC" ]; then
	echo "Admin MAC:   $ADMIN_MAC (whitelisted)"
fi
echo ""
echo "CONFIGURATION:"
echo "--------------"
echo "Contract ID: $CONTRACT_ID"
echo "Main Server: $MAIN_SERVER"
echo "Config File: /etc/zaanet/config"
echo "Install Log: /etc/zaanet/installation.log"
echo ""
echo "DEPLOYED FILES:"
echo "---------------"
find /etc/nodogsplash/htdocs/ -maxdepth 1 -type f \( -name '*.html' -o -name '*.js' \) -print0 2>/dev/null | xargs -0 basename -a 2>/dev/null | sed 's/^/  /' || echo "  Error listing files"
echo ""
echo "BACKUP LOCATIONS:"
echo "-----------------"
if [ -n "$NODOGSPLASH_BACKUP" ]; then
	echo "Nodogsplash: $NODOGSPLASH_BACKUP"
fi
if [ -n "$WIRELESS_BACKUP" ]; then
	echo "Wireless:    $WIRELESS_BACKUP"
fi
if [ -n "$BACKUP_DIR" ]; then
	echo "Htdocs:      $BACKUP_DIR"
fi
echo ""
echo "TESTING THE CAPTIVE PORTAL:"
echo "---------------------------"
echo "1. Connect a device to the WiFi network: $WIFI_SSID"
echo "2. Open a web browser"
echo "3. Try to visit any website"
echo "4. You should see the ZaaNet splash page"
echo "5. Enter a voucher code to authenticate"
echo ""
echo "NEXT STEPS:"
echo "-----------"
echo "1. Register this router on the ZaaNet platform:"
echo "   Router ID: $ROUTER_ID"
echo "   Contract ID: $CONTRACT_ID"
echo ""
echo "2. Generate test vouchers on the platform"
echo ""
echo "3. Monitor the router status:"
echo "   - View logs: logread | grep nodogsplash"
echo "   - Check status: /etc/init.d/nodogsplash status"
echo "   - View clients: ndsctl clients"
echo "   - View installation log: cat /etc/zaanet/installation.log"
echo ""
echo "TROUBLESHOOTING:"
echo "----------------"
echo "If captive portal doesn't appear:"
echo "  1. Check service: /etc/init.d/nodogsplash status"
echo "  2. Restart service: /etc/init.d/nodogsplash restart"
echo "  3. Check logs: logread | grep nodogsplash"
echo "  4. Verify files exist: ls -la /etc/nodogsplash/htdocs/"
echo ""
echo "To restore from backup (if needed):"
if [ -n "$NODOGSPLASH_BACKUP" ]; then
	echo "  cp \"$NODOGSPLASH_BACKUP\" /etc/config/nodogsplash"
fi
if [ -n "$WIRELESS_BACKUP" ]; then
	echo "  cp \"$WIRELESS_BACKUP\" /etc/config/wireless"
fi
echo ""
echo "SUPPORT:"
echo "--------"
echo "Documentation: https://docs.zaanet.xyz"
echo ""
echo "Thank you for using ZaaNet!"
echo ""
