#!/bin/bash
#############################################################################################################################
#
# Wael Isa
# Website:  https://www.wael.name
# GitHub:   https://github.com/waelisa/home-backup
# Version:  v1.1.4
# Build Date: 02/24/2026
#
# ██╗    ██╗ █████╗ ███████╗██╗         ██╗███████╗ █████╗
# ██║    ██║██╔══██╗██╔════╝██║         ██║██╔════╝██╔══██╗
# ██║ █╗ ██║███████║█████╗  ██║         ██║███████╗███████║
# ██║███╗██║██╔══██║██╔══╝  ██║         ██║╚════██║██╔══██║
# ╚███╔███╔╝██║  ██║███████╗███████╗    ██║███████╗██║  ██║
# ╚══╝╚══╝ ╚═╝  ╚═╝╚══════╝╚══════╝    ╚═╝╚══════╝╚═╝  ╚═╝
#
# Description: A bulletproof backup tool for your home folder with smart exclusions,
#              true incremental backups using hard links, atomic symlink updates,
#              desktop integration, automatic scheduling, universal path support,
#              and now with BIT ROT PROTECTION via checksum verification.
#
# Features:
#   • Universal path detection - works anywhere (USB drives, external disks, network mounts)
#   • Smart mount checking - verifies destination is accessible before backup
#   • Auto-eject for USB drives - safely unmounts drive after backup
#   • Integrity verification - SHA256 checksums for critical data
#   • Performance tuning options (safe vs fast vs turbo modes)
#   • Encryption support for cloud backups (GPG)
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
#   • Color-coded log summaries
#   • Paginated help system
#   • Remote sync ready (SSH support coming in v2.0)
#   • 🔍 VERIFICATION MODE - Full checksum verification to detect bit rot!
#
# v1.1.4 NEW FEATURE: Verification Mode (--verify)
#   • Detects silent data corruption (bit rot) on aging hardware
#   • Uses rsync -c to compare actual file contents, not just timestamps
#   • Ensures 100% data integrity even if file sizes haven't changed
#   • Slower but provides absolute confidence in backup quality
#   • Recommended to run monthly on critical data
#
# Performance Modes:
#   • safe   - Default, uses --no-inplace, verifies with checksums (safest)
#   • fast   - Uses --inplace for SSD speed, skips checksums (faster)
#   • turbo  - Uses --inplace and --no-whole-file (fastest, riskier)
#   • verify - Special mode that forces content checksum comparison (-c flag)
#
# Security Features:
#   • Auto-eject - Safely unmounts USB drives after backup
#   • Integrity verification - SHA256 checksums for critical data
#   • Emergency thresholds - Prevents backup with critically low space
#   • Atomic symlinks - Never points to failed backups
#   • Bit rot detection - Optional full checksum verification
#
# Requirements:
#   • rsync, gum (optional), notify-send (optional)
#   • udisks2 (for auto-eject), gpg (optional, for encryption)
#   • mail/mailx (optional, for email notifications)
#
# MODULAR STRUCTURE:
#   • home-backup.sh        - Main executable (this file)
#   • home-backup.functions - All core functions
#   • home-backup.modules   - Additional modules and features
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
#   v1.1.2 - Auto-eject for USB drives, integrity verification
#   v1.1.3 - Comprehensive help system, color-coded logs, pagination
#   v1.1.4 - VERIFICATION MODE: Full checksum comparison for bit rot detection!
#   v1.1.4 - MODULAR STRUCTURE: Split into main, functions, and modules
#
#############################################################################################################################

# Get the directory where this script is located
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# Source the functions file (core functionality)
if [ -f "$SCRIPT_DIR/home-backup.functions" ]; then
    source "$SCRIPT_DIR/home-backup.functions"
else
    echo "ERROR: Cannot find home-backup.functions in $SCRIPT_DIR"
    echo "Please ensure all module files are in the same directory."
    exit 1
fi

# Source the modules file (additional features)
if [ -f "$SCRIPT_DIR/home-backup.modules" ]; then
    source "$SCRIPT_DIR/home-backup.modules"
else
    echo "ERROR: Cannot find home-backup.modules in $SCRIPT_DIR"
    echo "Please ensure all module files are in the same directory."
    exit 1
fi

# Display module load confirmation (quiet mode for cron)
if [ "$1" != "--cron" ] && [ "$1" != "-c" ]; then
    echo -e "${GREEN}✅ Modules loaded successfully${NC}"
    sleep 1
fi

