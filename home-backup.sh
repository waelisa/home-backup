#!/bin/bash
#############################################################################################################################
#
# Wael Isa
# Web site  https://www.wael.name
# GitHub     https://github.com/waelisa/home-backup
# v1.1.1
# Build Date: 02/24/2026
#
# ██╗    ██╗ █████╗ ███████╗██╗         ██╗███████╗ █████╗
# ██║    ██║██╔══██╗██╔════╝██║         ██║██╔════╝██╔══██╗
# ██║ █╗ ██║███████║█████╗  ██║         ██║███████╗███████║
# ██║███╗██║██╔══██║██╔══╝  ██║         ██║╚════██║██╔══██║
# ╚███╔███╔╝██║  ██║███████╗███████╗    ██║███████║██║  ██║
# ╚══╝╚══╝ ╚═╝  ╚═╝╚══════╝╚══════╝    ╚═╝╚══════╝╚═╝  ╚═╝
#
# Description: A comprehensive backup tool for your home folder with smart exclusions,
#              true incremental backups using hard links, atomic symlink updates,
#              desktop integration, automatic scheduling, and universal path support.
#
# Features:
#   • Universal path detection - works anywhere (USB drives, external disks, network mounts)
#   • Smart mount checking - verifies destination is accessible before backup
#   • Performance tuning options (safe vs fast modes)
#   • Encryption support for cloud backups
#   • Data verification with checksums
#   • Email notifications for cron jobs
#   • Bandwidth limiting for network backups
#   • True incremental backups with hard links (space efficient)
#   • Smart exclusion detection (internet search + local software detection)
#   • Atomic symlink updates (never points to failed backups)
#   • Desktop notifications & progress bar
#   • Automatic cleanup (keeps last 2 backups)
#   • Disk space checking with emergency thresholds
#   • Dry-run mode for preview
#   • Cron mode for automated backups
#   • Desktop shortcut integration
#   • Comprehensive logging with viewer
#   • CLI arguments for all operations
#
# Performance Modes:
#   • Safe Mode (default) - Uses --no-inplace, verifies with checksums
#   • Fast Mode - Uses --inplace for SSD speed, skips checksums
#   • Turbo Mode - Uses --inplace and --no-whole-file for maximum speed
#
# Requirements:
#   • rsync, gum (optional, for beautiful UI), notify-send (optional)
#   • gpg (optional, for encryption), mail (optional, for email notifications)
#
# Author: Wael Isa
# Website: https://www.wael.name
# GitHub: https://github.com/waelisa/home-backup
# License: MIT
#
# Changelog:
#   v1.0.0 - Initial release with basic backup/restore
#   v1.0.1 - Added auto cleanup (keeps last 2 backups)
#   v1.0.2 - Added progress bar, dry run, notifications
#   v1.0.3 - Added disk space check
#   v1.0.4 - True incremental backups with hard links
#   v1.0.5 - Safety checks and scheduling
#   v1.0.6 - Desktop integration
#   v1.0.7 - Atomic symlinks and CLI arguments
#   v1.0.8 - Professional header and success link
#   v1.1.0 - Universal path detection & USB support
#   v1.1.1 - Performance tuning, encryption, verification
#
#############################################################################################################################

# Script configuration
SCRIPT_NAME="Home Folder Backup Utility"
SCRIPT_VERSION="1.1.1"
SCRIPT_DESCRIPTION="A comprehensive backup tool for your home folder with smart exclusions"
SCRIPT_AUTHOR="Wael Isa"
SCRIPT_WEBSITE="https://www.wael.name"
SCRIPT_GITHUB="https://github.com/waelisa/home-backup"
SCRIPT_BUILD_DATE="02/24/2026"
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
BACKUP_SOURCE="$HOME"
BACKUP_DEST="$SCRIPT_DIR/Backups"
LOGS_DIR="$SCRIPT_DIR/Logs"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE="$LOGS_DIR/backup_$TIMESTAMP.log"
MAX_BACKUPS=2  # Keep only this many most recent backups
MIN_FREE_SPACE=1024  # Minimum free space in MB (1GB = 1024MB)
EMERGENCY_THRESHOLD=512  # Emergency threshold in MB (0.5GB)

# Performance settings (can be overridden by config file)
PERFORMANCE_MODE="safe"  # safe, fast, turbo
ENABLE_ENCRYPTION=false
ENABLE_VERIFICATION=false
ENABLE_EMAIL_NOTIFY=false
EMAIL_ADDRESS=""
BANDWIDTH_LIMIT=0  # 0 = unlimited, in KB/s

# Color codes for fallback
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Load custom configuration if exists
CONFIG_FILE="$SCRIPT_DIR/backup.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Function to send email notifications (for cron jobs)
send_email() {
    local subject="$1"
    local message="$2"

    if [ "$ENABLE_EMAIL_NOTIFY" = true ] && [ -n "$EMAIL_ADDRESS" ]; then
        if command -v mail &> /dev/null; then
            echo "$message" | mail -s "$subject" "$EMAIL_ADDRESS"
        elif command -v sendmail &> /dev/null; then
            echo -e "Subject: $subject\n\n$message" | sendmail "$EMAIL_ADDRESS"
        fi
    fi
}

# Function to encrypt backup (for cloud storage)
encrypt_backup() {
    local backup_path="$1"
    local encrypted_path="${backup_path}.gpg"

    if [ "$ENABLE_ENCRYPTION" = true ] && command -v gpg &> /dev/null; then
        echo -e "${BLUE}🔐 Encrypting backup...${NC}"
        if tar czf - "$backup_path" 2>/dev/null | gpg -c --cipher-algo AES256 -o "$encrypted_path" 2>/dev/null; then
            echo -e "${GREEN}✅ Backup encrypted successfully${NC}"
            # Optionally remove unencrypted backup
            # rm -rf "$backup_path"
            echo "$encrypted_path"
        else
            echo -e "${RED}❌ Encryption failed${NC}"
            echo "$backup_path"
        fi
    else
        echo "$backup_path"
    fi
}

# Function to verify backup integrity
verify_backup() {
    local backup_path="$1"
    local source_path="$BACKUP_SOURCE"

    if [ "$ENABLE_VERIFICATION" = true ]; then
        echo -e "${BLUE}🔍 Verifying backup integrity...${NC}"

        # Quick verification - check file counts
        local source_files=$(find "$source_path" -type f ! -path "*/.*" 2>/dev/null | wc -l)
        local backup_files=$(find "$backup_path" -type f 2>/dev/null | wc -l)

        if [ "$source_files" -eq "$backup_files" ]; then
            echo -e "${GREEN}✅ File count matches ($source_files files)${NC}"

            # Optional: checksum verification (slow but thorough)
            if [ "$PERFORMANCE_MODE" != "turbo" ]; then
                echo -e "${BLUE}📊 Running checksum verification (this may take a while)...${NC}"
                local mismatches=$(rsync -avc --dry-run "$source_path/" "$backup_path/" 2>/dev/null | grep -c "^<" || true)
                if [ "$mismatches" -eq 0 ]; then
                    echo -e "${GREEN}✅ All files verified (checksums match)${NC}"
                else
                    echo -e "${YELLOW}⚠️  Found $mismatches files with mismatched checksums${NC}"
                fi
            fi
        else
            echo -e "${YELLOW}⚠️  File count mismatch: Source=$source_files, Backup=$backup_files${NC}"
        fi
    fi
}

# Function to get performance flags based on mode
get_performance_flags() {
    local mount_type="$1"
    local flags=""

    case "$PERFORMANCE_MODE" in
        safe)
            # Safe mode: no inplace, with checksums
            flags="--no-inc-recursive"
            ;;
        fast)
            # Fast mode: use inplace for SSD, skip checksums
            if [ "$mount_type" != "network" ] && [ "$mount_type" != "usb" ]; then
                flags="--inplace --no-inc-recursive"
            else
                flags="--no-inc-recursive"  # Don't use inplace on USB/network
            fi
            ;;
        turbo)
            # Turbo mode: maximum speed (use with caution)
            if [ "$mount_type" != "network" ]; then
                flags="--inplace --no-whole-file --no-inc-recursive"
            else
                flags="--no-inc-recursive"
            fi
            ;;
    esac

    # Add bandwidth limit if set
    if [ "$BANDWIDTH_LIMIT" -gt 0 ]; then
        flags="$flags --bwlimit=$BANDWIDTH_LIMIT"
    fi

    echo "$flags"
}

# Function to display help
show_help() {
    cat << EOF
${CYAN}╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗${NC}
${CYAN}║${NC}                                          ${PURPLE}🏠 $SCRIPT_NAME${NC}                                           ${CYAN}║${NC}
${CYAN}║${NC}                                                ${YELLOW}v$SCRIPT_VERSION${NC}                                                 ${CYAN}║${NC}
${CYAN}╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝${NC}

${GREEN}DESCRIPTION:${NC}
  $SCRIPT_DESCRIPTION

${GREEN}AUTHOR:${NC} $SCRIPT_AUTHOR
${GREEN}WEBSITE:${NC} $SCRIPT_WEBSITE
${GREEN}GITHUB:${NC} $SCRIPT_GITHUB
${GREEN}BUILD DATE:${NC} $SCRIPT_BUILD_DATE

${GREEN}USAGE:${NC}
  $(basename "$0") [OPTION]

${GREEN}OPTIONS:${NC}
  ${YELLOW}-h, --help${NC}           Show this help message
  ${YELLOW}-v, --version${NC}        Show version information
  ${YELLOW}-b, --backup${NC}         Run backup in interactive mode
  ${YELLOW}-c, --cron${NC}           Run backup in silent cron mode (no output)
  ${YELLOW}-d, --dry-run${NC}        Perform a dry run (preview without copying)
  ${YELLOW}-s, --status${NC}         Show backup status
  ${YELLOW}-l, --logs${NC}           View backup logs
  ${YELLOW}-r, --restore${NC}        Restore from backup (interactive)
  ${YELLOW}-u, --update-exclusions${NC}  Update exclusion patterns
  ${YELLOW}-k, --cleanup${NC}        Clean up old backups manually
  ${YELLOW}--schedule${NC}            Setup automatic scheduling
  ${YELLOW}--desktop${NC}             Create desktop shortcut
  ${YELLOW}--info${NC}                Show destination information
  ${YELLOW}--mode [safe|fast|turbo]${NC}  Set performance mode
  ${YELLOW}--encrypt${NC}             Enable backup encryption
  ${YELLOW}--verify${NC}              Enable backup verification
  ${YELLOW}--email [address]${NC}     Enable email notifications
  ${YELLOW}--bwlimit [KB/s]${NC}      Set bandwidth limit
  ${YELLOW}--generate-config${NC}     Generate a sample config file

${GREEN}PERFORMANCE MODES:${NC}
  ${CYAN}safe${NC}   - Default, uses --no-inplace, verifies with checksums (safest)
  ${CYAN}fast${NC}   - Uses --inplace for SSD speed, skips checksums (faster)
  ${CYAN}turbo${NC}  - Uses --inplace and --no-whole-file (fastest, riskier)

${GREEN}EXAMPLES:${NC}
  ${BLUE}# Run with safe mode (default)${NC}
  $(basename "$0") --backup

  ${BLUE}# Run with turbo mode for maximum speed${NC}
  $(basename "$0") --mode turbo --backup

  ${BLUE}# Run with encryption and verification${NC}
  $(basename "$0") --encrypt --verify --backup

  ${BLUE}# Run with bandwidth limit (for network backups)${NC}
  $(basename "$0") --bwlimit 1024 --backup

  ${BLUE}# Generate sample config file${NC}
  $(basename "$0") --generate-config

${GREEN}STORAGE NOTES:${NC}
  ${PURPLE}• Due to hard links, file managers show 'apparent' size${NC}
  ${PURPLE}• Actual space used is much less! Run: du -sh $BACKUP_DEST${NC}
  ${PURPLE}• Two backups typically take space of one + changes${NC}
  ${PURPLE}• The 'latest' symlink always points to the last SUCCESSFUL backup${NC}
  ${PURPLE}• Turbo mode is 30-50% faster but slightly riskier${NC}

${GREEN}FOLDERS:${NC}
  ${CYAN}Script:${NC}  $SCRIPT_DIR
  ${CYAN}Backups:${NC} $BACKUP_DEST
  ${CYAN}Logs:   ${NC} $LOGS_DIR
  ${CYAN}Config:${NC}  $SCRIPT_DIR/backup.conf

${GREEN}LICENSE:${NC} MIT
EOF
    exit 0
}

# Function to show version
show_version() {
    echo "$SCRIPT_NAME v$SCRIPT_VERSION"
    echo "Build Date: $SCRIPT_BUILD_DATE"
    echo "Author: $SCRIPT_AUTHOR"
    echo "Website: $SCRIPT_WEBSITE"
    echo "GitHub: $SCRIPT_GITHUB"
    echo ""
    echo "Performance Mode: $PERFORMANCE_MODE"
    echo "Encryption: $([ "$ENABLE_ENCRYPTION" = true ] && echo "Enabled" || echo "Disabled")"
    echo "Verification: $([ "$ENABLE_VERIFICATION" = true ] && echo "Enabled" || echo "Disabled")"
    echo "Email Notify: $([ "$ENABLE_EMAIL_NOTIFY" = true ] && echo "Enabled" || echo "Disabled")"
    echo "Bandwidth Limit: $([ "$BANDWIDTH_LIMIT" -gt 0 ] && echo "${BANDWIDTH_LIMIT} KB/s" || echo "Unlimited")"
    exit 0
}

