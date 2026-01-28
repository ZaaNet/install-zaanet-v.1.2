#!/bin/bash
set -eu  # Exit on any error and treat unset variables as errors
# ZaaNet Router Installation Script
# Version: 1.4 - GitHub Download
# Platform: GL.iNet GL-XE300 with OpenWrt 22.03.4

set -e  # Exit on any error

# Configuration
GITHUB_REPO="ZaaNet/public-splash"  # Public splash page repository
GITHUB_BRANCH="main"
GITHUB_RAW_BASE="https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}"
TMP_DIR="/tmp/zaanet-install"
PROJECT_DIR="$TMP_DIR"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions for colored output
print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
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
print_header "ZaaNet Router Installation Script v1.4"
echo "This script will:"
echo "  1. Download ZaaNet project files from GitHub"
echo "  2. Install and configure nodogsplash"
echo "  3. Set up your router with your credentials"
echo ""
echo "GitHub Repository: $GITHUB_REPO"
echo "Branch: $GITHUB_BRANCH"
echo ""
read -p "Press Enter to continue or Ctrl+C to cancel..."

# Step 1: Verify internet connection
print_header "Step 1: Verifying Internet Connection"

if ping -c 1 -W 2 8.8.8.8 > /dev/null 2>&1; then
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
if command -v wget > /dev/null 2>&1; then
    DOWNLOAD_CMD="wget -O"
    print_success "wget found"
elif command -v curl > /dev/null 2>&1; then
    DOWNLOAD_CMD="curl -L -o"
    print_success "curl found"
else
    print_error "Neither wget nor curl found"
    print_info "Installing wget..."
    opkg update > /dev/null 2>&1
    opkg install wget > /dev/null 2>&1
    DOWNLOAD_CMD="wget -O"
    print_success "wget installed"
fi

# Note: tar is not required for direct file downloads

# Step 3: Download project files from GitHub
print_header "Step 3: Downloading Project Files"

# Create temporary directory
mkdir -p "$PROJECT_DIR"
print_success "Created temporary directory"

# List of files to download from the repository (space-separated, POSIX-compatible)
FILES_TO_DOWNLOAD="splash.html session.html config.js script.js session.js styles.css"

print_info "Downloading files from GitHub..."
print_info "Repository: $GITHUB_REPO"
print_info "Branch: $GITHUB_BRANCH"
echo ""

# Download each file
FAILED_FILES=""

for file in $FILES_TO_DOWNLOAD; do
    FILE_URL="${GITHUB_RAW_BASE}/${file}"
    FILE_PATH="${PROJECT_DIR}/${file}"

    print_info "Downloading: $file"

    if $DOWNLOAD_CMD "$FILE_PATH" "$FILE_URL" > /dev/null 2>&1; then
        # Verify file was downloaded and is not empty
        if [ -f "$FILE_PATH" ] && [ -s "$FILE_PATH" ]; then
            print_success "Downloaded: $file"
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
ls -lh "$PROJECT_DIR" | grep -E '\.(html|js|css)$' | awk '{print "  " $9 " (" $5 ")"}'

# Step 4: Update package lists
print_header "Step 4: Updating Package Lists"

print_info "Running: opkg update"
if opkg update > /dev/null 2>&1; then
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

if opkg list-installed | grep -q "^nodogsplash"; then
    print_warning "Nodogsplash already installed"
    NODOGSPLASH_VERSION=$(opkg list-installed | grep nodogsplash | awk '{print $3}')
    print_info "Version: $NODOGSPLASH_VERSION"
else
    print_info "Installing nodogsplash..."
    if opkg install nodogsplash > /dev/null 2>&1; then
        print_success "Nodogsplash installed successfully"
    else
        print_error "Failed to install nodogsplash"
        exit 1
    fi
fi

# Step 7: Generate Router ID
print_header "Step 7: Generating Router Identifier"

ROUTER_ID="ZN-$(cat /sys/class/net/eth0/address | md5sum | cut -c1-8 | tr '[:lower:]' '[:upper:]')"
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
    read CONTRACT_ID
    
    if [ -z "$CONTRACT_ID" ]; then
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
    read -s ZAANET_SECRET
    echo ""
    
    if [ -z "$ZAANET_SECRET" ]; then
        print_error "Secret key cannot be empty"
        continue
    fi
    
    # Get string length (POSIX-compatible)
    SECRET_LEN=$(printf '%s' "$ZAANET_SECRET" | wc -c)
    if [ "$SECRET_LEN" -lt 16 ]; then
        print_warning "Secret key is too short (less than 16 characters)"
        echo -n "Use anyway? (y/n): "
        read confirm
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
read WIFI_SSID
WIFI_SSID=${WIFI_SSID:-ZaaNet}
print_info "Using SSID: $WIFI_SSID"

echo ""

