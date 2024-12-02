#!/bin/bash

# Define colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Define old paths to clean up
OLD_PATHS=(
    # Old repository locations
    "/home/pi/lister_numpad_macros"
    "/home/pi/lister_sound_system"
    "/home/pi/printer_data/gcodes/lister_printables"
    "/home/pi/printer_data/config/lister_config"
    
    # Old symlinks
    "/home/pi/klipper/klippy/extras/numpad_event_service.py"
    "/home/pi/klipper/klippy/extras/sound_system.py"
    "/home/pi/moonraker/moonraker/components/numpad_macros.py"
    "/home/pi/moonraker/moonraker/components/sound_system_service.py"
    
    # Old service files
    "/etc/systemd/system/numpad_event_service.service"
    
    # Old log files
    "/home/pi/printer_data/logs/numpad_event_service.log"
    "/home/pi/printer_data/logs/sound_system.log"
    "/home/pi/printer_data/logs/metadata_scan.log"
    "/home/pi/printer_data/logs/lister_printables_install.log"
    "/home/pi/printer_data/logs/lister_printables_update.log"
)

# Function to log messages
log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local color=""
    
    case $level in
        "INFO") color=$GREEN ;;
        "ERROR") color=$RED ;;
        "WARNING") color=$YELLOW ;;
        *) color=$NC ;;
    esac
    
    echo -e "${color}${timestamp} [${level}] ${message}${NC}"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_message "ERROR" "Please run as root (sudo)"
    exit 1
fi

# Stop related services
log_message "INFO" "Stopping services..."
systemctl stop numpad_event_service klipper moonraker

# Remove old files and directories
for path in "${OLD_PATHS[@]}"; do
    if [ -L "$path" ]; then
        # It's a symlink
        log_message "INFO" "Removing symlink: $path"
        rm -f "$path"
    elif [ -d "$path" ]; then
        # It's a directory
        log_message "INFO" "Removing directory: $path"
        rm -rf "$path"
    elif [ -f "$path" ]; then
        # It's a regular file
        log_message "INFO" "Removing file: $path"
        rm -f "$path"
    else
        log_message "WARNING" "Path not found: $path"
    fi
done

# Remove old cron jobs
log_message "INFO" "Removing old cron jobs..."
(crontab -l 2>/dev/null | grep -v "update_lister_metadata.py") | crontab -

# Reload systemd to remove old service
log_message "INFO" "Reloading systemd..."
systemctl daemon-reload

# Restart services
log_message "INFO" "Starting services..."
systemctl start klipper
sleep 2
systemctl start moonraker

log_message "INFO" "Cleanup completed successfully"
log_message "INFO" "You can now proceed with installing the new lister_config system" 