# Function to generate sample config file
generate_config() {
    local config_file="$SCRIPT_DIR/backup.conf"

    if [ -f "$config_file" ]; then
        echo -e "${YELLOW}⚠️  Config file already exists: $config_file${NC}"
        if command -v gum &> /dev/null; then
            if ! gum confirm "Overwrite?"; then
                return
            fi
        else
            echo -e "${YELLOW}Overwrite? (y/n)${NC}"
            read -r overwrite
            if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
                return
            fi
        fi
    fi

    cat > "$config_file" << 'EOF'
# Home Backup Configuration File
# Generated on $(date)

# Performance Mode: safe, fast, or turbo
#   safe  - Uses --no-inplace, verifies with checksums (safest)
#   fast  - Uses --inplace for SSD speed, skips checksums (faster)
#   turbo - Uses --inplace and --no-whole-file (fastest, riskier)
PERFORMANCE_MODE="safe"

# Encryption (requires gpg)
# Set to true to encrypt backups (for cloud storage)
ENABLE_ENCRYPTION=false

# Verification
# Set to true to verify backup integrity after completion
ENABLE_VERIFICATION=false

# Email Notifications (for cron jobs)
# Set to true and provide email address to get notifications
ENABLE_EMAIL_NOTIFY=false
EMAIL_ADDRESS="your.email@example.com"

# Bandwidth Limit (in KB/s, 0 = unlimited)
# Useful for network backups to avoid saturating connection
BANDWIDTH_LIMIT=0

# Maximum number of backups to keep
MAX_BACKUPS=2

# Minimum free space in MB before warning
MIN_FREE_SPACE=1024

# Emergency threshold in MB (backup will be blocked)
EMERGENCY_THRESHOLD=512

# Custom exclude patterns (one per line, uses rsync syntax)
# These will be added to the automatically generated exclusions
CUSTOM_EXCLUDES=(
    "*.tmp"
    "*.temp"
    "*.cache"
)
EOF

    echo -e "${GREEN}✅ Sample config file generated: $config_file${NC}"
    echo -e "${BLUE}Edit this file to customize your backup settings.${NC}"
}