# Confirmation
print_header "Configuration Summary"
echo "Router ID:   $ROUTER_ID"
echo "Contract ID: $CONTRACT_ID"
# Extract first 4 and last 4 characters (POSIX-compatible)
SECRET_PREFIX=$(printf '%.4s' "$ZAANET_SECRET")
SECRET_SUFFIX=$(echo "$ZAANET_SECRET" | sed 's/.*\(.\{4\}\)$/\1/')
echo "Secret Key:  ${SECRET_PREFIX}...${SECRET_SUFFIX}"
echo "Main Server: $MAIN_SERVER"
echo "WiFi SSID:   $WIFI_SSID"
echo ""
echo -n "Is this correct? (y/n): "
read confirm

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

# Get SSH client IP from SSH_CONNECTION environment variable
if [ -n "$SSH_CONNECTION" ]; then
    ADMIN_IP=$(echo $SSH_CONNECTION | awk '{print $1}')
    print_info "Detected SSH connection from: $ADMIN_IP"
    
    # Try multiple methods to get MAC address
    ADMIN_MAC=""
    
    # Method 1: Try ip neigh show (neighbor table)
    ADMIN_MAC=$(ip neigh show | grep "$ADMIN_IP" | grep -v "FAILED" | awk '{print $5}' | head -1)
    
    # Method 2: If not found, try to ping and refresh neighbor table
    if [ -z "$ADMIN_MAC" ] || [ "$ADMIN_MAC" = "00:00:00:00:00:00" ]; then
        print_info "Refreshing neighbor table..."
        ping -c 1 -W 1 "$ADMIN_IP" > /dev/null 2>&1
        sleep 1
        ADMIN_MAC=$(ip neigh show | grep "$ADMIN_IP" | grep -v "FAILED" | awk '{print $5}' | head -1)
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
        # Check if it's a valid MAC format
        if echo "$ADMIN_MAC" | grep -qE '^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$'; then
            # Convert to lowercase for consistency
            ADMIN_MAC=$(echo "$ADMIN_MAC" | tr '[:upper:]' '[:lower:]')
            print_success "Detected device MAC: $ADMIN_MAC"
            echo ""
            echo "Device Information:"
            echo "  IP Address: $ADMIN_IP"
            echo "  MAC Address: $ADMIN_MAC"
            echo ""
            echo -n "Whitelist this device? (y/n): "
            read whitelist_confirm
            
            if [ "$whitelist_confirm" = "y" ] || [ "$whitelist_confirm" = "Y" ]; then
                print_success "Admin device will be whitelisted"
            else
                ADMIN_MAC=""
                print_info "Admin device will NOT be whitelisted"
            fi
        else
            print_warning "Invalid MAC format detected: $ADMIN_MAC"
            ADMIN_MAC=""
        fi
    fi
    
    # If still not found, offer manual entry
    if [ -z "$ADMIN_MAC" ] || [ "$ADMIN_MAC" = "00:00:00:00:00:00" ]; then
        print_warning "Could not detect MAC address automatically"
        echo ""
        echo "Currently connected devices:"
        ip neigh show | grep -v "FAILED" | awk '{print "  IP: " $1 " - MAC: " $5}'
        echo ""
        echo -n "Enter MAC address to whitelist (format: aa:bb:cc:dd:ee:ff) or press Enter to skip: "
        read ADMIN_MAC
        
        # If user entered something, validate it
        if [ -n "$ADMIN_MAC" ]; then
            
            # Convert to lowercase for consistency
            ADMIN_MAC=$(echo "$ADMIN_MAC" | tr '[:upper:]' '[:lower:]')
            
            # Basic MAC validation - accept both uppercase and lowercase
            if echo "$ADMIN_MAC" | grep -qE '^([0-9a-f]{2}:){5}[0-9a-f]{2}$'; then
                print_success "MAC address accepted: $ADMIN_MAC"
            else
                print_warning "Invalid MAC format, skipping whitelisting"
                ADMIN_MAC=""
            fi
        else
            print_info "Skipping admin device whitelisting"
        fi
    fi
else
    print_warning "SSH connection info not available"
    echo ""
    echo "You can whitelist a device by entering its MAC address."
    echo -n "Whitelist a device? (y/n): "
    read whitelist_device
    
    if [ "$whitelist_device" = "y" ] || [ "$whitelist_device" = "Y" ]; then
        # Show connected devices to help user choose
        echo ""
        echo "Currently connected devices:"
        ip neigh show | grep -v "FAILED" | awk '{print "  IP: " $1 " - MAC: " $5}'
        echo ""
        
        echo -n "Enter MAC address to whitelist (format: aa:bb:cc:dd:ee:ff): "
        read ADMIN_MAC
        
        # Convert to lowercase
        ADMIN_MAC=$(echo "$ADMIN_MAC" | tr '[:upper:]' '[:lower:]')
        
        if echo "$ADMIN_MAC" | grep -qE '^([0-9a-f]{2}:){5}[0-9a-f]{2}$'; then
            print_success "MAC address accepted: $ADMIN_MAC"
        else
            print_warning "Invalid MAC format, skipping whitelisting"
            ADMIN_MAC=""
        fi
    fi