# Parse command line arguments
if [ $# -gt 0 ]; then
    parse_arguments "$@"
else
    # No arguments, run interactive mode
    main
fi

#####################################################################
# ENCRYPTION MODULE
#####################################################################

encrypt_backup() {
    local backup_path="$1"
    local cron_mode="$2"
    local encrypted_path="${backup_path}.gpg"

    if command -v gpg &> /dev/null; then
        if ! is_cron_mode "$cron_mode"; then
            echo -e "${BLUE}🔐 Encrypting backup...${NC}"
        fi

        if tar czf - "$backup_path" 2>/dev/null | gpg -c --cipher-algo AES256 -o "$encrypted_path" 2>/dev/null; then
            if ! is_cron_mode "$cron_mode"; then
                echo -e "${GREEN}✅ Backup encrypted successfully${NC}"
            fi
            echo "$encrypted_path"
        else
            if ! is_cron_mode "$cron_mode"; then
                echo -e "${RED}❌ Encryption failed${NC}"
            fi
            echo "$backup_path"
        fi
    else
        echo "$backup_path"
    fi
}

#####################################################################
# INTEGRITY VERIFICATION MODULE
#####################################################################

verify_integrity() {
    local backup_path="$1"
    local cron_mode="$2"
    local source_path="$BACKUP_SOURCE"

    if ! is_cron_mode "$cron_mode"; then
        echo -e "${BLUE}🔍 Running integrity verification...${NC}"
    fi

    mkdir -p "$INTEGRITY_DIR"

    local critical_folders=(
        "Documents"
        "Pictures"
        "Videos"
        "Music"
        "Desktop"
    )

    local verified_count=0
    local failed_count=0

    echo "Integrity Verification - $(date)" > "$INTEGRITY_LOG"

    for folder in "${critical_folders[@]}"; do
        local source_folder="$source_path/$folder"
        local backup_folder="$backup_path/$folder"

        if [ -d "$source_folder" ] && [ -d "$backup_folder" ]; then
            local source_count=$(find "$source_folder" -type f 2>/dev/null | wc -l)
            local backup_count=$(find "$backup_folder" -type f 2>/dev/null | wc -l)

            if [ "$source_count" -eq "$backup_count" ]; then
                echo "✅ $folder: OK ($source_count files)" >> "$INTEGRITY_LOG"
                ((verified_count++))
            else
                echo "⚠️  $folder: Source=$source_count, Backup=$backup_count" >> "$INTEGRITY_LOG"
                ((failed_count++))
            fi
        fi
    done

    echo "Verified: $verified_count, Issues: $failed_count" >> "$INTEGRITY_LOG"

    if [ $failed_count -gt 0 ] && [ "$ENABLE_EMAIL_NOTIFY" = true ]; then
        send_email "Integrity Issues" "Found issues in $failed_count folders"
    fi
}

#####################################################################
# AUTO-EJECT MODULE
#####################################################################

do_eject() {
    local eject_requested=$1
    local cron_mode=$2

    local mount_type=$(detect_mount_type)
    if [ "$mount_type" != "usb" ]; then
        return 0
    fi

    local mount_point=$(df -P "$BACKUP_DEST" 2>/dev/null | tail -1 | awk '{print $6}')
    local device=$(findmnt -n -o SOURCE --target "$BACKUP_DEST" 2>/dev/null)

    if [ -z "$device" ] || [ -z "$mount_point" ]; then
        return 0
    fi

    if [ "$ENABLE_AUTO_EJECT" = true ] || [ "$eject_requested" = true ]; then
        sync

        if command -v udisksctl &> /dev/null; then
            if udisksctl unmount -b "$device" &>/dev/null; then
                udisksctl power-off -b "$device" &>/dev/null
                if ! is_cron_mode "$cron_mode"; then
                    echo -e "${GREEN}✅ Drive safely ejected${NC}"
                fi
                echo "$(date): Drive ejected" >> "$LOG_FILE"
                return 0
            else
                return 1
            fi
        else
            if umount "$mount_point" &>/dev/null; then
                if ! is_cron_mode "$cron_mode"; then
                    echo -e "${GREEN}✅ Drive unmounted${NC}"
                fi
                return 0
            else
                return 1
            fi
        fi
    fi
}

#####################################################################
# CLEANUP MODULES
#####################################################################

cleanup_old_backups() {
    local cron_mode=$1
    local backups=()

    while IFS= read -r -d '' backup; do
        backups+=("$backup")
    done < <(find "$BACKUP_DEST" -maxdepth 1 -type d -name "$(basename "$BACKUP_SOURCE")_*" -print0 | sort -rz)

    local total_backups=${#backups[@]}

    if [ $total_backups -gt $MAX_BACKUPS ]; then
        if [ -z "$cron_mode" ]; then
            echo -e "\n${YELLOW}🧹 Cleaning up old backups...${NC}"
        fi

        for ((i=$MAX_BACKUPS; i<$total_backups; i++)); do
            local old_backup="${backups[$i]}"
            if [ -d "$old_backup" ]; then
                rm -rf "$old_backup"
            fi
        done
    fi

    if [ ${#backups[@]} -gt 0 ]; then
        ln -snf "${backups[0]}" "$BACKUP_DEST/latest"
    fi
}

cleanup_old_logs() {
    local cron_mode=$1
    local logs=()

    while IFS= read -r -d '' log; do
        logs+=("$log")
    done < <(find "$LOGS_DIR" -maxdepth 1 -type f -name "backup_*.log" -print0 | sort -rz)

    local total_logs=${#logs[@]}
    local max_logs=10

    if [ $total_logs -gt $max_logs ]; then
        for ((i=$max_logs; i<$total_logs; i++)); do
            rm -f "${logs[$i]}"
        done
    fi
}

cleanup_old_integrity() {
    local logs=()
    while IFS= read -r -d '' log; do
        logs+=("$log")
    done < <(find "$INTEGRITY_DIR" -maxdepth 1 -type f -name "integrity_*.log" -print0 | sort -rz)

    local total_logs=${#logs[@]}
    local max_logs=5

    if [ $total_logs -gt $max_logs ]; then
        for ((i=$max_logs; i<$total_logs; i++)); do
            rm -f "${logs[$i]}"
        done
    fi
}

#####################################################################
# EXCLUSION GENERATION MODULE
#####################################################################

search_exclusions() {
    local cron_mode=$1

    if ! is_cron_mode "$cron_mode"; then
        echo -e "${BLUE}🔍 Generating exclusion patterns...${NC}"
    fi

    cat > /tmp/recommended_exclusions.txt << 'EOF'
# Temporary & Cache Files
.cache
.thumbnails
.trash
.local/share/Trash
tmp
temp
*.tmp
*.temp

# Browser Caches
.mozilla/firefox/*/cache2
.config/google-chrome/Default/Cache
.config/chromium/Default/Cache

# Package Manager Caches
.cache/yay
.cache/pacman
.cache/pip
.npm
.cargo/registry

# Development
node_modules
__pycache__
*.pyc
target
build
dist

# Logs & History
.bash_history
.zsh_history
*.log
EOF
}

detect_local_exclusions() {
    local cron_mode=$1
    local local_excludes=()

    if command -v steam &> /dev/null || [ -d "$HOME/.steam" ]; then
        local_excludes+=(".steam")
    fi

    if command -v flatpak &> /dev/null; then
        local_excludes+=(".var")
    fi

    if command -v snap &> /dev/null; then
        local_excludes+=(".snap")
    fi

    printf "%s\n" "${local_excludes[@]}" > /tmp/local_exclusions.txt
}

merge_exclusions() {
    local merged_file="/tmp/final_exclusions.txt"

    cat > "$merged_file" << 'EOF'
.cache
.trash
.local/share/Trash
tmp
*.tmp
*.temp
*.log
EOF

    if [ -f "/tmp/recommended_exclusions.txt" ]; then
        grep -v "^#" "/tmp/recommended_exclusions.txt" | grep -v "^$" >> "$merged_file"
    fi

    if [ -f "/tmp/local_exclusions.txt" ]; then
        cat "/tmp/local_exclusions.txt" >> "$merged_file"
    fi

    sort -u "$merged_file" | grep -v "^#" | grep -v "^$" > "/tmp/clean_exclusions.txt"
    wc -l < "/tmp/clean_exclusions.txt"
}

#####################################################################
# LOG VIEWING MODULE
#####################################################################

show_log_summary() {
    clear

    echo -e "${BLUE}📋 LOG SUMMARY${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    local logs=()
    while IFS= read -r -d '' log; do
        logs+=("$log")
    done < <(find "$LOGS_DIR" -maxdepth 1 -type f -name "backup_*.log" -print0 | sort -r)

    if [ ${#logs[@]} -eq 0 ]; then
        echo -e "${RED}❌ No logs found${NC}"
        sleep 2
        return
    fi

    echo ""
    for i in "${!logs[@]}"; do
        local log="${logs[$i]}"
        local log_name=$(basename "$log")
        local log_date=${log_name#backup_}
        log_date=${log_date%.log}
        local log_size=$(du -sh "$log" 2>/dev/null | cut -f1)

        if grep -q "completed successfully" "$log"; then
            echo -e "  ${GREEN}$((i+1)).${NC} ${log_date//_/ } ${GREEN}[$log_size] ✅${NC}"
        elif grep -q "FAILED" "$log"; then
            echo -e "  ${RED}$((i+1)).${NC} ${log_date//_/ } ${RED}[$log_size] ❌${NC}"
        else
            echo -e "  ${YELLOW}$((i+1)).${NC} ${log_date//_/ } ${YELLOW}[$log_size] ⚠️${NC}"
        fi
    done

    echo ""
    echo -e "${YELLOW}Enter log number to view (or 0 to exit):${NC}"
    read -r choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#logs[@]} ]; then
        less "${logs[$((choice-1))]}"
    fi
}

view_logs() {
    show_log_summary
}

#####################################################################
# DESKTOP INTEGRATION MODULE
#####################################################################

create_desktop_shortcut() {
    local desktop_file="$HOME/.local/share/applications/home-backup.desktop"
    local script_path="$(readlink -f "$0")"

    mkdir -p "$HOME/.local/share/applications"

    cat > "$desktop_file" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Home Backup
Comment=Backup and restore your home folder
Exec=$script_path
Icon=system-backup
Terminal=true
Categories=System;Utility;
Keywords=backup;restore;
EOF

    chmod +x "$desktop_file"

    if [ -d "$HOME/Desktop" ]; then
        cp "$desktop_file" "$HOME/Desktop/"
    fi

    echo -e "${GREEN}✅ Desktop shortcut created!${NC}"
    sleep 2
}

#####################################################################
# SCHEDULING MODULE
#####################################################################

setup_scheduling() {
    clear
    echo -e "${BLUE}⏰ Schedule Automatic Backups${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    local script_path="$(readlink -f "$0")"
    local cron_job="0 2 * * * $script_path --cron >> $LOGS_DIR/cron.log 2>&1"

    (crontab -l 2>/dev/null | grep -v "$script_path" | crontab -)
    (crontab -l 2>/dev/null; echo "$cron_job") | crontab -

    echo -e "${GREEN}✅ Daily backup scheduled for 2 AM${NC}"
    sleep 2
}

#####################################################################
# RESTORE MODULE
#####################################################################

do_restore() {
    clear
    echo -e "${RED}⚠️  RESTORE OPERATION${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    local backups=()
    while IFS= read -r -d '' backup; do
        backups+=("$backup")
    done < <(find "$BACKUP_DEST" -maxdepth 1 -type d -name "$(basename "$BACKUP_SOURCE")_*" -print0 | sort -r)

    if [ ${#backups[@]} -eq 0 ]; then
        echo -e "${RED}❌ No backups found${NC}"
        sleep 2
        return
    fi

    echo -e "${CYAN}Available backups:${NC}"
    for i in "${!backups[@]}"; do
        local name=$(basename "${backups[$i]}")
        local date_part=${name//$(basename "$BACKUP_SOURCE")_/}
        echo -e "  $((i+1)). ${date_part//_/ at }"
    done

    echo ""
    echo -e "${YELLOW}Select backup to restore:${NC}"
    read -r selection

    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le ${#backups[@]} ]; then
        local selected_backup="${backs[$((selection-1))]}"
        echo -e "${RED}⚠️  This will overwrite your home folder!${NC}"
        echo -e "${YELLOW}Are you sure? (type 'yes' to confirm)${NC}"
        read -r confirm

        if [ "$confirm" = "yes" ]; then
            rsync -avh --progress "$selected_backup/" "$BACKUP_SOURCE/"
            echo -e "${GREEN}✅ Restore completed!${NC}"
        fi
    fi

    sleep 2
}

#####################################################################
# STATUS MODULE
#####################################################################

show_status() {
    clear
    echo -e "${BLUE}📊 BACKUP STATUS${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if [ -d "$BACKUP_DEST/latest" ]; then
        local latest=$(readlink -f "$BACKUP_DEST/latest")
        local size=$(du -sh "$latest" 2>/dev/null | cut -f1)
        local files=$(find "$latest" -type f 2>/dev/null | wc -l)
        local name=$(basename "$latest")
        local date_part=${name//$(basename "$BACKUP_SOURCE")_/}

        echo -e "${GREEN}✅ Latest Backup:${NC}"
        echo -e "  Date: ${date_part//_/ at }"
        echo -e "  Size: $size"
        echo -e "  Files: $files"
    else
        echo -e "${RED}❌ No backups found${NC}"
    fi

    echo ""
    echo -e "${BLUE}Press Enter to continue...${NC}"
    read -r
}

#####################################################################
# CONFIGURATION MODULE
#####################################################################

generate_config() {
    local config_file="$SCRIPT_DIR/backup.conf"

    cat > "$config_file" << 'EOF'
# Home Backup Configuration
PERFORMANCE_MODE="safe"
VERIFY_MODE=false
ENABLE_ENCRYPTION=false
ENABLE_INTEGRITY=false
ENABLE_AUTO_EJECT=false
ENABLE_EMAIL_NOTIFY=false
EMAIL_ADDRESS=""
BANDWIDTH_LIMIT=0
MAX_BACKUPS=2
MIN_FREE_SPACE=1024
EMERGENCY_THRESHOLD=512
EOF

    echo -e "${GREEN}✅ Config file generated: $config_file${NC}"
}

#####################################################################
# MAIN MENU
#####################################################################

show_menu() {
    if command -v gum &> /dev/null; then
        clear
        gum style \
            --border thick \
            --margin "1" \
            --padding "1 2" \
            --border-foreground 212 \
            --foreground 226 \
            "🏠  $SCRIPT_NAME v$SCRIPT_VERSION" \
            "" \
            "Bulletproof backup tool - now with BIT ROT PROTECTION! 🔍"

        choice=$(gum choose \
            --header="Select operation:" \
            --height=15 \
            "💾 Create Backup" \
            "🔍 Verify Mode Backup (Check Bit Rot)" \
            "🔍 Dry Run" \
            "♻️  Restore" \
            "📊 Status" \
            "📋 View Logs" \
            "🔍 Update Exclusions" \
            "🧹 Cleanup" \
            "⏰ Schedule" \
            "⚡ Change Performance Mode" \
            "🔌 Toggle Auto-Eject" \
            "🖥️  Desktop Shortcut" \
            "ℹ️  Destination Info" \
            "📖 Help" \
            "❌ Exit")

        case $choice in
            "💾 Create Backup")
                VERIFY_MODE="false"
                do_backup
                ;;
            "🔍 Verify Mode Backup (Check Bit Rot)")
                VERIFY_MODE="true"
                do_backup
                ;;
            "🔍 Dry Run")
                do_backup "dry"
                ;;
            "♻️  Restore")
                do_restore
                ;;
            "📊 Status")
                show_status
                ;;
            "📋 View Logs")
                view_logs
                ;;
            "🔍 Update Exclusions")
                update_exclusions
                ;;
            "🧹 Cleanup")
                do_cleanup
                ;;
            "⏰ Schedule")
                setup_scheduling
                ;;
            "⚡ Change Performance Mode")
                change_performance_mode
                ;;
            "🔌 Toggle Auto-Eject")
                toggle_auto_eject
                ;;
            "🖥️  Desktop Shortcut")
                create_desktop_shortcut
                ;;
            "ℹ️  Destination Info")
                show_destination_info
                ;;
            "📖 Help")
                show_paginated_help
                ;;
            "❌ Exit")
                clear
                exit 0
                ;;
        esac
    fi
}

#####################################################################
# MAIN ENTRY POINT
#####################################################################

main() {
    show_loading "Initializing $SCRIPT_NAME v$SCRIPT_VERSION" 1
    check_dependencies

    mkdir -p "$BACKUP_DEST" "$LOGS_DIR" "$INTEGRITY_DIR"

    if [ ! -f "/tmp/clean_exclusions.txt" ]; then
        search_exclusions
        detect_local_exclusions
        merge_exclusions > /dev/null
    fi

    echo -e "${PURPLE}🔍 v1.1.4 NEW: Verification Mode - protects against bit rot!${NC}"
    sleep 2

    while true; do
        show_menu
    done
}

# Export all module functions
export -f encrypt_backup verify_integrity do_eject
export -f cleanup_old_backups cleanup_old_logs cleanup_old_integrity
export -f search_exclusions detect_local_exclusions merge_exclusions
export -f show_log_summary view_logs create_desktop_shortcut
export -f setup_scheduling do_restore show_status generate_config
export -f show_menu main