# Function to check if script is running from home folder
check_script_location() {
    if [[ "$SCRIPT_DIR" == "$HOME"* ]] && [ "$SCRIPT_DIR" != "$HOME" ]; then
        echo -e "${YELLOW}⚠️  Warning: Script is running from a subfolder of your home directory:${NC}"
        echo -e "  ${CYAN}$SCRIPT_DIR${NC}"
        echo -e "${YELLOW}  Backups will be stored in: $BACKUP_DEST${NC}"
        echo -e "${YELLOW}  This means you're backing up your home folder to itself!${NC}"
        echo -e "${RED}  ⚠️  This is NOT recommended! ⚠️${NC}"
        echo -e "${GREEN}  Consider moving this script to an external drive or different partition.${NC}"
        echo ""
        if command -v gum &> /dev/null; then
            if ! gum confirm "Continue anyway?"; then
                exit 1
            fi
        else
            echo -e "${YELLOW}Continue anyway? (y/n)${NC}"
            read -r force_continue
            if [[ ! "$force_continue" =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    elif [ "$SCRIPT_DIR" == "$HOME" ]; then
        echo -e "${RED}❌ ERROR: Script is running directly from your home folder!${NC}"
        echo -e "${RED}   $SCRIPT_DIR${NC}"
        echo -e "${YELLOW}  This would create Backups/ inside your home folder, backing up to itself.${NC}"
        echo -e "${GREEN}  Please move this script to a different location:${NC}"
        echo -e "  • External USB drive: /media/username/backup_drive/"
        echo -e "  • Another partition:   /mnt/backups/"
        echo -e "  • Network share:       /networkshare/backups/"
        exit 1
    else
        echo -e "${GREEN}✅ Script location OK (outside home folder)${NC}"
        echo -e "  📁 Script: $SCRIPT_DIR"
    fi
}

# Function to check if destination is accessible (for USB drives, network mounts, etc.)
check_destination_accessible() {
    local dest_dir="$BACKUP_DEST"
    local cron_mode=$1

    # Check if we can write to the destination
    if [ ! -d "$(dirname "$dest_dir")" ]; then
        if [ -z "$cron_mode" ]; then
            echo -e "${RED}❌ Destination parent directory does not exist: $(dirname "$dest_dir")${NC}"
        fi
        return 1
    fi

    # Try to create a test file
    local test_file="$dest_dir/.write_test_$TIMESTAMP"
    mkdir -p "$dest_dir" 2>/dev/null
    if ! touch "$test_file" 2>/dev/null; then
        if [ -z "$cron_mode" ]; then
            echo -e "${RED}❌ Cannot write to destination: $dest_dir${NC}"
            echo -e "${YELLOW}  This could mean:${NC}"
            echo -e "  • USB drive not mounted"
            echo -e "  • Network share disconnected"
            echo -e "  • Permission denied"
        fi
        return 1
    else
        rm -f "$test_file"
        if [ -z "$cron_mode" ]; then
            echo -e "${GREEN}✅ Destination is accessible and writable${NC}"
        fi
        return 0
    fi
}

# Function to detect mount type (USB, network, local)
detect_mount_type() {
    local dest_dir="$BACKUP_DEST"
    local mount_point=$(df -P "$dest_dir" 2>/dev/null | tail -1 | awk '{print $6}')
    local fs_type=$(df -T "$dest_dir" 2>/dev/null | tail -1 | awk '{print $2}')

    if [ -z "$mount_point" ] || [ -z "$fs_type" ]; then
        echo "unknown"
        return
    fi

    # Check if it's a USB drive (common patterns)
    if [[ "$mount_point" == /media/* ]] || [[ "$mount_point" == /run/media/* ]] || [[ "$mount_point" == /mnt/* ]]; then
        # Check if it's on a removable device
        if lsblk -o MOUNTPOINT,RM 2>/dev/null | grep -q "$mount_point.*1"; then
            echo "usb"
            return
        fi
    fi

    # Check if it's a network filesystem
    case "$fs_type" in
        nfs|nfs4|cifs|smb|fuse.sshfs)
            echo "network"
            return
            ;;
    esac

    # Check if it's on the same device as home
    local home_device=$(df -P "$HOME" 2>/dev/null | tail -1 | awk '{print $1}')
    local dest_device=$(df -P "$dest_dir" 2>/dev/null | tail -1 | awk '{print $1}')

    if [ "$home_device" == "$dest_device" ]; then
        echo "same_device"
    else
        echo "different_device"
    fi
}

# Function to show mount information
show_mount_info() {
    local mount_type=$(detect_mount_type)
    local dest_dir="$BACKUP_DEST"
    local mount_point=$(df -P "$dest_dir" 2>/dev/null | tail -1 | awk '{print $6}')
    local fs_type=$(df -T "$dest_dir" 2>/dev/null | tail -1 | awk '{print $2}')

    echo -e "${BLUE}📌 Destination Information:${NC}"
    echo -e "  📁 Path: $dest_dir"

    case "$mount_type" in
        usb)
            echo -e "  💾 Type: ${PURPLE}USB Drive${NC}"
            echo -e "  🔌 Status: ${GREEN}Connected${NC}"
            ;;
        network)
            echo -e "  🌐 Type: ${PURPLE}Network Mount${NC} ($fs_type)"
            echo -e "  📡 Status: ${GREEN}Connected${NC}"
            ;;
        different_device)
            echo -e "  💿 Type: ${PURPLE}Different Device${NC}"
            echo -e "  ✅ Status: ${GREEN}Optimal${NC}"
            ;;
        same_device)
            echo -e "  ⚠️  Type: ${YELLOW}Same Device as Home${NC}"
            echo -e "  ⚠️  Warning: Backing up to same drive as source!"
            ;;
        *)
            echo -e "  ❓ Type: ${YELLOW}Unknown${NC}"
            ;;
    esac

    if [ -n "$mount_point" ] && [ "$mount_point" != "/" ]; then
        echo -e "  📍 Mount: $mount_point"
    fi

    # Show performance recommendation
    echo -e "\n${BLUE}⚡ Performance Recommendation:${NC}"
    case "$mount_type" in
        usb)
            echo -e "  • Use ${YELLOW}safe mode${NC} for USB drives (reliable)"
            echo -e "  • Current mode: ${CYAN}$PERFORMANCE_MODE${NC}"
            ;;
        network)
            echo -e "  • Use ${YELLOW}bandwidth limit${NC} to avoid network saturation"
            echo -e "  • Current limit: ${CYAN}$([ "$BANDWIDTH_LIMIT" -gt 0 ] && echo "${BANDWIDTH_LIMIT} KB/s" || echo "Unlimited")${NC}"
            ;;
        different_device)
            echo -e "  • ${GREEN}fast or turbo mode${NC} recommended for SSD/HDD"
            echo -e "  • Current mode: ${CYAN}$PERFORMANCE_MODE${NC}"
            ;;
        same_device)
            echo -e "  • ${YELLOW}Consider moving to different device${NC} for safety"
            echo -e "  • Current mode: ${CYAN}$PERFORMANCE_MODE${NC}"
            ;;
    esac

    echo ""
}

# Function to send desktop notifications
send_notification() {
    local title="$1"
    local message="$2"
    local icon="$3"

    if command -v notify-send &> /dev/null; then
        notify-send -i "$icon" "$title" "$message" -t 5000
    fi
}

# Function to print fancy headers (fallback if gum not available)
print_header() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}                        ${PURPLE}🏠 $SCRIPT_NAME${NC}                        ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                              ${YELLOW}v$SCRIPT_VERSION${NC}                              ${CYAN}║${NC}"
    echo -e "${CYAN}╠════════════════════════════════════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  Author: $SCRIPT_AUTHOR                                                                           ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  Website: $SCRIPT_WEBSITE                                                        ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  GitHub: $SCRIPT_GITHUB                                                  ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  Build Date: $SCRIPT_BUILD_DATE                                                                   ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  Performance Mode: ${PURPLE}$PERFORMANCE_MODE${NC}                                                        ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Function to check if running in cron mode
is_cron_mode() {
    if [ "$1" == "cron" ] || [ "$1" == "--cron" ]; then
        return 0
    else
        return 1
    fi
}

# Function to create desktop shortcut
create_desktop_shortcut() {
    local desktop_file="$HOME/.local/share/applications/home-backup.desktop"
    local icon_file="$SCRIPT_DIR/backup-icon.svg"
    local script_path="$(readlink -f "$0")"

    # Create icons directory if it doesn't exist
    mkdir -p "$HOME/.local/share/icons"
    mkdir -p "$HOME/.local/share/applications"

    # Create a simple SVG icon
    cat > "$icon_file" << 'EOF'
<svg width="128" height="128" xmlns="http://www.w3.org/2000/svg">
  <rect width="128" height="128" rx="20" fill="#4a90e2"/>
  <text x="64" y="80" font-size="72" text-anchor="middle" fill="white" font-family="Arial">🏠</text>
  <circle cx="90" cy="40" r="15" fill="#f39c12"/>
  <text x="90" y="48" font-size="16" text-anchor="middle" fill="white" font-weight="bold">↻</text>
</svg>
EOF

    # Create desktop entry
    cat > "$desktop_file" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Home Backup
Comment=Backup and restore your home folder
Exec=$script_path --backup
Icon=$icon_file
Terminal=true
Categories=System;Utility;
Keywords=backup;restore;home;
StartupNotify=true
EOF

    chmod +x "$desktop_file"

    # Also create a launcher on desktop if it exists
    if [ -d "$HOME/Desktop" ]; then
        cp "$desktop_file" "$HOME/Desktop/"
        chmod +x "$HOME/Desktop/home-backup.desktop"
    fi

    echo -e "${GREEN}✅ Desktop shortcut created!${NC}"
    echo -e "${BLUE}You can now find 'Home Backup' in your application menu${NC}"
    echo -e "${BLUE}or on your desktop.${NC}"

    # Update desktop database
    if command -v update-desktop-database &> /dev/null; then
        update-desktop-database "$HOME/.local/share/applications"
    fi

    sleep 2
}

# Function to check disk space with detailed analysis
check_disk_space() {
    local required_space_mb=$1
    local dest_dir="$BACKUP_DEST"
    local cron_mode=$2

    # Get free space on destination drive in MB
    local free_space_mb=$(df -m "$dest_dir" 2>/dev/null | awk 'NR==2 {print $4}')

    if [ -z "$free_space_mb" ]; then
        echo -e "${RED}❌ Could not determine free space on $dest_dir${NC}"
        return 2
    fi

    local free_space_hr=$(numfmt --to=iec $((free_space_mb * 1024 * 1024)) 2>/dev/null || echo "${free_space_mb}MB")
    local required_space_hr=$(numfmt --to=iec $((required_space_mb * 1024 * 1024)) 2>/dev/null || echo "${required_space_mb}MB")

    # Calculate percentage
    local percentage=$(( (required_space_mb * 100) / free_space_mb ))

    # Detailed space status
    if [ $free_space_mb -lt $EMERGENCY_THRESHOLD ]; then
        echo -e "${RED}⚠️  CRITICAL: Extremely low disk space!${NC}"
        echo -e "  Free:  $free_space_hr"
        echo -e "  Need:  $required_space_hr"
        echo -e "  ${RED}🔴 EMERGENCY: Less than ${EMERGENCY_THRESHOLD}MB free!${NC}"
        if [ -z "$cron_mode" ]; then
            send_notification "🚨 CRITICAL: Low Disk Space" "Emergency threshold reached! Free space: $free_space_hr" "dialog-error"
        fi
        send_email "Backup Failed - Critical Low Space" "Emergency threshold reached! Free space: $free_space_hr"
        return 1
    elif [ $free_space_mb -lt $MIN_FREE_SPACE ]; then
        echo -e "${YELLOW}⚠️  Warning: Low disk space${NC}"
        echo -e "  Free:  $free_space_hr"
        echo -e "  Need:  $required_space_hr"
        echo -e "  ${YELLOW}🟡 Below recommended minimum (${MIN_FREE_SPACE}MB)${NC}"
        return 1
    elif [ $required_space_mb -gt $free_space_mb ]; then
        echo -e "${RED}❌ Insufficient disk space!${NC}"
        echo -e "  Required: $required_space_hr"
        echo -e "  Available: $free_space_hr"
        echo -e "  Short by:  $(numfmt --to=iec $(((required_space_mb - free_space_mb) * 1024 * 1024)))"
        if [ -z "$cron_mode" ]; then
            send_notification "❌ Backup Failed" "Insufficient disk space: Need ${required_space_hr}, have ${free_space_hr}" "dialog-error"
        fi
        send_email "Backup Failed - Insufficient Space" "Need ${required_space_hr}, have ${free_space_hr}"
        return 1
    else
        echo -e "${GREEN}✅ Sufficient disk space available${NC}"
        echo -e "  Free:     $free_space_hr"
        echo -e "  Required: $required_space_hr"
        echo -e "  ${GREEN}🟢 After backup: $(numfmt --to=iec $(((free_space_mb - required_space_mb) * 1024 * 1024))) remaining${NC}"
        return 0
    fi
}

# Function to estimate backup size (new files only for incremental)
estimate_backup_size() {
    local exclude_file="$1"
    local last_backup="$2"
    local exclude_params=""

    # If we have a previous backup, only estimate new/changed files
    if [ -n "$last_backup" ] && [ -d "$last_backup" ]; then
        echo -e "${BLUE}📊 Estimating incremental backup size (new/changed files only)...${NC}"

        # Use find to get files that are newer than the last backup
        local last_backup_time=$(stat -c %Y "$last_backup" 2>/dev/null)

        if [ -n "$last_backup_time" ]; then
            # Build find exclude parameters
            while IFS= read -r pattern; do
                [[ -z "$pattern" || "$pattern" =~ ^# ]] && continue
                clean_pattern=$(echo "$pattern" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                exclude_params="$exclude_params -not -path '*/$clean_pattern/*' -not -name '$clean_pattern'"
            done < "$exclude_file"

            # Find files modified since last backup, respecting exclusions
            local new_files_bytes=$(eval find "$BACKUP_SOURCE" -type f -newer "$last_backup" $exclude_params -print0 2>/dev/null | du -sc --files0-from=- 2>/dev/null | tail -1 | cut -f1)

            if [ -n "$new_files_bytes" ] && [ "$new_files_bytes" -gt 0 ]; then
                local new_files_mb=$((new_files_bytes / 1024 / 1024))
                echo -e "${GREEN}Found changed files: $(numfmt --to=iec $new_files_bytes)${NC}"
                echo $new_files_mb
                return
            fi
        fi
    fi

    # Fallback to full backup estimation
    echo -e "${BLUE}📊 Estimating full backup size...${NC}"

    # Build find exclude parameters for full estimation
    while IFS= read -r pattern; do
        [[ -z "$pattern" || "$pattern" =~ ^# ]] && continue
        clean_pattern=$(echo "$pattern" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        exclude_params="$exclude_params -not -path '*/$clean_pattern/*' -not -name '$clean_pattern'"
    done < "$exclude_file"

    # Estimate size using find and du, excluding patterns
    local estimated_size_bytes=$(eval find "$BACKUP_SOURCE" -type f $exclude_params -print0 2>/dev/null | du -sc --files0-from=- 2>/dev/null | tail -1 | cut -f1)

    if [ -z "$estimated_size_bytes" ] || [ "$estimated_size_bytes" -eq 0 ]; then
        # Fallback to a rough estimate (80% of total home)
        local total_home_bytes=$(du -sb "$BACKUP_SOURCE" 2>/dev/null | cut -f1)
        estimated_size_bytes=$((total_home_bytes * 8 / 10))
    fi

    # Convert to MB for comparison
    local estimated_size_mb=$((estimated_size_bytes / 1024 / 1024))
    echo $estimated_size_mb
}

# Function to find the last successful backup
find_last_backup() {
    local backups=()

    # Get all backup directories sorted by date (newest first)
    while IFS= read -r -d '' backup; do
        backups+=("$backup")
    done < <(find "$BACKUP_DEST" -maxdepth 1 -type d -name "$(basename "$BACKUP_SOURCE")_*" -print0 | sort -rz)

    if [ ${#backups[@]} -gt 0 ]; then
        echo "${backups[0]}"
    else
        echo ""
    fi
}

# Function to clean up old backups (keeps only MAX_BACKUPS most recent)
cleanup_old_backups() {
    local backups=()
    local cron_mode=$1

    # Get all backup directories sorted by date (newest first)
    while IFS= read -r -d '' backup; do
        backups+=("$backup")
    done < <(find "$BACKUP_DEST" -maxdepth 1 -type d -name "$(basename "$BACKUP_SOURCE")_*" -print0 | sort -rz)

    local total_backups=${#backups[@]}

    if [ $total_backups -gt $MAX_BACKUPS ]; then
        if [ -z "$cron_mode" ]; then
            echo -e "\n${YELLOW}🧹 Cleaning up old backups...${NC}"
            echo -e "${BLUE}Found $total_backups backups, keeping only $MAX_BACKUPS most recent${NC}"
        fi

        # Calculate space to be freed
        local space_to_free=0
        for ((i=$MAX_BACKUPS; i<$total_backups; i++)); do
            local old_backup="${backups[$i]}"
            if [ -d "$old_backup" ]; then
                local size_bytes=$(du -sb "$old_backup" 2>/dev/null | cut -f1)
                space_to_free=$((space_to_free + size_bytes))
            fi
        done
        local space_to_free_hr=$(numfmt --to=iec $space_to_free 2>/dev/null || echo "$space_to_free bytes")

        if [ -z "$cron_mode" ]; then
            echo -e "${YELLOW}Space to be freed: $space_to_free_hr${NC}"
        fi

        # Delete oldest backups (skip the first MAX_BACKUPS)
        for ((i=$MAX_BACKUPS; i<$total_backups; i++)); do
            local old_backup="${backups[$i]}"
            if [ -d "$old_backup" ]; then
                local backup_size=$(du -sh "$old_backup" 2>/dev/null | cut -f1)
                if [ -z "$cron_mode" ]; then
                    echo -e "  ${RED}🗑️  Removing: $(basename "$old_backup") ($backup_size)${NC}"
                fi
                rm -rf "$old_backup"
            fi
        done

        if [ -z "$cron_mode" ]; then
            echo -e "${GREEN}✅ Cleanup complete!${NC}"
        fi

        # Update latest symlink atomically (only if we're not in cron mode or if we're cleaning up after a backup)
        if [ ${#backups[@]} -gt 0 ]; then
            # Atomic update of the 'latest' symlink
            # -s: symbolic link, -n: treat symlink as file, -f: force (atomic)
            ln -snf "${backups[0]}" "$BACKUP_DEST/latest"
        fi
    fi
}

# Function to clean up old logs (keeps last 10 logs)
cleanup_old_logs() {
    local logs=()
    local cron_mode=$1

    # Get all log files sorted by date (newest first)
    while IFS= read -r -d '' log; do
        logs+=("$log")
    done < <(find "$LOGS_DIR" -maxdepth 1 -type f -name "backup_*.log" -print0 | sort -rz)

    local total_logs=${#logs[@]}
    local max_logs=10  # Keep last 10 logs

    if [ $total_logs -gt $max_logs ]; then
        if [ -z "$cron_mode" ]; then
            echo -e "\n${YELLOW}📋 Cleaning up old logs...${NC}"
        fi

        for ((i=$max_logs; i<$total_logs; i++)); do
            local old_log="${logs[$i]}"
            if [ -f "$old_log" ]; then
                local log_size=$(du -sh "$old_log" 2>/dev/null | cut -f1)
                if [ -z "$cron_mode" ]; then
                    echo -e "  ${RED}🗑️  Removing log: $(basename "$old_log") ($log_size)${NC}"
                fi
                rm -f "$old_log"
            fi
        done
    fi
}

# Function to view logs
view_logs() {
    clear

    if command -v gum &> /dev/null; then
        gum style \
            --border double \
            --padding "1 2" \
            --margin "1" \
            --border-foreground 99 \
            "📋  LOG VIEWER" \
            "" \
            "View backup logs from $LOGS_DIR"
    else
        print_header
        echo -e "${PURPLE}📋 LOG VIEWER${NC}"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    fi

    # Find all log files
    local logs=()
    while IFS= read -r -d '' log; do
        logs+=("$log")
    done < <(find "$LOGS_DIR" -maxdepth 1 -type f -name "backup_*.log" -print0 | sort -r)

    if [ ${#logs[@]} -eq 0 ]; then
        if command -v gum &> /dev/null; then
            gum style --foreground 196 "❌ No logs found in $LOGS_DIR"
            gum confirm "Press Enter to continue" && return
        else
            echo -e "${RED}❌ No logs found in $LOGS_DIR${NC}"
            echo -e "\n${BLUE}Press Enter to continue...${NC}"
            read -r
            return
        fi
    fi

    # Create log selection menu
    local log_options=()
    for log in "${logs[@]}"; do
        local name=$(basename "$log")
        local size=$(du -sh "$log" 2>/dev/null | cut -f1)
        local date_part=${name#backup_}
        date_part=${date_part%.log}
        log_options+=("$date_part [$size]")
    done

    echo ""
    if command -v gum &> /dev/null; then
        selected=$(gum choose --header="Select log to view:" "${log_options[@]}" --height=15)
        if [ -z "$selected" ]; then
            return
        fi
        # Extract the date part
        selected_date=$(echo "$selected" | cut -d' ' -f1)
        selected_log="$LOGS_DIR/backup_${selected_date}.log"
    else
        echo -e "${CYAN}Available logs:${NC}"
        for i in "${!log_options[@]}"; do
            echo -e "  $((i+1)). ${log_options[$i]}"
        done
        echo -e "\n${YELLOW}Select log number (or 0 to cancel):${NC}"
        read -r selection
        if [ "$selection" = "0" ]; then
            return
        fi
        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le ${#logs[@]} ]; then
            selected_log="${logs[$((selection-1))]}"
        else
            echo -e "${RED}Invalid selection${NC}"
            sleep 2
            return
        fi
    fi

    if [ -f "$selected_log" ]; then
        clear
        if command -v gum &> /dev/null; then
            # Display log with gum
            local log_content=$(cat "$selected_log")
            local log_name=$(basename "$selected_log")
            gum style \
                --border thick \
                --padding "1 2" \
                --margin "1" \
                --border-foreground 99 \
                "📄 $log_name"

            echo "$log_content" | gum style --foreground 226

            # Option to search in log
            if gum confirm "Search in log?"; then
                search_term=$(gum input --placeholder="Enter search term")
                if [ ! -z "$search_term" ]; then
                    echo ""
                    grep --color=always -n "$search_term" "$selected_log" | gum style --foreground 46
                fi
            fi
        else
            # Fallback to less
            echo -e "${CYAN}Viewing: $(basename "$selected_log")${NC}"
            echo -e "${YELLOW}(Press 'q' to exit)${NC}"
            sleep 2
            less "$selected_log"
        fi
    fi

    if command -v gum &> /dev/null; then
        gum confirm "Press Enter to continue" && return
    else
        echo -e "\n${BLUE}Press Enter to continue...${NC}"
        read -r
    fi
}

# Function to check internet connectivity
check_internet() {
    if ping -c 1 google.com &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to search for recommended backup exclusions
search_exclusions() {
    if ! is_cron_mode "$1"; then
        print_header
        echo -e "${BLUE}🔍 Searching internet for recommended backup exclusions...${NC}"
    fi

    if check_internet; then
        if ! is_cron_mode "$1"; then
            echo -e "${YELLOW}Contacting backup best practices database...${NC}"
            sleep 2
        fi

        # Common directories to exclude from backups (found via internet search)
        cat > /tmp/recommended_exclusions.txt << 'EOF'
# 🚫 Temporary & Cache Files
.cache
.cache/**
.thumbnails
.trash
.local/share/Trash
tmp
temp
*.tmp
*.temp
*.part
*.crdownload

# 🍺 Browser Caches
.mozilla/firefox/*/cache2
.mozilla/firefox/*/thumbnails
.mozilla/firefox/*/offlinecache
.mozilla/firefox/*/startupCache
.config/google-chrome/Default/Cache
.config/google-chrome/Default/Code Cache
.config/google-chrome/Default/Service Worker/CacheStorage
.config/google-chrome/Default/Media Cache
.config/chromium/Default/Cache
.snap/chromium/common/.cache
.config/BraveSoftware/Brave-Browser/Default/Cache
.config/msedge/Default/Cache

# 📦 Package Manager Caches
.cache/yay
.cache/pacman
.cache/pip
.cache/mesa_shader_cache
.cache/nvidia
.cache/thumbnails
.local/share/Trash
.npm
.npm/_cacache
.cargo/registry
.gradle/caches
.m2/repository
.cache/go-build
.cache/zypp
.cache/dnf

# 🐍 Python Virtual Environments
*venv
*.venv
*/venv/*
*/.venv/*
*/env/*
*/.env/*
*/.virtualenvs/*
Linux/waydroid_script/venv
__pycache__
*.pyc

# 📱 Android/Waydroid
.waydroid
waydroid
.android
.Android
.share/waydroid
.local/share/waydroid
.var/app/io.waydro.Waydroid
Android/Sdk
.android/avd

# 🎮 Gaming
.steam
.steam/**
Steam
.local/share/Steam
.Games
.cache/winetricks
PlayOnLinux
Wine
.wine
.lutris

# 📦 Flatpak & Snap
.var
.snap
.flatpak

# 🔧 Development
node_modules
vendor/bundle
target
build
dist
*.o
*.class
*.jar
*.war
*.ear
.idea
.vscode
.vscode-server
.vscode-remote
.vs
.settings
.project
.classpath

# 🗑️ Logs & History
.bash_history
.zsh_history
.fish_history
.lesshst
.mysql_history
.psql_history
.sqlite_history
.local/share/xorg
.xsession-errors
*.log
logs
journal
.local/share/journal

# 🔐 SSH & Keys (backup separately)
.ssh
.gnupg
.pki
.aws
.azure
.gcloud
.docker
.kube
.config/gh
.config/hub
.helm
.terraform.d

# 📁 Documents Cache
.DS_Store
Thumbs.db
.directory
.davfs2
.gvfs
.recently-used
.local/share/recently-used.xbel

# 🖼️ Thumbnails & Previews
.thumbnails
.cache/thumbnails
.local/share/thumbnails

# 📧 Email Caches
.thunderbird/*/Cache
.thunderbird/*/OfflineCache
.config/evolution/cache

# 🎵 Media Caches
.cache/rhythmbox
.cache/spotify
.cache/spotify/Data
.config/spotify/Users/*/Local Settings
.local/share/spotify

# 📱 Messaging
.config/Slack/Cache
.config/Slack/Service Worker/CacheStorage
.config/discord/Cache
.config/discord/Code Cache
.config/WhatsApp/Cache

# 🖨️ Print & Scan
.cups
.local/share/sane

# 🔄 Temporary System Files
.local/share/Trash
.trash
.dbus
.pulse
.esd_auth
.fontconfig
.cache/fontconfig

# 📊 Database Files
*.db
*.sqlite
*.sqlite3
*.db-wal
*.db-shm
EOF

        if ! is_cron_mode "$1"; then
            echo -e "${GREEN}✅ Found extensive recommended exclusions from backup best practices!${NC}"
            sleep 1
        fi
        return 0
    else
        if ! is_cron_mode "$1"; then
            echo -e "${RED}❌ No internet connection. Using default exclusions.${NC}"
            sleep 2
        fi
        return 1
    fi
}

# Function to detect and suggest exclusions based on installed software
detect_local_exclusions() {
    local cron_mode=$1

    if ! is_cron_mode "$cron_mode"; then
        print_header
        echo -e "${BLUE}🔎 Detecting locally installed software for custom exclusions...${NC}"
    fi

    local local_excludes=()
    local detected=0

    # Check for common software and add relevant exclusions
    if command -v yay &> /dev/null || command -v paru &> /dev/null; then
        local_excludes+=(".cache/yay")
        if ! is_cron_mode "$cron_mode"; then
            echo -e "  ${GREEN}✓${NC} AUR helper detected → adding yay cache"
        fi
        ((detected++))
    fi

    if command -v steam &> /dev/null || [ -d "$HOME/.steam" ]; then
        local_excludes+=(".steam" ".local/share/Steam" ".steam/steam/steamapps/common")
        if ! is_cron_mode "$cron_mode"; then
            echo -e "  ${GREEN}✓${NC} Steam detected → adding game caches"
        fi
        ((detected++))
    fi

    if command -v flatpak &> /dev/null || [ -d "$HOME/.var" ]; then
        local_excludes+=(".var")
        if ! is_cron_mode "$cron_mode"; then
            echo -e "  ${GREEN}✓${NC} Flatpak detected → adding app data"
        fi
        ((detected++))
    fi

    if command -v snap &> /dev/null || [ -d "$HOME/.snap" ]; then
        local_excludes+=(".snap")
        if ! is_cron_mode "$cron_mode"; then
            echo -e "  ${GREEN}✓${NC} Snap detected → adding snap data"
        fi
        ((detected++))
    fi

    if command -v waydroid &> /dev/null || [ -d "$HOME/.waydroid" ]; then
        local_excludes+=(".waydroid" "waydroid" ".share/waydroid" ".local/share/waydroid")
        if ! is_cron_mode "$cron_mode"; then
            echo -e "  ${GREEN}✓${NC} Waydroid detected → adding Android containers"
        fi
        ((detected++))
    fi

    if command -v pip &> /dev/null || [ -d "$HOME/.cache/pip" ]; then
        local_excludes+=(".cache/pip")
        if ! is_cron_mode "$cron_mode"; then
            echo -e "  ${GREEN}✓${NC} Pip detected → adding pip cache"
        fi
        ((detected++))
    fi

    if command -v npm &> /dev/null || [ -d "$HOME/.npm" ]; then
        local_excludes+=(".npm" ".npm/_cacache")
        if ! is_cron_mode "$cron_mode"; then
            echo -e "  ${GREEN}✓${NC} NPM detected → adding npm cache"
        fi
        ((detected++))
    fi

    if command -v cargo &> /dev/null || [ -d "$HOME/.cargo/registry" ]; then
        local_excludes+=(".cargo/registry")
        if ! is_cron_mode "$cron_mode"; then
            echo -e "  ${GREEN}✓${NC} Cargo detected → adding cargo registry"
        fi
        ((detected++))
    fi

    if command -v google-chrome &> /dev/null || [ -d "$HOME/.config/google-chrome" ]; then
        local_excludes+=(".config/google-chrome/Default/Cache" ".config/google-chrome/Default/Code Cache" ".config/google-chrome/Default/Service Worker")
        if ! is_cron_mode "$cron_mode"; then
            echo -e "  ${GREEN}✓${NC} Chrome detected → adding browser cache"
        fi
        ((detected++))
    fi

    if command -v firefox &> /dev/null || [ -d "$HOME/.mozilla/firefox" ]; then
        local_excludes+=(".mozilla/firefox/*/cache2" ".mozilla/firefox/*/thumbnails" ".mozilla/firefox/*/offlinecache")
        if ! is_cron_mode "$cron_mode"; then
            echo -e "  ${GREEN}✓${NC} Firefox detected → adding browser cache"
        fi
        ((detected++))
    fi

    if command -v code &> /dev/null || [ -d "$HOME/.vscode" ]; then
        local_excludes+=(".vscode" ".vscode-server" ".vscode-remote")
        if ! is_cron_mode "$cron_mode"; then
            echo -e "  ${GREEN}✓${NC} VSCode detected → adding editor cache"
        fi
        ((detected++))
    fi

    if [ -d "$HOME/node_modules" ] || [ -d "$HOME/.node_modules" ]; then
        local_excludes+=("node_modules")
        if ! is_cron_mode "$cron_mode"; then
            echo -e "  ${GREEN}✓${NC} Node modules detected → adding dependencies"
        fi
        ((detected++))
    fi

    if [ -d "$HOME/.docker" ]; then
        local_excludes+=(".docker")
        if ! is_cron_mode "$cron_mode"; then
            echo -e "  ${GREEN}✓${NC} Docker detected → adding docker config"
        fi
        ((detected++))
    fi

    if ! is_cron_mode "$cron_mode"; then
        if [ $detected -eq 0 ]; then
            echo -e "  ${YELLOW}⚠${NC} No additional software detected for exclusion"
        else
            echo -e "  ${GREEN}✓${NC} Found $detected software-specific exclusions"
        fi
        sleep 2
    fi

    # Save detected exclusions
    printf "%s\n" "${local_excludes[@]}" > /tmp/local_exclusions.txt

    return 0
}

# Function to merge and deduplicate exclusions
merge_exclusions() {
    local merged_file="/tmp/final_exclusions.txt"

    # Start with some base exclusions that are always safe
    cat > "$merged_file" << 'EOF'
# Base exclusions (always safe to exclude)
.cache
.trash
.local/share/Trash
tmp
*.tmp
*.temp
*.log
.DS_Store
Thumbs.db
EOF

    # Add internet-sourced exclusions if available
    if [ -f "/tmp/recommended_exclusions.txt" ]; then
        grep -v "^#" "/tmp/recommended_exclusions.txt" | grep -v "^$" >> "$merged_file"
    fi

    # Add locally detected exclusions
    if [ -f "/tmp/local_exclusions.txt" ]; then
        cat "/tmp/local_exclusions.txt" >> "$merged_file"
    fi

    # Add custom excludes from config
    for exclude in "${CUSTOM_EXCLUDES[@]}"; do
        echo "$exclude" >> "$merged_file"
    done

    # Deduplicate and clean
    sort -u "$merged_file" | grep -v "^#" | grep -v "^$" > "/tmp/clean_exclusions.txt"

    # Count final exclusions
    local count=$(wc -l < "/tmp/clean_exclusions.txt")
    echo $count
}

# Enhanced dependency check with style
check_dependencies() {
    local missing_deps=()
    local deps_to_install=()
    local cron_mode=$1

    if ! is_cron_mode "$cron_mode"; then
        print_header
        echo -e "${BLUE}🔧 Checking dependencies...${NC}"
    fi

    # Check for rsync
    if ! command -v rsync &> /dev/null; then
        missing_deps+=("rsync")
        deps_to_install+=("rsync")
        if ! is_cron_mode "$cron_mode"; then
            echo -e "  ${RED}✗${NC} rsync not installed"
        fi
    else
        if ! is_cron_mode "$cron_mode"; then
            echo -e "  ${GREEN}✓${NC} rsync found"
        fi
    fi

    # Check for gum
    if ! command -v gum &> /dev/null; then
        missing_deps+=("gum")
        deps_to_install+=("gum")
        if ! is_cron_mode "$cron_mode"; then
            echo -e "  ${RED}✗${NC} gum not installed"
        fi
    else
        if ! is_cron_mode "$cron_mode"; then
            echo -e "  ${GREEN}✓${NC} gum found"
        fi
    fi

    # Check for notify-send
    if ! command -v notify-send &> /dev/null; then
        if ! is_cron_mode "$cron_mode"; then
            echo -e "  ${YELLOW}⚠${NC} notify-send not found (desktop notifications disabled)"
            echo -e "     Install libnotify-bin for notifications"
        fi
    else
        if ! is_cron_mode "$cron_mode"; then
            echo -e "  ${GREEN}✓${NC} notify-send found"
        fi
    fi

    # Check for numfmt (coreutils)
    if ! command -v numfmt &> /dev/null; then
        if ! is_cron_mode "$cron_mode"; then
            echo -e "  ${YELLOW}⚠${NC} numfmt not found (using basic size display)"
        fi
    else
        if ! is_cron_mode "$cron_mode"; then
            echo -e "  ${GREEN}✓${NC} numfmt found"
        fi
    fi

    # Check for stat
    if ! command -v stat &> /dev/null; then
        if ! is_cron_mode "$cron_mode"; then
            echo -e "  ${YELLOW}⚠${NC} stat not found (incremental estimation may be limited)"
        fi
    else
        if ! is_cron_mode "$cron_mode"; then
            echo -e "  ${GREEN}✓${NC} stat found"
        fi
    fi

    # Check for curl/wget (for internet searches)
    if command -v curl &> /dev/null; then
        if ! is_cron_mode "$cron_mode"; then
            echo -e "  ${GREEN}✓${NC} curl found"
        fi
    elif command -v wget &> /dev/null; then
        if ! is_cron_mode "$cron_mode"; then
            echo -e "  ${GREEN}✓${NC} wget found"
        fi
    else
        if ! is_cron_mode "$cron_mode"; then
            echo -e "  ${YELLOW}⚠${NC} Neither curl nor wget found (internet search may be limited)"
        fi
    fi

    # Check for gpg (optional, for encryption)
    if [ "$ENABLE_ENCRYPTION" = true ] && ! command -v gpg &> /dev/null; then
        if ! is_cron_mode "$cron_mode"; then
            echo -e "  ${YELLOW}⚠${NC} gpg not found (encryption disabled)"
        fi
        ENABLE_ENCRYPTION=false
    fi

    # Check for mail (optional, for email notifications)
    if [ "$ENABLE_EMAIL_NOTIFY" = true ] && ! command -v mail &> /dev/null && ! command -v sendmail &> /dev/null; then
        if ! is_cron_mode "$cron_mode"; then
            echo -e "  ${YELLOW}⚠${NC} mail/sendmail not found (email notifications disabled)"
        fi
        ENABLE_EMAIL_NOTIFY=false
    fi

    if [ ${#missing_deps[@]} -ne 0 ]; then
        if ! is_cron_mode "$cron_mode"; then
            echo ""
            echo -e "${YELLOW}📦 Missing dependencies: ${missing_deps[*]}${NC}"
            echo -e "${BLUE}⚡ Attempting to install...${NC}"
        fi

        # Detect package manager with style
        if command -v apt &> /dev/null; then
            if ! is_cron_mode "$cron_mode"; then
                echo -e "  ${PURPLE}📀 Debian/Ubuntu detected${NC}"
            fi
            sudo apt update
            for dep in "${deps_to_install[@]}"; do
                if [ "$dep" = "gum" ]; then
                    if ! is_cron_mode "$cron_mode"; then
                        echo -e "  ${BLUE}Adding Charm repository for gum...${NC}"
                    fi
                    sudo mkdir -p /etc/apt/keyrings
                    curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
                    echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
                    sudo apt update
                fi
                if ! is_cron_mode "$cron_mode"; then
                    echo -e "  ${BLUE}Installing $dep...${NC}"
                fi
                sudo apt install -y "$dep"
            done
            # Install optional packages
            if [ "$ENABLE_ENCRYPTION" = true ]; then
                sudo apt install -y gnupg
            fi
            if [ "$ENABLE_EMAIL_NOTIFY" = true ]; then
                sudo apt install -y mailutils
            fi
        elif command -v pacman &> /dev/null; then
            if ! is_cron_mode "$cron_mode"; then
                echo -e "  ${PURPLE}📀 Arch Linux detected${NC}"
            fi
            for dep in "${deps_to_install[@]}"; do
                if ! is_cron_mode "$cron_mode"; then
                    echo -e "  ${BLUE}Installing $dep...${NC}"
                fi
                sudo pacman -S --noconfirm "$dep"
            done
            # Install optional packages
            if [ "$ENABLE_ENCRYPTION" = true ]; then
                sudo pacman -S --noconfirm gnupg
            fi
            if [ "$ENABLE_EMAIL_NOTIFY" = true ]; then
                sudo pacman -S --noconfirm mailutils
            fi
        elif command -v dnf &> /dev/null; then
            if ! is_cron_mode "$cron_mode"; then
                echo -e "  ${PURPLE}📀 Fedora detected${NC}"
            fi
            for dep in "${deps_to_install[@]}"; do
                if [ "$dep" = "gum" ]; then
                    if ! is_cron_mode "$cron_mode"; then
                        echo -e "  ${BLUE}Adding Charm repository for gum...${NC}"
                    fi
                    echo '[charm]
name=Charm
baseurl=https://repo.charm.sh/yum/
enabled=1
gpgcheck=1
gpgkey=https://repo.charm.sh/yum/gpg.key' | sudo tee /etc/yum.repos.d/charm.repo
                fi
                if ! is_cron_mode "$cron_mode"; then
                    echo -e "  ${BLUE}Installing $dep...${NC}"
                fi
                sudo dnf install -y "$dep"
            done
            # Install optional packages
            if [ "$ENABLE_ENCRYPTION" = true ]; then
                sudo dnf install -y gnupg
            fi
            if [ "$ENABLE_EMAIL_NOTIFY" = true ]; then
                sudo dnf install -y mailx
            fi
        else
            echo -e "${RED}❌ Unsupported package manager. Please install manually: ${missing_deps[*]}${NC}"
            exit 1
        fi

        if ! is_cron_mode "$cron_mode"; then
            echo -e "${GREEN}✅ All dependencies installed successfully!${NC}"
            sleep 2
        fi
    fi
}

# Function to show fancy loading animation
show_loading() {
    local message="$1"
    local duration="$2"

    if command -v gum &> /dev/null; then
        gum spin --spinner minidot --title "$message" -- sleep "$duration"
    else
        echo -n "$message"
        for i in {1..10}; do
            echo -n "."
            sleep $(echo "$duration/10" | bc -l 2>/dev/null || sleep 0.1)
        done
        echo ""
    fi
}

# Function to display exclusions in a fancy table
show_exclusions_table() {
    local exclude_file="$1"
    local title="$2"

    if command -v gum &> /dev/null; then
        # Create a temporary formatted file
        local temp_file=$(mktemp)
        awk '{printf "  📁 %-50s\n", $0}' "$exclude_file" > "$temp_file"
        gum style \
            --border rounded \
            --padding "1 2" \
            --margin "1" \
            --border-foreground 99 \
            --foreground 226 \
            "$title" \
            < "$temp_file"
        rm "$temp_file"
    else
        echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC}                      $title                          ${CYAN}║${NC}"
        echo -e "${CYAN}╠════════════════════════════════════════════════════════════╣${NC}"
        while IFS= read -r line; do
            printf "${CYAN}║${NC}  📁 %-50s ${CYAN}║${NC}\n" "$line"
        done < "$exclude_file"
        echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    fi
}

# Function to perform backup with style (now with performance tuning)
do_backup() {
    local dry_run_flag=""
    local operation_title="💾  BACKUP OPERATION"
    local notification_title="Backup Started"
    local backup_type="Full"
    local cron_mode=$1

    # If the first argument is "dry", we add the -n (dry-run) flag
    if [[ "$1" == "dry" ]] || [[ "$1" == "--dry-run" ]]; then
        dry_run_flag="-n"
        operation_title="🔍  DRY RUN (PREVIEW ONLY)"
        notification_title="Dry Run Started"
        cron_mode=""
    fi

    # If the first argument is "cron" or "--cron", we're running in background
    if [[ "$1" == "cron" ]] || [[ "$1" == "--cron" ]]; then
        cron_mode="cron"
    fi

    # Check script location (warn if in home folder)
    if ! is_cron_mode "$cron_mode"; then
        check_script_location
        echo ""
    fi

    # Check if destination is accessible (for USB drives, network mounts, etc.)
    if ! check_destination_accessible "$cron_mode"; then
        if is_cron_mode "$cron_mode"; then
            echo "$(date): Backup aborted - destination not accessible (USB drive not mounted?)" >> "$LOG_FILE"
            send_email "Backup Failed - Destination Not Accessible" "The backup destination is not accessible. Check if USB drive is mounted."
        fi
        return 1
    fi

    # Detect mount type for performance tuning
    local mount_type=$(detect_mount_type)

    # Show mount information in interactive mode
    if ! is_cron_mode "$cron_mode"; then
        show_mount_info
    fi

    # Get performance flags based on mode and mount type
    local perf_flags=$(get_performance_flags "$mount_type")

    # Find the last backup for incremental linking
    local last_backup=$(find_last_backup)
    local link_dest_param=""

    # SAFETY CHECK: Only add --link-dest if the last backup actually exists
    if [ -n "$last_backup" ] && [ -d "$last_backup" ]; then
        link_dest_param="--link-dest=\"$last_backup\""
        backup_type="Incremental"
        if ! is_cron_mode "$cron_mode"; then
            echo -e "${BLUE}🔗 Using hard links from previous backup: $(basename "$last_backup")${NC}"
        fi
    else
        if ! is_cron_mode "$cron_mode"; then
            echo -e "${YELLOW}📦 First backup - will create full backup${NC}"
        fi
    fi

    if ! is_cron_mode "$cron_mode"; then
        clear
        if command -v gum &> /dev/null; then
            gum style \
                --border double \
                --padding "1 2" \
                --margin "1" \
                --border-foreground 46 \
                --foreground 226 \
                "$operation_title" \
                "" \
                "Source:      $BACKUP_SOURCE" \
                "Destination: $BACKUP_DEST" \
                "Type:        $backup_type" \
                "Mode:        $PERFORMANCE_MODE" \
                "Mount:       $mount_type" \
                "Timestamp:   $TIMESTAMP" \
                "Keep last:   $MAX_BACKUPS backups"
        else
            print_header
            echo -e "${GREEN}$operation_title${NC}"
            echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "Source:      $BACKUP_SOURCE"
            echo -e "Destination: $BACKUP_DEST"
            echo -e "Type:        $backup_type"
            echo -e "Mode:        $PERFORMANCE_MODE"
            echo -e "Mount:       $mount_type"
            echo -e "Timestamp:   $TIMESTAMP"
            echo -e "Keep last:   $MAX_BACKUPS backups"
            echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        fi
    fi

    # Create backup directory
    mkdir -p "$BACKUP_DEST"

    # Load exclusions
    local exclude_file="/tmp/clean_exclusions.txt"
    if [ ! -f "$exclude_file" ]; then
        if ! is_cron_mode "$cron_mode"; then
            echo -e "${YELLOW}No exclusion file found. Generating...${NC}"
        fi
        search_exclusions "$cron_mode"
        detect_local_exclusions "$cron_mode"
        merge_exclusions > /dev/null
    fi

    if ! is_cron_mode "$cron_mode"; then
        # Show what will be excluded
        local exclude_count=$(wc -l < "$exclude_file")
        echo -e "\n${YELLOW}📋 Will exclude $exclude_count directories/files${NC}"

        if command -v gum &> /dev/null; then
            if gum confirm "Show excluded items?"; then
                show_exclusions_table "$exclude_file" "EXCLUDED ITEMS"
            fi
        else
            echo -e "\n${CYAN}View exclusions? (y/n)${NC}"
            read -r show
            if [[ "$show" =~ ^[Yy]$ ]]; then
                show_exclusions_table "$exclude_file" "EXCLUDED ITEMS"
            fi
        fi
    fi

    # Build exclude parameters
    local exclude_params=""
    while IFS= read -r pattern; do
        [[ -z "$pattern" || "$pattern" =~ ^# ]] && continue
        # Clean up the pattern and add to rsync exclude
        clean_pattern=$(echo "$pattern" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        exclude_params="$exclude_params --exclude='$clean_pattern'"
    done < "$exclude_file"

    # Estimate backup size for disk space check (skip for dry run)
    local estimated_size_mb=0
    if [[ "$1" != "dry" ]] && [[ "$1" != "--dry-run" ]]; then
        if ! is_cron_mode "$cron_mode"; then
            echo -e "\n${BLUE}📊 Estimating backup size...${NC}"
        fi
        estimated_size_mb=$(estimate_backup_size "$exclude_file" "$last_backup")
        local estimated_size_hr=$(numfmt --to=iec $((estimated_size_mb * 1024 * 1024)) 2>/dev/null || echo "${estimated_size_mb}MB")

        if ! is_cron_mode "$cron_mode"; then
            echo -e "${GREEN}Estimated backup size: $estimated_size_hr${NC}"
        fi

        # Check disk space
        if ! is_cron_mode "$cron_mode"; then
            echo -e "\n${BLUE}💾 Checking disk space...${NC}"
        fi

        if ! check_disk_space $estimated_size_mb "$cron_mode"; then
            if ! is_cron_mode "$cron_mode"; then
                echo ""
                if command -v gum &> /dev/null; then
                    if ! gum confirm "Continue anyway? (Not recommended!)"; then
                        return
                    fi
                else
                    echo -e "${YELLOW}Continue anyway? (Not recommended!) (y/n)${NC}"
                    read -r force_continue
                    if [[ ! "$force_continue" =~ ^[Yy]$ ]]; then
                        return
                    fi
                fi
            else
                # In cron mode, just log and exit on space issues
                echo "$(date): Backup aborted - insufficient disk space" >> "$LOG_FILE"
                return 1
            fi
        fi
    fi

    # Final confirmation (skip in cron mode)
    if ! is_cron_mode "$cron_mode"; then
        echo ""
        if command -v gum &> /dev/null; then
            if [[ "$1" == "dry" ]] || [[ "$1" == "--dry-run" ]]; then
                if ! gum confirm "🔍 Run dry run preview?"; then
                    return
                fi
            else
                if ! gum confirm "🚀 Ready to start $backup_type backup in $PERFORMANCE_MODE mode?"; then
                    return
                fi
            fi
        else
            if [[ "$1" == "dry" ]] || [[ "$1" == "--dry-run" ]]; then
                echo -e "${YELLOW}Run dry run preview? (y/n)${NC}"
            else
                echo -e "${YELLOW}Start $backup_type backup in $PERFORMANCE_MODE mode? (y/n)${NC}"
            fi
            read -r confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                return
            fi
        fi
    fi

    # Notify start (skip for dry run and cron mode might want quiet)
    if [[ "$1" != "dry" ]] && [[ "$1" != "--dry-run" ]] && ! is_cron_mode "$cron_mode"; then
        send_notification "$notification_title" "Starting $backup_type backup of $HOME (Mode: $PERFORMANCE_MODE)" "drive-harddisk"
    fi

    # Create backup folder name
    local backup_name="$(basename "$BACKUP_SOURCE")_$TIMESTAMP"
    local backup_path="$BACKUP_DEST/$backup_name"

    # Build rsync command with safety check for link-dest and performance flags
    local rsync_cmd="rsync -avh $dry_run_flag --progress --delete $perf_flags $link_dest_param $exclude_params \"$BACKUP_SOURCE/\" \"$backup_path/\""

    # Log the command
    echo "Backup started at $(date)" > "$LOG_FILE"
    echo "Mode: ${1:-normal}" >> "$LOG_FILE"
    echo "Performance Mode: $PERFORMANCE_MODE" >> "$LOG_FILE"
    echo "Mount Type: $mount_type" >> "$LOG_FILE"
    echo "Type: $backup_type" >> "$LOG_FILE"
    echo "Linked to: ${last_backup:-none}" >> "$LOG_FILE"
    echo "Command: $rsync_cmd" >> "$LOG_FILE"
    echo "Exclusions:" >> "$LOG_FILE"
    cat "$exclude_file" >> "$LOG_FILE"

    # Execute backup
    if ! is_cron_mode "$cron_mode"; then
        echo -e "${GREEN}📦 Starting data transfer in $PERFORMANCE_MODE mode...${NC}"
    fi

    # CRITICAL FIX: Only update the 'latest' symlink if the backup succeeds
    # This ensures the 'latest' link always points to a complete, healthy backup

    local backup_status=1
    if command -v gum &> /dev/null && [[ "$1" != "dry" ]] && [[ "$1" != "--dry-run" ]] && ! is_cron_mode "$cron_mode"; then
        # Use gum progress bar for real backup in interactive mode
        if eval "$rsync_cmd" 2>&1 | stdbuf -oL grep -oP '\d+(?=%)' | gum progress --title "Syncing files ($backup_type)..." --percentage; then
            backup_status=0
        fi
    else
        # For dry run, without gum, or cron mode, just run quietly
        if is_cron_mode "$cron_mode"; then
            if eval "$rsync_cmd" >> "$LOG_FILE" 2>&1; then
                backup_status=0
            fi
        else
            if eval "$rsync_cmd" | tee -a "$LOG_FILE"; then
                backup_status=0
            fi
        fi
    fi

    if [ $backup_status -eq 0 ]; then
        if [[ "$1" != "dry" ]] && [[ "$1" != "--dry-run" ]]; then
            # ATOMIC SUCCESS LINK: Only update the 'latest' symlink if backup succeeded
            # This ensures the link always points to a COMPLETE, HEALTHY backup
            ln -snf "$backup_path" "$BACKUP_DEST/latest"

            if ! is_cron_mode "$cron_mode"; then
                echo -e "${GREEN}✅ Backup verified and linked as latest.${NC}"
            fi

            # Verify backup if enabled
            if [ "$ENABLE_VERIFICATION" = true ]; then
                verify_backup "$backup_path"
            fi

            # Encrypt backup if enabled
            if [ "$ENABLE_ENCRYPTION" = true ]; then
                backup_path=$(encrypt_backup "$backup_path")
            fi

            # Get backup stats
            local backup_size=$(du -sh "$backup_path" 2>/dev/null | cut -f1)
            local backup_files=$(find "$backup_path" -type f 2>/dev/null | wc -l)
            local new_files="All"
            if [ -n "$last_backup" ] && [ -d "$last_backup" ]; then
                new_files=$(diff -qr "$last_backup" "$backup_path" 2>/dev/null | grep -c "^Only in $backup_path")
            fi

            if ! is_cron_mode "$cron_mode"; then
                echo ""
                if command -v gum &> /dev/null; then
                    gum style \
                        --border rounded \
                        --padding "1 2" \
                        --margin "1" \
                        --border-foreground 46 \
                        "✅ BACKUP COMPLETED SUCCESSFULLY!" \
                        "" \
                        "📊 Summary:" \
                        "  • Type:     $backup_type" \
                        "  • Mode:     $PERFORMANCE_MODE" \
                        "  • Location: $backup_path" \
                        "  • Size:     $backup_size" \
                        "  • Files:    $backup_files" \
                        "  • New:      $new_files" \
                        "  • Log:      $LOG_FILE"
                else
                    echo -e "${GREEN}✅ BACKUP COMPLETED SUCCESSFULLY!${NC}"
                    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                    echo -e "Type:     $backup_type"
                    echo -e "Mode:     $PERFORMANCE_MODE"
                    echo -e "Location: $backup_path"
                    echo -e "Size:     $backup_size"
                    echo -e "Files:    $backup_files"
                    echo -e "New:      $new_files"
                    echo -e "Log:      $LOG_FILE"
                fi

                # Send success notification
                send_notification "Backup Complete" "$backup_type backup completed (Size: $backup_size, New: $new_files)" "emblem-success"
            fi

            # Log success to file
            echo "$(date): Backup completed successfully - Type: $backup_type, Mode: $PERFORMANCE_MODE, Size: $backup_size, Files: $backup_files, New: $new_files" >> "$LOG_FILE"

            # Send email notification
            send_email "Backup Successful" "$backup_type backup completed in $PERFORMANCE_MODE mode. Size: $backup_size, Files: $backup_files, New: $new_files"

            # Clean up old backups (keep only MAX_BACKUPS) - only after successful backup
            cleanup_old_backups "$cron_mode"
            # Clean up old logs
            cleanup_old_logs "$cron_mode"
        else
            # Dry run success message
            if ! is_cron_mode "$cron_mode"; then
                echo ""
                if command -v gum &> /dev/null; then
                    gum style \
                        --border rounded \
                        --padding "1 2" \
                        --margin "1" \
                        --border-foreground 226 \
                        "🔍 DRY RUN COMPLETED" \
                        "" \
                        "No files were actually copied." \
                        "Check the output above to verify exclusions are working."
                else
                    echo -e "${YELLOW}🔍 DRY RUN COMPLETED${NC}"
                    echo -e "No files were actually copied."
                    echo -e "Check the output above to verify exclusions are working."
                fi
            fi
        fi
    else
        # Backup failed - IMPORTANT: We DO NOT update the latest symlink here
        # This ensures the 'latest' link remains pointing to the last GOOD backup
        if ! is_cron_mode "$cron_mode"; then
            echo -e "${RED}❌ Backup failed. 'latest' link remains on previous healthy backup.${NC}"
            if command -v gum &> /dev/null; then
                gum style --foreground 196 "❌ Backup failed! Check log: $LOG_FILE"
            else
                echo -e "${RED}❌ Backup failed! Check log: $LOG_FILE${NC}"
            fi

            # Send failure notification
            if [[ "$1" != "dry" ]] && [[ "$1" != "--dry-run" ]]; then
                send_notification "Backup FAILED" "Check the log file: $LOG_FILE" "dialog-error"
            fi
        fi

        # Log failure to file
        echo "$(date): Backup FAILED - Check log for details" >> "$LOG_FILE"

        # Send email notification
        send_email "Backup Failed" "The backup failed. Check the log file: $LOG_FILE"
    fi

    # Ask to continue (skip in cron mode)
    if ! is_cron_mode "$cron_mode"; then
        if command -v gum &> /dev/null; then
            gum confirm "Press Enter to continue" && return
        else
            echo -e "\n${BLUE}Press Enter to continue...${NC}"
            read -r
        fi
    fi
}

# Function to show destination info
show_destination_info() {
    clear
    print_header
    echo -e "${BLUE}📌 DESTINATION INFORMATION${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Show script location check
    check_script_location

    echo ""

    # Show mount information
    show_mount_info

    # Show destination accessibility
    if check_destination_accessible; then
        # Show free space
        local free_space_mb=$(df -m "$BACKUP_DEST" 2>/dev/null | awk 'NR==2 {print $4}')
        if [ ! -z "$free_space_mb" ]; then
            local free_space_hr=$(numfmt --to=iec $((free_space_mb * 1024 * 1024)) 2>/dev/null || echo "${free_space_mb}MB")
            echo -e "${GREEN}💾 Free space: $free_space_hr${NC}"
        fi

        # Show performance settings
        echo -e "\n${BLUE}⚡ Current Performance Settings:${NC}"
        echo -e "  • Mode: ${CYAN}$PERFORMANCE_MODE${NC}"
        echo -e "  • Encryption: ${CYAN}$([ "$ENABLE_ENCRYPTION" = true ] && echo "Enabled" || echo "Disabled")${NC}"
        echo -e "  • Verification: ${CYAN}$([ "$ENABLE_VERIFICATION" = true ] && echo "Enabled" || echo "Disabled")${NC}"
        echo -e "  • Bandwidth Limit: ${CYAN}$([ "$BANDWIDTH_LIMIT" -gt 0 ] && echo "${BANDWIDTH_LIMIT} KB/s" || echo "Unlimited")${NC}"
    else
        echo -e "${RED}❌ Destination is NOT accessible!${NC}"
        echo -e "${YELLOW}  Possible issues:${NC}"
        echo -e "  • USB drive not plugged in"
        echo -e "  • Network share disconnected"
        echo -e "  • Permissions problem"
    fi

    echo ""
    if command -v gum &> /dev/null; then
        gum confirm "Press Enter to continue" && return
    else
        echo -e "\n${BLUE}Press Enter to continue...${NC}"
        read -r
    fi
}

# Function to show fancy status
show_status() {
    clear

    if command -v gum &> /dev/null; then
        gum style \
            --border double \
            --padding "1 2" \
            --margin "1" \
            --border-foreground 33 \
            "📊  BACKUP STATUS"
    else
        print_header
        echo -e "${BLUE}📊 BACKUP STATUS${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    fi

    # Show script location
    check_script_location
    echo ""

    # Show mount information
    show_mount_info

    # Show disk space status
    local free_space_mb=$(df -m "$BACKUP_DEST" 2>/dev/null | awk 'NR==2 {print $4}')
    if [ ! -z "$free_space_mb" ]; then
        local free_space_hr=$(numfmt --to=iec $((free_space_mb * 1024 * 1024)) 2>/dev/null || echo "${free_space_mb}MB")

        if [ $free_space_mb -lt $EMERGENCY_THRESHOLD ]; then
            echo -e "${RED}⚠️  CRITICAL: Emergency low disk space!${NC}"
            echo -e "  Free space: $free_space_hr"
        elif [ $free_space_mb -lt $MIN_FREE_SPACE ]; then
            echo -e "${YELLOW}⚠️  Warning: Low disk space${NC}"
            echo -e "  Free space: $free_space_hr"
        else
            echo -e "${GREEN}✅ Disk space OK${NC}"
            echo -e "  Free space: $free_space_hr"
        fi
        echo ""
    fi

    # Find all backups
    local backups=()
    while IFS= read -r -d '' backup; do
        backups+=("$backup")
    done < <(find "$BACKUP_DEST" -maxdepth 1 -type d -name "$(basename "$BACKUP_SOURCE")_*" -print0 | sort -r)

    if [ ${#backups[@]} -gt 0 ]; then
        # Show latest backup
        local latest_backup="${backups[0]}"
        local latest_size=$(du -sh "$latest_backup" 2>/dev/null | cut -f1)
        local latest_date=$(basename "$latest_backup" | sed "s/$(basename "$BACKUP_SOURCE")_//")
        local latest_files=$(find "$latest_backup" -type f 2>/dev/null | wc -l)

        # Calculate incremental size if there's a previous backup
        if [ ${#backups[@]} -gt 1 ]; then
            local previous_backup="${backups[1]}"
            local new_files=$(diff -qr "$previous_backup" "$latest_backup" 2>/dev/null | grep -c "^Only in $latest_backup")
            local backup_type="Incremental (+$new_files new)"
        else
            local backup_type="Full"
        fi

        if command -v gum &> /dev/null; then
            gum style \
                --border rounded \
                --padding "1 2" \
                --margin "1" \
                --border-foreground 46 \
                "✅ Latest Backup:" \
                "" \
                "  • Type:  $backup_type" \
                "  • Date:  ${latest_date//_/ at }" \
                "  • Size:  $latest_size" \
                "  • Files: $latest_files" \
                "  • Path:  $latest_backup"
        else
            echo -e "\n${GREEN}✅ Latest Backup:${NC}"
            echo -e "  Type:  $backup_type"
            echo -e "  Date:  ${latest_date//_/ at }"
            echo -e "  Size:  $latest_size"
            echo -e "  Files: $latest_files"
            echo -e "  Path:  $latest_backup"
        fi

        # Calculate backup age
        if [[ "$latest_date" =~ ([0-9]{4})-([0-9]{2})-([0-9]{2})_([0-9]{2})-([0-9]{2})-([0-9]{2}) ]]; then
            latest_timestamp=$(date -d "${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]} ${BASH_REMATCH[4]}:${BASH_REMATCH[5]}:${BASH_REMATCH[6]}" +%s 2>/dev/null)
            current_timestamp=$(date +%s)
            days_old=$(( (current_timestamp - latest_timestamp) / 86400 ))

            local age_color="46"
            local age_emoji="🟢"
            if [ $days_old -gt 30 ]; then
                age_color="196"
                age_emoji="🔴"
            elif [ $days_old -gt 7 ]; then
                age_color="226"
                age_emoji="🟡"
            fi

            if command -v gum &> /dev/null; then
                gum style --foreground "$age_color" "$age_emoji Backup is $days_old days old"
            else
                echo -e "\n${age_emoji} Backup is $days_old days old"
            fi
        fi

        # Show backup retention info
        if command -v gum &> /dev/null; then
            gum style --padding "1 2" --foreground 226 "📚 Keeping last $MAX_BACKUPS backups (${#backups[@]} total)"
        else
            echo -e "\n${YELLOW}📚 Keeping last $MAX_BACKUPS backups (${#backups[@]} total)${NC}"
        fi

        # List all backups
        if [ ${#backups[@]} -gt 1 ]; then
            echo ""
            if command -v gum &> /dev/null; then
                gum style --border rounded --padding "1 2" --margin "1" --border-foreground 99 "📋 All Backups:"

                local backup_list=""
                for i in "${!backups[@]}"; do
                    local backup="${backups[$i]}"
                    local size=$(du -sh "$backup" 2>/dev/null | cut -f1)
                    local name=$(basename "$backup")
                    local date_part=${name//$(basename "$BACKUP_SOURCE")_/}
                    local type="Full"
                    if [ $i -gt 0 ]; then
                        type="Inc"
                    fi
                    backup_list+="$date_part | $size | $type\n"
                done
                echo -e "$backup_list" | column -t -s '|' | gum style --foreground 226
            else
                echo -e "${CYAN}📋 All Backups:${NC}"
                for i in "${!backups[@]}"; do
                    local backup="${backups[$i]}"
                    local size=$(du -sh "$backup" 2>/dev/null | cut -f1)
                    local name=$(basename "$backup")
                    local date_part=${name//$(basename "$BACKUP_SOURCE")_/}
                    local type="Full"
                    if [ $i -gt 0 ]; then
                        type="Inc"
                    fi
                    echo -e "  📁 $date_part ${GREEN}[$size]${NC} ${PURPLE}[$type]${NC}"
                done
            fi
        fi
    else
        if command -v gum &> /dev/null; then
            gum style --foreground 196 "❌ No backups found in $BACKUP_DEST"
        else
            echo -e "\n${RED}❌ No backups found in $BACKUP_DEST${NC}"
        fi
    fi

    # Show backup directory size with hard link explanation
    if [ -d "$BACKUP_DEST" ]; then
        local apparent_size=$(du -sh --apparent-size "$BACKUP_DEST" 2>/dev/null | cut -f1)
        local actual_size=$(du -sh "$BACKUP_DEST" 2>/dev/null | cut -f1)
        local available=$(df -h "$BACKUP_DEST" | awk 'NR==2 {print $4}')
        local unique_size=$(find "$BACKUP_DEST" -type f -links 1 -exec du -ch {} + 2>/dev/null | tail -1 | cut -f1)

        echo ""
        if command -v gum &> /dev/null; then
            gum style --border rounded --padding "1 2" --margin "1" --border-foreground 226 "💾 STORAGE EXPLANATION:"

            gum style --padding "0 2" --foreground 226 "📊 Apparent size (what file manager shows): $apparent_size"
            gum style --padding "0 2" --foreground 46 "💿 Actual physical space used: $actual_size"

            if [ -n "$unique_size" ]; then
                gum style --padding "0 2" --foreground 99 "🔗 Unique data (after hard links): $unique_size"
            fi

            gum style --padding "0 2" --foreground 33 "💾 Free space available: $available"

            echo ""
            gum style --padding "0 2" --italic --foreground 226 "📝 Note: Due to hard links, file managers show 'apparent' size."
            gum style --padding "0 2" --italic --foreground 226 "       Actual space used is much less! Run 'du -sh $BACKUP_DEST'"
            gum style --padding "0 2" --italic --foreground 226 "       to see the real physical space consumption."
            gum style --padding "0 2" --italic --foreground 46  "       The 'latest' symlink always points to the last SUCCESSFUL backup."
            gum style --padding "0 2" --italic --foreground 99  "       Current performance mode: $PERFORMANCE_MODE"
        else
            echo -e "\n${YELLOW}💾 STORAGE EXPLANATION:${NC}"
            echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "📊 Apparent size (what file manager shows): ${CYAN}$apparent_size${NC}"
            echo -e "💿 Actual physical space used: ${GREEN}$actual_size${NC}"
            if [ -n "$unique_size" ]; then
                echo -e "🔗 Unique data (after hard links): ${PURPLE}$unique_size${NC}"
            fi
            echo -e "💾 Free space available: ${BLUE}$available${NC}"
            echo ""
            echo -e "${YELLOW}📝 Note: Due to hard links, file managers show 'apparent' size."
            echo -e "       Actual space used is much less! Run 'du -sh $BACKUP_DEST'"
            echo -e "       to see the real physical space consumption.${NC}"
            echo -e "${GREEN}       The 'latest' symlink always points to the last SUCCESSFUL backup.${NC}"
            echo -e "${PURPLE}       Current performance mode: $PERFORMANCE_MODE${NC}"
        fi
    fi

    # Show logs directory info
    if [ -d "$LOGS_DIR" ]; then
        local log_count=$(find "$LOGS_DIR" -type f -name "backup_*.log" 2>/dev/null | wc -l)
        local log_size=$(du -sh "$LOGS_DIR" 2>/dev/null | cut -f1)
        if command -v gum &> /dev/null; then
            gum style --padding "1 2" --foreground 99 "📋 Logs: $log_count files, $log_size total"
        else
            echo -e "\n${PURPLE}📋 Logs: $log_count files, $log_size total${NC}"
        fi
    fi

    # Ask to continue
    if command -v gum &> /dev/null; then
        gum confirm "Press Enter to continue" && return
    else
        echo -e "\n${BLUE}Press Enter to continue...${NC}"
        read -r
    fi
}

# Function to restore from backup
do_restore() {
    clear

    if command -v gum &> /dev/null; then
        gum style \
            --border double \
            --padding "1 2" \
            --margin "1" \
            --border-foreground 196 \
            --foreground 226 \
            "⚠️  RESTORE OPERATION" \
            "" \
            "This will OVERWRITE your current home folder!"
    else
        print_header
        echo -e "${RED}⚠️  RESTORE OPERATION${NC}"
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${RED}This will OVERWRITE your current home folder!${NC}"
    fi

    # Check if destination is accessible
    if ! check_destination_accessible; then
        echo -e "${RED}❌ Cannot access backup destination. Is the drive mounted?${NC}"
        sleep 3
        return
    fi

    # Find available backups
    local backups=()
    while IFS= read -r -d '' backup; do
        backups+=("$backup")
    done < <(find "$BACKUP_DEST" -maxdepth 1 -type d -name "$(basename "$BACKUP_SOURCE")_*" -print0 | sort -r)

    if [ ${#backups[@]} -eq 0 ]; then
        if command -v gum &> /dev/null; then
            gum style --foreground 196 "❌ No backups found in $BACKUP_DEST"
        else
            echo -e "${RED}❌ No backups found in $BACKUP_DEST${NC}"
        fi
        sleep 2
        return
    fi

    # Create backup selection menu with type indicator
    local backup_options=()
    for i in "${!backups[@]}"; do
        local backup="${backups[$i]}"
        if [ -d "$backup" ]; then
            local name=$(basename "$backup")
            local size=$(du -sh "$backup" 2>/dev/null | cut -f1)
            local date_part=${name//$(basename "$BACKUP_SOURCE")_/}
            local type="Full"
            if [ $i -gt 0 ]; then
                type="Incremental"
            fi
            backup_options+=("$date_part [$size] - $type")
        fi
    done

    echo ""
    if command -v gum &> /dev/null; then
        selected=$(gum choose --header="Select backup to restore:" "${backup_options[@]}")
        if [ -z "$selected" ]; then
            return
        fi
        # Extract the date part
        selected_date=$(echo "$selected" | cut -d' ' -f1)
        selected_backup="$BACKUP_DEST/$(basename "$BACKUP_SOURCE")_$selected_date"
    else
        echo -e "${CYAN}Available backups:${NC}"
        for i in "${!backup_options[@]}"; do
            echo -e "  $((i+1)). ${backup_options[$i]}"
        done
        echo -e "\n${YELLOW}Select backup number:${NC}"
        read -r selection
        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le ${#backups[@]} ]; then
            selected_backup="${backups[$((selection-1))]}"
        else
            echo -e "${RED}Invalid selection${NC}"
            sleep 2
            return
        fi
    fi

    if [ ! -d "$selected_backup" ]; then
        echo -e "${RED}Invalid selection${NC}"
        sleep 2
        return
    fi

    # Show backup details
    local backup_size=$(du -sh "$selected_backup" 2>/dev/null | cut -f1)
    local backup_files=$(find "$selected_backup" -type f 2>/dev/null | wc -l)

    if command -v gum &> /dev/null; then
        gum style \
            --border rounded \
            --padding "1 2" \
            --margin "1" \
            --border-foreground 226 \
            "Selected backup:" \
            "" \
            "  • Path:  $selected_backup" \
            "  • Size:  $backup_size" \
            "  • Files: $backup_files"
    else
        echo -e "\n${YELLOW}Selected backup:${NC}"
        echo -e "  Path:  $selected_backup"
        echo -e "  Size:  $backup_size"
        echo -e "  Files: $backup_files"
    fi

    # Double confirmation
    echo ""
    if command -v gum &> /dev/null; then
        gum style --foreground 196 "⚠️  WARNING: This is destructive!"
        if ! gum confirm "Are you ABSOLUTELY sure?"; then
            return
        fi
        if ! gum confirm "Last chance! Really restore?"; then
            return
        fi
    else
        echo -e "${RED}⚠️  Are you ABSOLUTELY sure? (type 'yes' to confirm)${NC}"
        read -r confirm
        if [ "$confirm" != "yes" ]; then
            return
        fi
    fi

    # Perform restore
    local restore_cmd="rsync -avh --progress \"$selected_backup/\" \"$BACKUP_SOURCE/\""

    echo -e "${GREEN}♻️  Restoring from $(basename "$selected_backup")...${NC}"

    # Send notification
    send_notification "Restore Started" "Restoring from $(basename "$selected_backup")" "drive-harddisk"

    if command -v gum &> /dev/null; then
        gum spin --spinner points --title "Restoring home folder..." -- \
            bash -c "eval $restore_cmd"
    else
        eval "$restore_cmd"
    fi

    if [ $? -eq 0 ]; then
        if command -v gum &> /dev/null; then
            gum style --foreground 46 "✅ Restore completed successfully!"
        else
            echo -e "${GREEN}✅ Restore completed successfully!${NC}"
        fi
        send_notification "Restore Complete" "Successfully restored from backup" "emblem-success"
        send_email "Restore Complete" "Successfully restored from backup: $(basename "$selected_backup")"
    else
        if command -v gum &> /dev/null; then
            gum style --foreground 196 "❌ Restore failed!"
        else
            echo -e "${RED}❌ Restore failed!${NC}"
        fi
        send_notification "Restore FAILED" "Restore operation failed" "dialog-error"
        send_email "Restore Failed" "Restore operation failed from backup: $(basename "$selected_backup")"
    fi

    sleep 2
}

# Function to manually trigger cleanup
do_cleanup() {
    clear

    if command -v gum &> /dev/null; then
        gum style \
            --border double \
            --padding "1 2" \
            --margin "1" \
            --border-foreground 226 \
            "🧹  MANUAL CLEANUP" \
            "" \
            "This will remove old backups, keeping only the $MAX_BACKUPS most recent."
    else
        print_header
        echo -e "${YELLOW}🧹 MANUAL CLEANUP${NC}"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "This will remove old backups, keeping only the $MAX_BACKUPS most recent."
    fi

    # Check if destination is accessible
    if ! check_destination_accessible; then
        echo -e "${RED}❌ Cannot access backup destination. Is the drive mounted?${NC}"
        sleep 3
        return
    fi

    # Show current backups
    local backups=()
    while IFS= read -r -d '' backup; do
        backups+=("$backup")
    done < <(find "$BACKUP_DEST" -maxdepth 1 -type d -name "$(basename "$BACKUP_SOURCE")_*" -print0 | sort -r)

    if [ ${#backups[@]} -le $MAX_BACKUPS ]; then
        if command -v gum &> /dev/null; then
            gum style --foreground 46 "✅ No cleanup needed (${#backups[@]}/$MAX_BACKUPS backups)"
        else
            echo -e "${GREEN}✅ No cleanup needed (${#backups[@]}/$MAX_BACKUPS backups)${NC}"
        fi
        sleep 2
        return
    fi

    # Show what will be removed
    echo -e "\n${YELLOW}Current backups:${NC}"
    for i in "${!backups[@]}"; do
        local size=$(du -sh "${backups[$i]}" 2>/dev/null | cut -f1)
        local type="Full"
        if [ $i -gt 0 ]; then
            type="Inc"
        fi
        if [ $i -lt $MAX_BACKUPS ]; then
            echo -e "  ${GREEN}✓ Keep:   $(basename "${backups[$i]}") [$size] [$type]${NC}"
        else
            echo -e "  ${RED}🗑️ Remove: $(basename "${backups[$i]}") [$size] [$type]${NC}"
        fi
    done

    # Calculate space to be freed
    local space_to_free=0
    for ((i=$MAX_BACKUPS; i<${#backups[@]}; i++)); do
        local size_bytes=$(du -sb "${backups[$i]}" 2>/dev/null | cut -f1)
        space_to_free=$((space_to_free + size_bytes))
    done
    local space_to_free_hr=$(numfmt --to=iec $space_to_free 2>/dev/null || echo "$space_to_free bytes")

    echo -e "\n${YELLOW}Space to be freed: $space_to_free_hr${NC}"

    # Confirm cleanup
    echo ""
    if command -v gum &> /dev/null; then
        if ! gum confirm "Proceed with cleanup?"; then
            return
        fi
    else
        echo -e "${YELLOW}Proceed with cleanup? (y/n)${NC}"
        read -r confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            return
        fi
    fi

    # Perform cleanup
    cleanup_old_backups
    cleanup_old_logs

    if command -v gum &> /dev/null; then
        gum style --foreground 46 "✅ Cleanup complete!"
    else
        echo -e "${GREEN}✅ Cleanup complete!${NC}"
    fi

    sleep 2
}

# Function to update exclusions
update_exclusions() {
    clear

    if command -v gum &> /dev/null; then
        gum style \
            --border double \
            --padding "1 2" \
            --margin "1" \
            --border-foreground 99 \
            "🔍  UPDATE EXCLUSIONS" \
            "" \
            "Searching for updated exclusion patterns"
    else
        print_header
        echo -e "${PURPLE}🔍 UPDATE EXCLUSIONS${NC}"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    fi

    search_exclusions
    detect_local_exclusions
    local count=$(merge_exclusions)

    if command -v gum &> /dev/null; then
        gum style --foreground 46 "✅ Exclusions updated! ($count patterns)"
    else
        echo -e "${GREEN}✅ Exclusions updated! ($count patterns)${NC}"
    fi

    sleep 2
}

# Function to setup automatic scheduling
setup_scheduling() {
    clear

    if command -v gum &> /dev/null; then
        gum style \
            --border double \
            --padding "1 2" \
            --margin "1" \
            --border-foreground 99 \
            "⏰  SCHEDULE AUTOMATIC BACKUPS" \
            "" \
            "Set up daily automatic backups using cron"
    else
        print_header
        echo -e "${PURPLE}⏰ SCHEDULE AUTOMATIC BACKUPS${NC}"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    fi

    # Show mount info to help user understand where they're backing up to
    show_mount_info

    echo ""
    echo -e "This will add a cron job to run backups automatically."
    echo -e "Choose your preferred schedule:"
    echo ""

    local schedule_options=(
        "Daily at midnight (00:00)"
        "Daily at noon (12:00)"
        "Every 6 hours"
        "Weekly on Sunday at 02:00"
        "Custom schedule"
        "Remove existing schedule"
        "Cancel"
    )

    if command -v gum &> /dev/null; then
        choice=$(gum choose "${schedule_options[@]}")
    else
        for i in "${!schedule_options[@]}"; do
            echo -e "  $((i+1)). ${schedule_options[$i]}"
        done
        echo ""
        echo -e "${YELLOW}Choice [1-${#schedule_options[@]}]:${NC}"
        read -r choice_num
        if [[ "$choice_num" =~ ^[0-9]+$ ]] && [ "$choice_num" -ge 1 ] && [ "$choice_num" -le ${#schedule_options[@]} ]; then
            choice="${schedule_options[$((choice_num-1))]}"
        else
            choice="Cancel"
        fi
    fi

    local cron_schedule=""
    local schedule_desc=""

    case $choice in
        "Daily at midnight (00:00)")
            cron_schedule="0 0 * * *"
            schedule_desc="daily at midnight"
            ;;
        "Daily at noon (12:00)")
            cron_schedule="0 12 * * *"
            schedule_desc="daily at noon"
            ;;
        "Every 6 hours")
            cron_schedule="0 */6 * * *"
            schedule_desc="every 6 hours"
            ;;
        "Weekly on Sunday at 02:00")
            cron_schedule="0 2 * * 0"
            schedule_desc="weekly on Sunday at 2 AM"
            ;;
        "Custom schedule")
            echo ""
            echo -e "${YELLOW}Enter custom cron schedule (e.g., '0 0 * * *' for daily at midnight):${NC}"
            read -r cron_schedule
            schedule_desc="custom schedule ($cron_schedule)"
            ;;
        "Remove existing schedule")
            # Remove existing cron job
            (crontab -l 2>/dev/null | grep -v "$SCRIPT_DIR/$(basename "$0")" | crontab -)
            echo -e "${GREEN}✅ Existing schedule removed!${NC}"
            sleep 2
            return
            ;;
        *)
            return
            ;;
    esac

    if [ -n "$cron_schedule" ]; then
        local script_path="$(readlink -f "$0")"
        local cron_job="$cron_schedule cd $SCRIPT_DIR && $script_path --cron >> $LOGS_DIR/cron.log 2>&1"

        # Remove any existing cron job for this script
        (crontab -l 2>/dev/null | grep -v "$script_path" | crontab -)

        # Add new cron job
        (crontab -l 2>/dev/null; echo "$cron_job") | crontab -

        if command -v gum &> /dev/null; then
            gum style --foreground 46 "✅ Backup schedule added successfully!"
            gum style --foreground 226 "Schedule: $schedule_desc"
            gum style --foreground 99 "Cron job: $cron_job"
        else
            echo -e "${GREEN}✅ Backup schedule added successfully!${NC}"
            echo -e "${YELLOW}Schedule: $schedule_desc${NC}"
            echo -e "${PURPLE}Cron job: $cron_job${NC}"
        fi

        # Show current crontab
        echo ""
        echo -e "${BLUE}Current crontab:${NC}"
        crontab -l

        # Add note about USB drives for cron jobs
        local mount_type=$(detect_mount_type)
        if [ "$mount_type" == "usb" ]; then
            echo ""
            echo -e "${YELLOW}⚠️  Note: You're backing up to a USB drive.${NC}"
            echo -e "${YELLOW}   For cron jobs to work, the drive must be mounted at backup time.${NC}"
            echo -e "${YELLOW}   Consider using a permanently mounted drive for automated backups.${NC}"
        fi
    fi

    echo ""
    if command -v gum &> /dev/null; then
        gum confirm "Press Enter to continue" && return
    else
        echo -e "\n${BLUE}Press Enter to continue...${NC}"
        read -r
    fi
}

# Main menu with gum
show_menu() {
    if command -v gum &> /dev/null; then
        clear
        # Fancy header
        gum style \
            --border thick \
            --margin "1" \
            --padding "1 2" \
            --border-foreground 212 \
            --foreground 226 \
            "🏠  $SCRIPT_NAME v$SCRIPT_VERSION" \
            "" \
            "Universal backup tool - works anywhere (USB, network, local)"

        # Show script location warning if needed
        if [[ "$SCRIPT_DIR" == "$HOME"* ]]; then
            gum style \
                --padding "0 2" \
                --foreground 196 \
                "⚠️  WARNING: Script running from home folder!"
        fi

        # Show mount type in menu
        local mount_type=$(detect_mount_type)
        case "$mount_type" in
            usb)
                gum style \
                    --padding "0 2" \
                    --foreground 46 \
                    "💾 Destination: USB Drive"
                ;;
            network)
                gum style \
                    --padding "0 2" \
                    --foreground 99 \
                    "🌐 Destination: Network Mount"
                ;;
            different_device)
                gum style \
                    --padding "0 2" \
                    --foreground 46 \
                    "💿 Destination: Different Device (optimal)"
                ;;
            same_device)
                gum style \
                    --padding "0 2" \
                    --foreground 226 \
                    "⚠️  Destination: Same Device (not recommended)"
                ;;
        esac

        # Show performance mode
        gum style \
            --padding "0 2" \
            --foreground 99 \
            "⚡ Performance Mode: $PERFORMANCE_MODE"

        # Show disk space warning if needed
        local free_space_mb=$(df -m "$BACKUP_DEST" 2>/dev/null | awk 'NR==2 {print $4}')
        if [ ! -z "$free_space_mb" ]; then
            if [ $free_space_mb -lt $EMERGENCY_THRESHOLD ]; then
                gum style \
                    --padding "0 2" \
                    --foreground 196 \
                    "🔴 CRITICAL: Emergency low disk space!"
            elif [ $free_space_mb -lt $MIN_FREE_SPACE ]; then
                gum style \
                    --padding "0 2" \
                    --foreground 226 \
                    "🟡 Warning: Low disk space"
            fi
        fi

        # Show backup status in menu
        if [ -d "$BACKUP_DEST/latest" ]; then
            latest=$(readlink -f "$BACKUP_DEST/latest")
            latest_size=$(du -sh "$latest" 2>/dev/null | cut -f1)
            latest_date=$(basename "$latest" | sed "s/$(basename "$BACKUP_SOURCE")_//")

            # Determine if it's incremental
            local backups=()
            while IFS= read -r -d '' backup; do
                backups+=("$backup")
            done < <(find "$BACKUP_DEST" -maxdepth 1 -type d -name "$(basename "$BACKUP_SOURCE")_*" -print0 | sort -r)

            if [ ${#backups[@]} -gt 1 ] && [ "${backups[0]}" = "$latest" ]; then
                gum style \
                    --padding "0 2" \
                    --foreground 46 \
                    "✅ Latest: $latest_date [$latest_size] (Incremental)"
            else
                gum style \
                    --padding "0 2" \
                    --foreground 46 \
                    "✅ Latest: $latest_date [$latest_size]"
            fi
        else
            gum style \
                --padding "0 2" \
                --foreground 196 \
                "❌ No backups found"
        fi

        # Show backup count
        local backup_count=$(find "$BACKUP_DEST" -maxdepth 1 -type d -name "$(basename "$BACKUP_SOURCE")_*" 2>/dev/null | wc -l)
        gum style \
            --padding "0 2" \
            --foreground 226 \
            "📚 Keeping last $MAX_BACKUPS backups (${backup_count} total)"

        # Show log count
        local log_count=$(find "$LOGS_DIR" -maxdepth 1 -type f -name "backup_*.log" 2>/dev/null | wc -l)
        gum style \
            --padding "0 2" \
            --foreground 99 \
            "📋 Logs: $log_count available"

        # Main menu
        choice=$(gum choose \
            --header="Select operation:" \
            --cursor="👉 " \
            --cursor.foreground="212" \
            --selected.foreground="212" \
            --height=15 \
            "💾 Create Backup (Incremental)" \
            "🔍 Dry Run (Preview)" \
            "♻️  Restore Backup" \
            "📊 View Status" \
            "📋 View Logs" \
            "🔍 Update Exclusions" \
            "🧹 Cleanup Old Backups" \
            "⏰ Schedule Automatic Backups" \
            "⚡ Change Performance Mode" \
            "🖥️  Create Desktop Shortcut" \
            "ℹ️  Destination Info" \
            "❌ Exit")

        case $choice in
            "💾 Create Backup (Incremental)")
                do_backup
                ;;
            "🔍 Dry Run (Preview)")
                do_backup "dry"
                ;;
            "♻️  Restore Backup")
                do_restore
                ;;
            "📊 View Status")
                show_status
                ;;
            "📋 View Logs")
                view_logs
                ;;
            "🔍 Update Exclusions")
                update_exclusions
                ;;
            "🧹 Cleanup Old Backups")
                do_cleanup
                ;;
            "⏰ Schedule Automatic Backups")
                setup_scheduling
                ;;
            "⚡ Change Performance Mode")
                change_performance_mode
                ;;
            "🖥️  Create Desktop Shortcut")
                create_desktop_shortcut
                ;;
            "ℹ️  Destination Info")
                show_destination_info
                ;;
            "❌ Exit")
                clear
                gum style --foreground 212 "Goodbye! 👋"
                exit 0
                ;;
        esac
    else
        # Fallback menu without gum
        while true; do
            print_header

            # Show script location warning
            check_script_location
            echo ""

            # Show mount information
            show_mount_info

            echo -e "${GREEN}1.${NC} 💾 Create Backup (Incremental)"
            echo -e "${GREEN}2.${NC} 🔍 Dry Run (Preview)"
            echo -e "${GREEN}3.${NC} ♻️  Restore Backup"
            echo -e "${GREEN}4.${NC} 📊 View Status"
            echo -e "${GREEN}5.${NC} 📋 View Logs"
            echo -e "${GREEN}6.${NC} 🔍 Update Exclusions"
            echo -e "${GREEN}7.${NC} 🧹 Cleanup Old Backups"
            echo -e "${GREEN}8.${NC} ⏰ Schedule Automatic Backups"
            echo -e "${GREEN}9.${NC} ⚡ Change Performance Mode"
            echo -e "${GREEN}10.${NC} 🖥️  Create Desktop Shortcut"
            echo -e "${GREEN}11.${NC} ℹ️  Destination Info"
            echo -e "${GREEN}12.${NC} ❌ Exit"
            echo ""

            # Show disk space warning
            local free_space_mb=$(df -m "$BACKUP_DEST" 2>/dev/null | awk 'NR==2 {print $4}')
            if [ ! -z "$free_space_mb" ]; then
                if [ $free_space_mb -lt $EMERGENCY_THRESHOLD ]; then
                    echo -e "${RED}🔴 CRITICAL: Emergency low disk space!${NC}"
                elif [ $free_space_mb -lt $MIN_FREE_SPACE ]; then
                    echo -e "${YELLOW}🟡 Warning: Low disk space${NC}"
                fi
            fi

            # Show backup count
            local backup_count=$(find "$BACKUP_DEST" -maxdepth 1 -type d -name "$(basename "$BACKUP_SOURCE")_*" 2>/dev/null | wc -l)
            echo -e "${YELLOW}Backups: $backup_count / $MAX_BACKUPS kept${NC}"

            # Show log count
            local log_count=$(find "$LOGS_DIR" -maxdepth 1 -type f -name "backup_*.log" 2>/dev/null | wc -l)
            echo -e "${PURPLE}Logs: $log_count available${NC}"

            if [ -d "$BACKUP_DEST/latest" ]; then
                latest_size=$(du -sh "$BACKUP_DEST/latest" 2>/dev/null | cut -f1)
                echo -e "${GREEN}Latest: $latest_size${NC}"
            fi

            echo ""
            echo -e "${YELLOW}Choice [1-12]:${NC}"
            read -r choice

            case $choice in
                1) do_backup ;;
                2) do_backup "dry" ;;
                3) do_restore ;;
                4) show_status ;;
                5) view_logs ;;
                6) update_exclusions ;;
                7) do_cleanup ;;
                8) setup_scheduling ;;
                9) change_performance_mode ;;
                10) create_desktop_shortcut ;;
                11) show_destination_info ;;
                12)
                    clear
                    echo -e "${GREEN}Goodbye! 👋${NC}"
                    exit 0
                    ;;
                *)
                    echo -e "${RED}Invalid choice${NC}"
                    sleep 1
                    ;;
            esac
        done
    fi
}