fi

echo ""

# Step 9: Create directory structure
print_header "Step 9: Creating Directory Structure"

mkdir -p /etc/zaanet
chmod 755 /etc/zaanet
print_success "Created /etc/zaanet"

mkdir -p /www/cgi-bin
chmod 755 /www/cgi-bin
print_success "Created /www/cgi-bin"

# Step 10: Create configuration file
print_header "Step 10: Creating Configuration File"

cat > /etc/zaanet/config << EOF
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
# Clear htdocs before deploying new files (BusyBox compatible)
print_info "Clearing /etc/nodogsplash/htdocs/ before deploying new files..."
find /etc/nodogsplash/htdocs/ -type f ! -name ".gitkeep" -exec rm -f {} +

# Backup existing files
if [ -f /etc/nodogsplash/htdocs/splash.html ]; then
    BACKUP_FILE="/etc/nodogsplash/htdocs/splash.html.backup.$(date +%Y%m%d-%H%M%S)"
    cp /etc/nodogsplash/htdocs/splash.html "$BACKUP_FILE"
    print_info "Backed up existing splash.html to: $BACKUP_FILE"
fi



# Strictly require splash.html to exist before copy
if [ ! -f "$PROJECT_DIR/splash.html" ]; then
    print_error "splash.html is missing in $PROJECT_DIR. Aborting deployment."
    exit 1
fi

# Empty the htdocs directory before deploying new files
print_info "Clearing /etc/nodogsplash/htdocs/ before deploying new files..."
find /etc/nodogsplash/htdocs/ -mindepth 1 -delete
print_success "/etc/nodogsplash/htdocs/ is now empty."

print_info "Copying project files to /etc/nodogsplash/htdocs/..."

