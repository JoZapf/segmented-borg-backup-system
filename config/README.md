# Configuration Files

## Security Notice

⚠️ **The actual configuration files contain sensitive information and are excluded from Git!**

Files in `.gitignore`:
- `common.env` - Contains Shelly IP address
- `profiles/system.env` - Contains backup HDD UUID, hostname, device names
- `profiles/data.env` - Contains backup HDD UUID, hostname

## Setup Instructions

### 1. Copy Example Files

```bash
# Copy common configuration
cp config/common.env.example config/common.env

# Copy system profile
cp config/profiles/system.env.example config/profiles/system.env

# Optional: Copy data profile (for second HDD)
cp config/profiles/data.env.example config/profiles/data.env
```

### 2. Edit Configuration Files

#### common.env
Replace:
- `SHELLY_IP="192.168.X.X"` with your actual Shelly Plug IP

#### profiles/system.env
Replace:
- `BACKUP_UUID="REPLACE-WITH-YOUR-BACKUP-HDD-UUID"` with output from `sudo blkid`
- `hostname_nvme0n1_System` with your actual hostname (e.g., `myhostname_nvme0n1_System`)
- `hostname-nvme0n1-system` with your actual hostname (e.g., `myhostname-nvme0n1-system`)
- `HDD_DEVICE="/dev/sdX"` with your actual backup HDD device (find with `lsblk`)

#### profiles/data.env (optional)
Replace:
- `BACKUP_UUID="REPLACE-WITH-YOUR-DATA-HDD-UUID"` with UUID of second HDD
- `hostname_Data` with your actual hostname (e.g., `myhostname_Data`)
- `hostname-data` with your actual hostname (e.g., `myhostname-data`)

### 3. Secure Permissions

```bash
# Ensure configs are only readable by root
sudo chmod 600 config/common.env
sudo chmod 600 config/profiles/system.env
sudo chmod 600 config/profiles/data.env
```

## Finding Your Values

### Get HDD UUID
```bash
sudo blkid
# Look for your backup HDD and copy the UUID value
```

### Get Hostname
```bash
hostname
# Use this value in TARGET_DIR and ARCHIVE_PREFIX
```

### Get HDD Device
```bash
lsblk
# Look for your backup HDD (e.g., sdc, sdd)
```

### Get Shelly IP
```bash
# Check your router's DHCP leases or Shelly app
# Should be on your local network (e.g., 192.168.x.x)
```

## Example Values

**Example common.env:**
```bash
export SHELLY_IP="192.168.1.100"
```

**Example system.env:**
```bash
export BACKUP_UUID="a1b2c3d4-e5f6-7890-abcd-ef1234567890"
export TARGET_DIR="${BACKUP_MNT}/mylaptop_nvme0n1_System"
export HDD_DEVICE="/dev/sdc"
export ARCHIVE_PREFIX="mylaptop-nvme0n1-system"
```

## Security Best Practices

1. ✅ Never commit actual config files to Git
2. ✅ Keep configs readable only by root (chmod 600)
3. ✅ Back up your configs securely (encrypted)
4. ✅ Document your UUIDs separately (password manager)
5. ✅ Keep Borg passphrase in a secure location

## Troubleshooting

**Error: "Configuration file not found"**
→ You forgot to copy the .example files

**Error: "BACKUP_UUID contains REPLACE"**
→ You forgot to edit the config file with actual values

**Error: "Wrong UUID mounted"**
→ Double-check your BACKUP_UUID matches your backup HDD