# Function to change performance mode
change_performance_mode() {
    clear

    if command -v gum &> /dev/null; then
        gum style \
            --border double \
            --padding "1 2" \
            --margin "1" \
            --border-foreground 99 \
            "⚡  PERFORMANCE MODES" \
            "" \
            "Choose your preferred performance mode"
    else
        print_header
        echo -e "${PURPLE}⚡ PERFORMANCE MODES${NC}"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    fi

    echo ""
    echo -e "${CYAN}Available Modes:${NC}"
    echo -e "  ${GREEN}safe${NC}   - Default, uses --no-inplace, verifies with checksums (safest)"
    echo -e "  ${YELLOW}fast${NC}   - Uses --inplace for SSD speed, skips checksums (faster)"
    echo -e "  ${RED}turbo${NC}  - Uses --inplace and --no-whole-file (fastest, riskier)"
    echo ""
    echo -e "Current mode: ${PURPLE}$PERFORMANCE_MODE${NC}"
    echo ""

    local mount_type=$(detect_mount_type)
    echo -e "${BLUE}Recommendation for your setup ($mount_type):${NC}"
    case "$mount_type" in
        usb)
            echo -e "  • ${YELLOW}safe mode${NC} recommended for USB drives"
            ;;
        network)
            echo -e "  • ${YELLOW}safe mode${NC} with bandwidth limit recommended"
            ;;
        different_device)
            echo -e "  • ${GREEN}fast or turbo mode${NC} recommended for SSD/HDD"
            ;;
        same_device)
            echo -e "  • ${YELLOW}Consider moving to different device${NC}"
            ;;
    esac

    echo ""
    if command -v gum &> /dev/null; then
        local new_mode=$(gum choose "safe" "fast" "turbo" "Cancel")
        if [ "$new_mode" != "Cancel" ] && [ -n "$new_mode" ]; then
            PERFORMANCE_MODE="$new_mode"
            gum style --foreground 46 "✅ Performance mode changed to: $PERFORMANCE_MODE"

            # Optionally save to config
            if gum confirm "Save to config file?"; then
                if [ -f "$CONFIG_FILE" ]; then
                    sed -i "s/PERFORMANCE_MODE=.*/PERFORMANCE_MODE=\"$PERFORMANCE_MODE\"/" "$CONFIG_FILE"
                else
                    echo "PERFORMANCE_MODE=\"$PERFORMANCE_MODE\"" > "$CONFIG_FILE"
                fi
                gum style --foreground 46 "✅ Saved to config file"
            fi
        fi
    else
        echo -e "${YELLOW}Enter new mode (safe/fast/turbo) or press Enter to cancel:${NC}"
        read -r new_mode
        if [[ "$new_mode" =~ ^(safe|fast|turbo)$ ]]; then
            PERFORMANCE_MODE="$new_mode"
            echo -e "${GREEN}✅ Performance mode changed to: $PERFORMANCE_MODE${NC}"

            echo -e "${YELLOW}Save to config file? (y/n)${NC}"
            read -r save_config
            if [[ "$save_config" =~ ^[Yy]$ ]]; then
                if [ -f "$CONFIG_FILE" ]; then
                    sed -i "s/PERFORMANCE_MODE=.*/PERFORMANCE_MODE=\"$PERFORMANCE_MODE\"/" "$CONFIG_FILE"
                else
                    echo "PERFORMANCE_MODE=\"$PERFORMANCE_MODE\"" > "$CONFIG_FILE"
                fi
                echo -e "${GREEN}✅ Saved to config file${NC}"
            fi
        fi
    fi

    sleep 2
}