# Copy all HTML files
for file in "$PROJECT_DIR"/*.html; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        cp "$file" /etc/nodogsplash/htdocs/
        print_success "Deployed: $filename"
    fi
done

# Copy all JS files
for file in "$PROJECT_DIR"/*.js; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        cp "$file" /etc/nodogsplash/htdocs/
        print_success "Deployed: $filename"
    fi
done

# Copy all CSS files
for file in "$PROJECT_DIR"/*.css; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        cp "$file" /etc/nodogsplash/htdocs/
        print_success "Deployed: $filename"
    fi
done

# Copy assets directory if exists
if [ -d "$PROJECT_DIR/assets" ]; then
    cp -r "$PROJECT_DIR/assets" /etc/nodogsplash/htdocs/
    print_success "Deployed: assets directory"
fi

# Copy images directory if exists
if [ -d "$PROJECT_DIR/images" ]; then
    mkdir -p /etc/nodogsplash/htdocs/images
    cp -r "$PROJECT_DIR/images"/* /etc/nodogsplash/htdocs/images/
    print_success "Deployed: images directory"
fi

# Strictly require splash.html to exist after copy
if [ ! -f /etc/nodogsplash/htdocs/splash.html ]; then
    print_error "splash.html was not copied to /etc/nodogsplash/htdocs/. Aborting."
    exit 1
fi

# Step 12: Inject configuration into files
print_header "Step 12: Injecting Configuration"

print_info "Replacing configuration placeholders in files..."

# Replace in all deployed files
for file in /etc/nodogsplash/htdocs/*.html /etc/nodogsplash/htdocs/*.js /etc/nodogsplash/htdocs/*.css; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        
        # Replace each placeholder (POSIX-compatible, no associative arrays)
        # ROUTER_ID_PLACEHOLDER
        escaped_placeholder=$(echo "ROUTER_ID_PLACEHOLDER" | sed 's/[\/&]/\\&/g')
        escaped_replacement=$(echo "$ROUTER_ID" | sed 's/[\/&]/\\&/g')
        sed -i "s/${escaped_placeholder}/${escaped_replacement}/g" "$file" 2>/dev/null || true
        
        # CONTRACT_ID_PLACEHOLDER
        escaped_placeholder=$(echo "CONTRACT_ID_PLACEHOLDER" | sed 's/[\/&]/\\&/g')
        escaped_replacement=$(echo "$CONTRACT_ID" | sed 's/[\/&]/\\&/g')
        sed -i "s/${escaped_placeholder}/${escaped_replacement}/g" "$file" 2>/dev/null || true
        
        # MAIN_SERVER_PLACEHOLDER
        escaped_placeholder=$(echo "MAIN_SERVER_PLACEHOLDER" | sed 's/[\/&]/\\&/g')
        escaped_replacement=$(echo "$MAIN_SERVER" | sed 's/[\/&]/\\&/g')
        sed -i "s/${escaped_placeholder}/${escaped_replacement}/g" "$file" 2>/dev/null || true
        
        # WIFI_SSID_PLACEHOLDER
        escaped_placeholder=$(echo "WIFI_SSID_PLACEHOLDER" | sed 's/[\/&]/\\&/g')
        escaped_replacement=$(echo "$WIFI_SSID" | sed 's/[\/&]/\\&/g')
        sed -i "s/${escaped_placeholder}/${escaped_replacement}/g" "$file" 2>/dev/null || true
        
        # $routerid (nodogsplash variable)
        escaped_placeholder=$(echo '\$routerid' | sed 's/[\/&]/\\&/g')
        escaped_replacement=$(echo "$ROUTER_ID" | sed 's/[\/&]/\\&/g')
        sed -i "s/${escaped_placeholder}/${escaped_replacement}/g" "$file" 2>/dev/null || true
        
        # https://api.zaanet.xyz (hardcoded URL replacement)
        escaped_placeholder=$(echo "https://api.zaanet.xyz" | sed 's/[\/&]/\\&/g')
        escaped_replacement=$(echo "$MAIN_SERVER" | sed 's/[\/&]/\\&/g')
        sed -i "s/${escaped_placeholder}/${escaped_replacement}/g" "$file" 2>/dev/null || true
        
        print_success "Updated: $filename"
    fi
done

# Verify critical files exist
if [ ! -f /etc/nodogsplash/htdocs/splash.html ]; then
    print_error "splash.html is missing after deployment"
    exit 1
fi

print_success "Configuration injected successfully"

# Step 12.5: Fetch and cache network info for captive portal (recommended)
print_header "Step 12.5: Caching Network Info (Recommended)"

echo "The splash page loads network details from a local file: /network-info.json"
echo "Blocked clients cannot reach the internet, so the router should fetch and cache it."
echo ""
echo -n "Fetch & cache network info now (and keep it refreshed)? (y/n) [y]: "
read cache_confirm
cache_confirm=${cache_confirm:-y}

if [ "$cache_confirm" = "y" ] || [ "$cache_confirm" = "Y" ]; then
    NETWORK_INFO_URL="${MAIN_SERVER}/api/v1/portal/network/${CONTRACT_ID}"
    NETWORK_INFO_TMP="/tmp/network-info.json"
    NETWORK_INFO_DEST="/etc/nodogsplash/htdocs/network-info.json"

    print_info "Fetching network info from: $NETWORK_INFO_URL"

    # Fetch into temp file first
    if $DOWNLOAD_CMD "$NETWORK_INFO_TMP" "$NETWORK_INFO_URL" > /dev/null 2>&1; then
        # Basic validation: file exists, non-empty, and has \"success\":true
        if [ -s "$NETWORK_INFO_TMP" ] && grep -q '"success"[[:space:]]*:[[:space:]]*true' "$NETWORK_INFO_TMP" 2>/dev/null; then
            cp "$NETWORK_INFO_TMP" "$NETWORK_INFO_DEST"
            chmod 644 "$NETWORK_INFO_DEST"
            print_success "Cached network info to: $NETWORK_INFO_DEST"
        else
            print_warning "Network info fetch did not look valid; skipping cache write"
            print_info "You can retry later with: $NETWORK_INFO_URL"
        fi
    else
        print_warning "Failed to fetch network info (continuing without it)"
        print_info "URL: $NETWORK_INFO_URL"
    fi

    # Create updater script for periodic refresh
    print_info "Creating network info refresh script..."
    cat > /etc/zaanet/update-network-info.sh << 'EOF'
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

if command -v wget >/dev/null 2>&1; then
  wget -O "$TMP_FILE" "$NETWORK_INFO_URL" >/dev/null 2>&1 || exit 0
elif command -v curl >/dev/null 2>&1; then
  curl -L -o "$TMP_FILE" "$NETWORK_INFO_URL" >/dev/null 2>&1 || exit 0
else
  exit 0
fi

# Only overwrite if response looks valid
if [ -s "$TMP_FILE" ] && grep -q '"success"[[:space:]]*:[[:space:]]*true' "$TMP_FILE" 2>/dev/null; then
  cp "$TMP_FILE" "$DEST_FILE"
  chmod 644 "$DEST_FILE"
fi
EOF

    chmod 755 /etc/zaanet/update-network-info.sh
    print_success "Created: /etc/zaanet/update-network-info.sh"

    # Install cron job (every 15 minutes)
    print_info "Installing cron job (every 15 minutes)..."
    mkdir -p /etc/crontabs
    touch /etc/crontabs/root
    # Remove any previous entry for this script, then append
    grep -v "/etc/zaanet/update-network-info.sh" /etc/crontabs/root > /tmp/root.cron 2>/dev/null || true
    echo "*/30 * * * * /etc/zaanet/update-network-info.sh >/dev/null 2>&1" >> /tmp/root.cron
    cp /tmp/root.cron /etc/crontabs/root
    rm -f /tmp/root.cron

    # Ensure cron is enabled and running (OpenWrt)
    /etc/init.d/cron enable > /dev/null 2>&1 || true
    /etc/init.d/cron restart > /dev/null 2>&1 || true
    print_success "Cron refresh enabled"
