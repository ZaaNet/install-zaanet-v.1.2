# ZaaNet Router Installation

Quick installation for ZaaNet WiFi hotspot routers.

## Prerequisites

- Internet connection configured on router
- SSH access enabled
- ZaaNet account with credentials

## Installation

### Step 1: Enable SSH on Router

1. Access router web interface: http://192.168.8.1
2. Navigate to: System → Administration → SSH Access
3. Enable SSH and set password

### Step 2: SSH into Router
```bash
ssh root@192.168.8.1
```

Enter your router password.

### Step 3: Run Installation Command
```bash
wget -O /tmp/install.sh https://raw.githubusercontent.com/ZaaNet/install-zaanet-v.1.2/main/install-zaanet.sh && sh /tmp/install.sh
```

### Step 4: Provide Your Credentials

When prompted, enter:
- Your Smart Contract ID (starts with 0x)
- Your ZaaNet Secret Key
- Main Server URL (press Enter for default)
- WiFi SSID (press Enter for default: ZaaNet)

### Step 5: Wait for Completion

Installation takes 2-5 minutes. The script will:
- Download project files from GitHub
- Install firewall
- Configure the captive portal
- Set up WiFi network

### Step 6: Save Your Router ID

The script generates a unique Router ID. **Save this!**

You'll need it to register on the ZaaNet platform.

## Testing

1. Connect to WiFi network (default: "ZaaNet")
2. Open browser → automatic redirect to splash page
3. Enter a test voucher code
4. Get internet access

## Troubleshooting

**Installation fails:**
```bash
# Check internet connection
ping 8.8.8.8

# Try again
sh /tmp/install.sh
```

**Check service status:**
```bash
/etc/init.d/nodogsplash status
```

**View logs:**
```bash
logread | grep nodogsplash
```

## Support

- Documentation: https://docs.zaanet.xyz
- Issues: https://github.com/ZaaNet/install-zaanet-v.1.2/issues

## Files Installed

- Configuration: `/etc/zaanet/config`
- Splash page: `/etc/nodogsplash/htdocs/splash.html`
- Session page: `/etc/nodogsplash/htdocs/session.html`
- Installation log: `/etc/zaanet/installation.log`