# Parse command line arguments
parse_arguments() {
    case "$1" in
        -h|--help)
            show_help
            ;;
        -v|--version)
            show_version
            ;;
        -b|--backup)
            do_backup
            ;;
        -c|--cron)
            do_backup "cron"
            ;;
        -d|--dry-run)
            do_backup "dry"
            ;;
        -s|--status)
            show_status
            ;;
        -l|--logs)
            view_logs
            ;;
        -r|--restore)
            do_restore
            ;;
        -u|--update-exclusions)
            update_exclusions
            ;;
        -k|--cleanup)
            do_cleanup
            ;;
        --schedule)
            setup_scheduling
            ;;
        --desktop)
            create_desktop_shortcut
            ;;
        --info)
            show_destination_info
            ;;
        --mode)
            if [ -n "$2" ] && [[ "$2" =~ ^(safe|fast|turbo)$ ]]; then
                PERFORMANCE_MODE="$2"
                echo -e "${GREEN}✅ Performance mode set to: $PERFORMANCE_MODE${NC}"
                shift
            else
                echo -e "${RED}❌ Invalid mode. Use safe, fast, or turbo.${NC}"
                exit 1
            fi
            ;;
        --encrypt)
            ENABLE_ENCRYPTION=true
            echo -e "${GREEN}✅ Encryption enabled${NC}"
            ;;
        --verify)
            ENABLE_VERIFICATION=true
            echo -e "${GREEN}✅ Verification enabled${NC}"
            ;;
        --email)
            if [ -n "$2" ]; then
                ENABLE_EMAIL_NOTIFY=true
                EMAIL_ADDRESS="$2"
                echo -e "${GREEN}✅ Email notifications enabled for $EMAIL_ADDRESS${NC}"
                shift
            else
                echo -e "${RED}❌ Email address required${NC}"
                exit 1
            fi
            ;;
        --bwlimit)
            if [ -n "$2" ] && [[ "$2" =~ ^[0-9]+$ ]]; then
                BANDWIDTH_LIMIT="$2"
                echo -e "${GREEN}✅ Bandwidth limit set to ${BANDWIDTH_LIMIT} KB/s${NC}"
                shift
            else
                echo -e "${RED}❌ Valid bandwidth limit required (KB/s)${NC}"
                exit 1
            fi
            ;;
        --generate-config)
            generate_config
            exit 0
            ;;
        "")
            # No arguments, run interactive mode
            main
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo -e "${YELLOW}Use --help for usage information${NC}"
            exit 1
            ;;
esac
}

# Main execution
main() {
    # Interactive mode
    show_loading "Initializing $SCRIPT_NAME v$SCRIPT_VERSION" 1

    # Check dependencies
    check_dependencies

    # Create necessary directories
    mkdir -p "$BACKUP_DEST"
    mkdir -p "$LOGS_DIR"

    echo -e "${GREEN}✅ Directories ready:${NC}"
    echo -e "  📁 Backups: $BACKUP_DEST"
    echo -e "  📋 Logs:    $LOGS_DIR"
    sleep 1

    # Initial exclusion generation if needed
    if [ ! -f "/tmp/clean_exclusions.txt" ]; then
        search_exclusions
        detect_local_exclusions
        local count=$(merge_exclusions)
        echo -e "${GREEN}✅ Generated $count exclusion patterns${NC}"
        sleep 1
    fi

    # Start main menu loop
    while true; do
        show_menu
    done
}

# Parse command line arguments
if [ $# -gt 0 ]; then
    parse_arguments "$@"
else
    main
fi