else
    print_warning "Skipped network info caching"
    print_info "The splash page will hide network details if /network-info.json is missing."
fi

# Step 12.6: Setup Metrics Collection (Traffic Stats from NoDogSplash)
print_header "Step 12.6: Configuring Metrics Collection"

echo "ZaaNet can collect real-time traffic stats (data usage) from connected users."
echo "This data is used for:"
echo "  - Session page analytics (download/upload stats)"
echo "  - Admin dashboard metrics"
echo "  - Usage-based billing (if enabled)"
echo ""
echo -n "Enable metrics collection? (y/n) [y]: "
read metrics_confirm
metrics_confirm=${metrics_confirm:-y}

if [ "$metrics_confirm" = "y" ] || [ "$metrics_confirm" = "Y" ]; then
    print_info "Creating metrics collection script..."
    
    cat > /etc/zaanet/collect-metrics.sh << 'METRICS_EOF'
#!/bin/sh
# ZaaNet Router Metrics Collection Script
set -e

# Load router config
if [ -f /etc/zaanet/config ]; then
  . /etc/zaanet/config
else
  exit 1
fi

LOG_FILE="/tmp/zaanet-metrics.log"
METRICS_ENDPOINT="${MAIN_SERVER}/api/v1/portal/metrics/data-usage"

# Check if NoDogSplash is running
if ! /etc/init.d/nodogsplash status | grep -q "running"; then
  exit 0
fi

