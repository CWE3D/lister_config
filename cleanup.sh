#!/bin/bash

# Define colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Define paths
CONFIG_DIR="/home/pi/printer_data/config"
LOG_DIR="/home/pi/printer_data/logs"
LOG_FILE="${LOG_DIR}/lister_config.log"

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
    local component="${3:-CLEANUP}"

    case $level in
        "INFO") color=$GREEN ;;
        "ERROR") color=$RED ;;
        "WARNING") color=$YELLOW ;;
        *) color=$NC ;;
    esac

    echo -e "${color}${timestamp} [${level}] [${component}] ${message}${NC}" | tee -a "$LOG_FILE"
}

# Function to clean up legacy installation
cleanup_legacy() {
    log_message "INFO" "Starting legacy cleanup..." "CLEANUP"
    
    # Stop related services
    log_message "INFO" "Stopping services..." "CLEANUP"
    systemctl stop numpad_event_service klipper moonraker
    
    # Remove old files and directories
    for path in "${OLD_PATHS[@]}"; do
        if [ -L "$path" ]; then
            # It's a symlink
            log_message "INFO" "Removing symlink: $path" "CLEANUP"
            rm -f "$path"
        elif [ -d "$path" ]; then
            # It's a directory
            log_message "INFO" "Removing directory: $path" "CLEANUP"
            rm -rf "$path"
        elif [ -f "$path" ]; then
            # It's a regular file
            log_message "INFO" "Removing file: $path" "CLEANUP"
            rm -f "$path"
        else
            log_message "WARNING" "Path not found: $path" "CLEANUP"
        fi
    done
    
    # Remove old cron jobs
    log_message "INFO" "Removing old cron jobs..." "CLEANUP"
    (crontab -l 2>/dev/null | grep -v "update_lister_metadata.py") | crontab -
    
    # Reload systemd to remove old service
    log_message "INFO" "Reloading systemd..." "CLEANUP"
    systemctl daemon-reload
    
    # Restart services
    log_message "INFO" "Starting services..." "CLEANUP"
    systemctl start klipper
    sleep 2
    systemctl start moonraker
    
    log_message "INFO" "Legacy cleanup completed" "CLEANUP"
}

# Function to clean up config files
cleanup_config() {
    log_message "INFO" "Starting config cleanup..." "CLEANUP"
    
    # Remove old macro files (with dashes)
    rm -f "${CONFIG_DIR}/lister_config/macros/macros-base.cfg"
    rm -f "${CONFIG_DIR}/lister_config/macros/macros-probe.cfg"
    rm -f "${CONFIG_DIR}/lister_config/macros/macros-homing.cfg"
    rm -f "${CONFIG_DIR}/lister_config/macros/macros.cfg"
    rm -f "${CONFIG_DIR}/lister_config/macros/numpad-macros.cfg"
    
    # Remove new macro files (with underscores)
    rm -f "${CONFIG_DIR}/lister_config/macros/macros_base.cfg"
    rm -f "${CONFIG_DIR}/lister_config/macros/macros_probe.cfg"
    rm -f "${CONFIG_DIR}/lister_config/macros/macros_homing.cfg"
    rm -f "${CONFIG_DIR}/lister_config/macros/macros.cfg"
    rm -f "${CONFIG_DIR}/lister_config/macros/numpad_macros.cfg"
    
    # Remove other config files
    rm -f "${CONFIG_DIR}/lister_printer.cfg"
    rm -f "${CONFIG_DIR}/lister_moonraker.cfg"
    
    # Remove directories if empty
    rmdir "${CONFIG_DIR}/lister_config/macros" 2>/dev/null || true
    rmdir "${CONFIG_DIR}/lister_config" 2>/dev/null || true
    rmdir "${CONFIG_DIR}/.theme" 2>/dev/null || true
    
    log_message "INFO" "Config cleanup completed" "CLEANUP"
}

# Function to clean up logs
cleanup_logs() {
    log_message "INFO" "Starting log cleanup..." "CLEANUP"
    
    # Remove log files
    rm -f "${LOG_DIR}/lister_config.log"
    rm -f "${LOG_DIR}/numpad_event_service.log"
    
    log_message "INFO" "Log cleanup completed" "CLEANUP"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_message "ERROR" "Please run as root (sudo)" "CLEANUP"
    exit 1
fi

# Main process
main() {
    log_message "INFO" "Starting cleanup process" "CLEANUP"
    
    case "$1" in
        "config")
            cleanup_config
            ;;
        "logs")
            cleanup_logs
            ;;
        "legacy")
            cleanup_legacy
            ;;
        "all")
            cleanup_legacy
            cleanup_config
            cleanup_logs
            ;;
        *)
            echo "Usage: $0 {config|logs|legacy|all}"
            exit 1
            ;;
    esac
    
    log_message "INFO" "Cleanup process completed" "CLEANUP"
}

# Script entry point
if [ "$1" == "" ]; then
    echo "Usage: $0 {config|logs|legacy|all}"
    exit 1
fi

main "$1" 