# Get authenticated clients only
CLIENT_DATA=$(ndsctl clients 2>/dev/null | awk '
  NR > 1 && NF >= 7 {
    ip = $1
    download = $3
    upload = $4
    state = $7
    
    if (state ~ /authenticated/i && (download > 0 || upload > 0)) {
      total = download + upload
      printf "{\"userIP\":\"%s\",\"sessionId\":null,\"dataUsage\":{\"downloadBytes\":%d,\"uploadBytes\":%d,\"totalBytes\":%d,\"lastUpdated\":\"%s\"}},", ip, download, upload, total, strftime("%Y-%m-%dT%H:%M:%SZ")
    }
  }
' | sed 's/,$//')

if [ -z "$CLIENT_DATA" ]; then
  exit 0
fi

PAYLOAD="{\"sessionUpdates\":[$CLIENT_DATA]}"

# Send to server
if command -v wget >/dev/null 2>&1; then
  wget --timeout=10 --tries=1 -qO- \
    --header="Content-Type: application/json" \
    --header="X-Router-ID: $ROUTER_ID" \
    --header="X-Contract-ID: $CONTRACT_ID" \
    --post-data="$PAYLOAD" \
    "$METRICS_ENDPOINT" >/dev/null 2>&1 || true
elif command -v curl >/dev/null 2>&1; then
  curl -s --max-time 10 \
    -H "Content-Type: application/json" \
    -H "X-Router-ID: $ROUTER_ID" \
    -H "X-Contract-ID: $CONTRACT_ID" \
    -d "$PAYLOAD" \
    "$METRICS_ENDPOINT" >/dev/null 2>&1 || true
fi

exit 0
METRICS_EOF

    chmod 755 /etc/zaanet/collect-metrics.sh
    print_success "Created: /etc/zaanet/collect-metrics.sh"

    # Install cron job (every 1 minute)
    print_info "Installing metrics collection cron job (every 60 seconds)..."
    mkdir -p /etc/crontabs
    touch /etc/crontabs/root
    # Remove any previous entry for this script, then append
    grep -v "/etc/zaanet/collect-metrics.sh" /etc/crontabs/root > /tmp/root.cron 2>/dev/null || true
    echo "* * * * * /etc/zaanet/collect-metrics.sh >/dev/null 2>&1" >> /tmp/root.cron
    cp /tmp/root.cron /etc/crontabs/root
    rm -f /tmp/root.cron

    # Ensure cron is enabled and running
    /etc/init.d/cron enable > /dev/null 2>&1 || true
    /etc/init.d/cron restart > /dev/null 2>&1 || true
    print_success "Metrics collection enabled (runs every 60 seconds)"
    print_info "Logs: /tmp/zaanet-metrics.log"
else
    print_warning "Skipped metrics collection"
    print_info "Session analytics will not show real-time data usage"
fi

# Step 13: Configure nodogsplash
print_header "Step 13: Configuring Nodogsplash"

print_warning "IMPORTANT: Ensure you are connected via SSH (not WiFi) before continuing"
print_info "WiFi connectivity may be temporarily interrupted during configuration"
echo ""
read -p "Press Enter to continue (or Ctrl+C to cancel if not ready)..."

# Hard reset Nodogsplash config for v5/v6 compatibility
print_info "Resetting Nodogsplash config to default (removes legacy/invalid options)..."
/etc/init.d/nodogsplash stop > /dev/null 2>&1 || true
if [ -f /etc/config/nodogsplash ]; then
    cp /etc/config/nodogsplash /etc/config/nodogsplash.backup
    print_info "Backed up nodogsplash configuration"
    rm -f /etc/config/nodogsplash
fi
opkg update > /dev/null 2>&1
opkg install --force-reinstall nodogsplash > /dev/null 2>&1
print_success "Nodogsplash config reset and package reinstalled"

print_info "Setting nodogsplash parameters..."
# Always remove legacy/invalid options before setting new ones
uci -q delete nodogsplash.@nodogsplash[0].checkinterval || true

# Use || true to prevent exit on error for individual commands
uci set nodogsplash.@nodogsplash[0].enabled='1' || true
uci set nodogsplash.@nodogsplash[0].gatewayname='ZaaNet WiFi Hotspot' || true
uci set nodogsplash.@nodogsplash[0].gatewayinterface='br-lan' || true
uci set nodogsplash.@nodogsplash[0].preauthidletimeout='10' || true
uci set nodogsplash.@nodogsplash[0].authidletimeout='60' || true
uci set nodogsplash.@nodogsplash[0].sessiontimeout='1440' || true
# Portal server configuration (CRITICAL for splash page display)
uci set nodogsplash.@nodogsplash[0].gatewayport='2050' || true
uci set nodogsplash.@nodogsplash[0].docroot='/etc/nodogsplash/htdocs' || true
uci set nodogsplash.@nodogsplash[0].splashpage='/etc/nodogsplash/htdocs/splash.html' || true
uci set nodogsplash.@nodogsplash[0].loglevel='info' || true

# Clear existing firewall rules
uci -q delete nodogsplash.@nodogsplash[0].preauthenticated_users || true
uci -q delete nodogsplash.@nodogsplash[0].users_to_router || true
uci -q delete nodogsplash.@nodogsplash[0].trustedmaclist || true

print_success "Basic parameters set"


# Step 13.5: Configure FAS (Forwarding Authentication Service)
print_header "Step 13.5: Configuring FAS (Remote Authentication)"

print_info "Setting up Forwarding Authentication Service (FAS)..."

# (REMOVED) uci set nodogsplash.@nodogsplash[0].fas_enable='1' || true
# Configure remote FAS server
uci set nodogsplash.@nodogsplash[0].fas_remoteip='api.zaanet.xyz' || true
uci set nodogsplash.@nodogsplash[0].fas_port='443' || true
uci set nodogsplash.@nodogsplash[0].fas_path='/api/v1/nds/auth' || true
uci set nodogsplash.@nodogsplash[0].fas_secure='1' || true
print_success "FAS remote server configured: api.zaanet.xyz:443/api/v1/nds/auth"

# Configure FAS parameters (fields to forward to server)
# Clear existing FAS parameters first
uci -q delete nodogsplash.@nodogsplash[0].fas_params || true

# Add required fields that NoDogSplash will forward to the FAS endpoint
uci add_list nodogsplash.@nodogsplash[0].fas_params='voucher' || true
uci add_list nodogsplash.@nodogsplash[0].fas_params='mac' || true
uci add_list nodogsplash.@nodogsplash[0].fas_params='ip' || true
uci add_list nodogsplash.@nodogsplash[0].fas_params='tok' || true
uci add_list nodogsplash.@nodogsplash[0].fas_params='routerId' || true
uci add_list nodogsplash.@nodogsplash[0].fas_params='contractId' || true
print_success "FAS parameters configured (voucher, mac, ip, tok, routerId, contractId)"

# Set router metadata (exposed to FAS server)
uci set nodogsplash.@nodogsplash[0].routerid="$ROUTER_ID" || true
uci set nodogsplash.@nodogsplash[0].contractid="$CONTRACT_ID" || true
print_success "Router metadata set (routerId: $ROUTER_ID, contractId: $CONTRACT_ID)"

print_info "FAS configuration complete - voucher validation will use remote server"

# Step 13.6: Admin Device Whitelisting
print_header "Step 13.6: Whitelisting Admin Device"

# Add admin device to trusted MAC list FIRST (before firewall rules)
# This ensures admin device has access even if nodogsplash restarts
if [ -n "$ADMIN_MAC" ]; then
    print_info "Adding admin device to trusted list (CRITICAL for maintaining access)..."
    uci add_list nodogsplash.@nodogsplash[0].trustedmaclist="$ADMIN_MAC" || true
    print_success "Admin device whitelisted: $ADMIN_MAC"
    print_info "This device will bypass captive portal"
else
    print_warning "No admin device MAC provided - you may lose WiFi access temporarily"
    print_info "You can add your MAC later: uci add_list nodogsplash.@nodogsplash[0].trustedmaclist='YOUR_MAC'"
fi

# Step 13.7: Configure Firewall Rules
print_header "Step 13.7: Configuring Firewall Rules"

# Add firewall rules for pre-authenticated users (before login)
print_info "Configuring pre-authentication firewall rules..."
if ! uci add_list nodogsplash.@nodogsplash[0].preauthenticated_users='allow tcp port 53'; then
    print_error "Failed to add pre-authenticated firewall rule (tcp 53)"; exit 1; fi
if ! uci add_list nodogsplash.@nodogsplash[0].preauthenticated_users='allow udp port 53'; then
    print_error "Failed to add pre-authenticated firewall rule (udp 53)"; exit 1; fi
if ! uci add_list nodogsplash.@nodogsplash[0].preauthenticated_users='allow udp port 67'; then
    print_error "Failed to add pre-authenticated firewall rule (udp 67)"; exit 1; fi
if ! uci add_list nodogsplash.@nodogsplash[0].preauthenticated_users='allow udp port 68'; then
    print_error "Failed to add pre-authenticated firewall rule (udp 68)"; exit 1; fi
print_success "Pre-auth rules configured"

# Add rules to allow access to router admin panel and services
print_info "Configuring router access rules..."
if ! uci add_list nodogsplash.@nodogsplash[0].users_to_router='allow tcp port 22'; then
    print_error "Failed to add router access rule (tcp 22)"; exit 1; fi
if ! uci add_list nodogsplash.@nodogsplash[0].users_to_router='allow tcp port 80'; then
    print_error "Failed to add router access rule (tcp 80)"; exit 1; fi
if ! uci add_list nodogsplash.@nodogsplash[0].users_to_router='allow tcp port 443'; then
    print_error "Failed to add router access rule (tcp 443)"; exit 1; fi
if ! uci add_list nodogsplash.@nodogsplash[0].users_to_router='allow tcp port 53'; then
    print_error "Failed to add router access rule (tcp 53)"; exit 1; fi
if ! uci add_list nodogsplash.@nodogsplash[0].users_to_router='allow udp port 53'; then
    print_error "Failed to add router access rule (udp 53)"; exit 1; fi
if ! uci add_list nodogsplash.@nodogsplash[0].users_to_router='allow udp port 67'; then
    print_error "Failed to add router access rule (udp 67)"; exit 1; fi
print_success "Router access rules configured"

# Step 13.8: Commit Nodogsplash Configuration
print_header "Step 13.8: Committing Nodogsplash Configuration"

# Commit changes
print_info "Committing configuration..."
if uci commit nodogsplash; then
    print_success "Nodogsplash configured successfully (including FAS)"
    print_success "Router admin panel will be accessible at: http://192.168.8.1"
    if [ -n "$ADMIN_MAC" ]; then
        print_success "Admin device ($ADMIN_MAC) has full access"
    fi
else
    print_error "Failed to commit nodogsplash configuration"
    print_info "Attempting to restore backup..."
    if [ -f /etc/config/nodogsplash.backup ]; then
        cp /etc/config/nodogsplash.backup /etc/config/nodogsplash
        print_warning "Configuration restored from backup"
    fi
fi

# Step 14: Configure WiFi
print_header "Step 14: Configuring WiFi Network"

print_warning "⚠️  WARNING: WiFi will be temporarily disconnected during reload!"
print_warning "⚠️  Make sure you are connected via SSH (Ethernet/USB) before continuing!"
print_info "This will configure an open WiFi network (no password)"
print_info "The captive portal will handle authentication"
echo ""
echo -n "Continue with WiFi configuration? (y/n): "
read confirm

if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
    # Backup wireless config
    if [ -f /etc/config/wireless ]; then
        cp /etc/config/wireless /etc/config/wireless.backup
        print_info "Backed up wireless configuration"
    fi
    
    # Configure 2.4GHz WiFi (use || true to prevent exit on error)
    uci set wireless.@wifi-iface[0].encryption='none' || true
    uci set wireless.@wifi-iface[0].ssid="$WIFI_SSID" || true
    uci set wireless.@wifi-iface[0].disabled='0' || true
    uci -q delete wireless.@wifi-iface[0].key || true
    
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
    print_success "WiFi configured"
    
    print_warning "Reloading WiFi - all WiFi connections will drop temporarily!"
    print_info "This may take 10-15 seconds..."
    print_info "If connected via WiFi, you will need to reconnect after this step"
    echo ""
    
    # Reload WiFi - use timeout to prevent hanging
    print_info "Reloading WiFi (this may take 15-20 seconds)..."
    
    # Try to reload WiFi with a timeout
    if command -v timeout > /dev/null 2>&1; then
        # Use timeout if available
        timeout 30 wifi reload || {
            print_warning "WiFi reload timed out, but configuration is saved"
            print_info "WiFi will reload on next reboot or you can manually run: wifi reload"
        }
    else
        # Fallback: run in background with wait limit
        print_info "Running WiFi reload in background..."
        wifi reload &
        WIFI_PID=$!
        
        # Wait up to 25 seconds
        WAIT_COUNT=0
        while [ $WAIT_COUNT -lt 25 ]; do
            if ! kill -0 $WIFI_PID 2>/dev/null; then
                # Process finished
                break
            fi
            sleep 1
            WAIT_COUNT=$((WAIT_COUNT + 1))
        done
        
        # If still running, kill it and continue
        if kill -0 $WIFI_PID 2>/dev/null; then
            print_warning "WiFi reload taking too long, continuing anyway..."
            kill $WIFI_PID 2>/dev/null || true
            wait $WIFI_PID 2>/dev/null || true
        fi
    fi
    
    # Wait a bit for WiFi to stabilize
    sleep 3
    
    print_success "WiFi configuration saved"
    print_info "New SSID: $WIFI_SSID (open network)"
    print_info "If WiFi didn't reload automatically, you can run: wifi reload"
else
    print_warning "Skipped WiFi configuration"
    print_info "You must manually configure an open WiFi network later"
fi

# Step 15: Enable and start services
print_header "Step 15: Starting Services"

# Enable nodogsplash on boot
/etc/init.d/nodogsplash enable > /dev/null 2>&1
print_success "Nodogsplash enabled on boot"

# Restart nodogsplash
print_info "Starting nodogsplash..."
print_info "If admin device was whitelisted, you should maintain access"
/etc/init.d/nodogsplash restart > /dev/null 2>&1
sleep 5

# Check status
if /etc/init.d/nodogsplash status | grep -q "running"; then
    print_success "Nodogsplash is running"
    if [ -n "$ADMIN_MAC" ]; then
        print_success "Admin device ($ADMIN_MAC) should have full access"
    else
        print_warning "No admin device whitelisted - you may need to authenticate"
    fi
else
    print_error "Nodogsplash failed to start"
    print_info "Check logs: logread | grep nodogsplash"
    print_warning "You may need to manually restart: /etc/init.d/nodogsplash restart"
    # Don't exit - allow installation to continue
fi

# Step 16: Verify installation
print_header "Step 16: Verifying Installation"

# Check nodogsplash listening
if netstat -tuln 2>/dev/null | grep -q ":2050"; then
    print_success "Nodogsplash listening on port 2050"
else
    print_warning "Nodogsplash may not be listening on port 2050"
fi

# Verify deployed files
VERIFY_FILES="splash.html config.js script.js"
for file in $VERIFY_FILES; do
    if [ -f "/etc/nodogsplash/htdocs/$file" ]; then
        print_success "$file deployed"
    else
        print_warning "$file not found"
    fi
done

# Check configuration file
if [ -f /etc/zaanet/config ]; then
    print_success "Configuration file exists"
else
    print_error "Configuration file missing"
fi

# Step 17: Create installation log
cat > /etc/zaanet/installation.log << EOF
ZaaNet Installation Log
=======================

Installation Date: $(date)
Script Version: 1.4 (GitHub Download)

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

System Information:
-------------------
OpenWrt Version: $(cat /etc/openwrt_release 2>/dev/null | grep DISTRIB_DESCRIPTION | cut -d"'" -f2 || echo "Unknown")
Nodogsplash Version: $(opkg list-installed 2>/dev/null | grep nodogsplash | awk '{print $3}' || echo "Unknown")
Available Space: ${AVAILABLE_MB}MB

Deployed Files:
---------------
$(ls -lh /etc/nodogsplash/htdocs/ 2>/dev/null | grep -E '\.(html|js|css)$' | awk '{print $9, $5}')

Status:
-------
Installation completed successfully.
Nodogsplash service: running
EOF

print_success "Installation log saved"

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
echo ""
echo "CONFIGURATION:"
echo "--------------"
echo "Contract ID: $CONTRACT_ID"
echo "Main Server: $MAIN_SERVER"
echo "Config File: /etc/zaanet/config"
echo ""
echo "DEPLOYED FILES:"
echo "---------------"
ls /etc/nodogsplash/htdocs/*.html /etc/nodogsplash/htdocs/*.js 2>/dev/null | xargs -n 1 basename | sed 's/^/  /'
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
echo ""
echo "SUPPORT:"
echo "--------"
echo "Documentation: https://docs.zaanet.xyz"
echo "Installation Log: /etc/zaanet/installation.log"
echo ""
echo "Thank you for using ZaaNet!"
echo ""