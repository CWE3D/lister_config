#!/bin/bash

# Define colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Define repository information
# Format: "repo_url:install_dir:branch"
declare -A REPOS=(
    ["lister_numpad_macros"]="https://github.com/CWE3D/lister_numpad_macros.git:/home/pi/lister_numpad_macros:main"
    ["lister_sound_system"]="https://github.com/CWE3D/lister_sound_system.git:/home/pi/lister_sound_system:main"
    ["lister_printables"]="https://github.com/CWE3D/lister_printables.git:/home/pi/printer_data/gcodes/lister_printables:main"
)

# Define paths
LOG_DIR="/home/pi/printer_data/logs"
REFRESH_LOG="${LOG_DIR}/lister_refresh.log"
CONFIG_DIR="/home/pi/printer_data/config"
EXPECTED_SCRIPT_PATH="/home/pi/printer_data/config/lister_config/refresh.sh"

# Status tracking
declare -A REPO_STATUS
declare -A SERVICE_STATUS
declare -A UPDATE_STATUS

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

    echo -e "${color}${timestamp} [${level}] ${message}${NC}" | tee -a "$REFRESH_LOG"
}

# Function to verify script location
verify_script_location() {
    local current_script=$(realpath "$0")
    if [ "$current_script" != "$EXPECTED_SCRIPT_PATH" ]; then
        echo -e "${RED}Error: This script must be run from within the lister_config repository${NC}"
        echo -e "${YELLOW}Expected location: ${EXPECTED_SCRIPT_PATH}${NC}"
        exit 1
    fi
}

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_message "ERROR" "Please run as root (sudo)"
        exit 1
    fi
}

# Function to check for repository updates
check_repository() {
    local name=$1
    local repo_info=${REPOS[$name]}
    local repo_dir=$(echo $repo_info | cut -d':' -f2)
    local branch=$(echo $repo_info | cut -d':' -f3)

    if [ ! -d "$repo_dir/.git" ]; then
        REPO_STATUS[$name]="MISSING"
        log_message "ERROR" "Repository $name not found at $repo_dir"
        return 1
    fi

    # Store original HEAD
    local original_head=$(cd "$repo_dir" && git rev-parse HEAD)

    # Fetch updates
    (cd "$repo_dir" && \
     git fetch origin "$branch" && \
     git reset --hard "origin/$branch") || {
        REPO_STATUS[$name]="FETCH_FAILED"
        log_message "ERROR" "Failed to fetch updates for $name"
        return 1
    }

    # Check if there were updates
    local new_head=$(cd "$repo_dir" && git rev-parse HEAD)
    if [ "$original_head" != "$new_head" ]; then
        UPDATE_STATUS[$name]="UPDATED"
        log_message "INFO" "Repository $name updated"

        # Check for requirements.txt and install if present
        local req_file="$repo_dir/requirements.txt"
        if [ -f "$req_file" ]; then
            log_message "INFO" "Installing updated Python requirements for $name"
            pip3 install -r "$req_file"
        fi

        # Run install script if it exists
        local install_script="$repo_dir/install.sh"
        if [ -f "$install_script" ]; then
            log_message "INFO" "Running install script for $name"
            chmod +x "$install_script"
            if $install_script; then
                REPO_STATUS[$name]="UPDATED"
            else
                REPO_STATUS[$name]="INSTALL_FAILED"
                log_message "ERROR" "Install script failed for $name"
                return 1
            fi
        else
            REPO_STATUS[$name]="UPDATED"
        fi
    else
        UPDATE_STATUS[$name]="UNCHANGED"
        REPO_STATUS[$name]="CURRENT"
        log_message "INFO" "Repository $name is up to date"
    fi

    return 0
}

# Function to check service status
check_services() {
    local services=(
        "klipper"
        "moonraker"
        "numpad_event_service"
    )

    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            SERVICE_STATUS[$service]="RUNNING"
            log_message "INFO" "Service $service is running"
        else
            SERVICE_STATUS[$service]="STOPPED"
            log_message "ERROR" "Service $service is not running"
            # Attempt to restart service
            log_message "INFO" "Attempting to restart $service"
            systemctl restart "$service"
            sleep 2
            if systemctl is-active --quiet "$service"; then
                SERVICE_STATUS[$service]="RESTARTED"
                log_message "INFO" "Successfully restarted $service"
            else
                log_message "ERROR" "Failed to restart $service"
            fi
        fi
    done

    # Check cron job for lister_printables
    if crontab -u pi -l 2>/dev/null | grep -q "update_lister_metadata.py"; then
        SERVICE_STATUS["printables_cron"]="CONFIGURED"
        log_message "INFO" "Printables cron job is configured"
    else
        SERVICE_STATUS["printables_cron"]="MISSING"
        log_message "ERROR" "Printables cron job is missing"
    fi
}

# Function to fix permissions
fix_permissions() {
    log_message "INFO" "Checking and fixing permissions"

    for repo_info in "${REPOS[@]}"; do
        local dir=$(echo $repo_info | cut -d':' -f2)
        if [ -d "$dir" ]; then
            log_message "INFO" "Setting permissions for $dir"
            chown -R pi:pi "$dir"
            chmod -R 755 "$dir"
            find "$dir" -type f -name "*.sh" -exec chmod +x {} \;
        fi
    done
}

# Function to print status report
print_report() {
    log_message "INFO" "Refresh Status Report"
    echo "----------------------------------------"
    echo "Repository Status:"
    for repo in "${!REPO_STATUS[@]}"; do
        local status=${REPO_STATUS[$repo]}
        local update=${UPDATE_STATUS[$repo]}
        local color=$GREEN
        [[ $status != "CURRENT" && $status != "UPDATED" ]] && color=$RED
        echo -e "${color}$repo: $status ($update)${NC}"
    done

    echo -e "\nService Status:"
    for service in "${!SERVICE_STATUS[@]}"; do
        local status=${SERVICE_STATUS[$service]}
        local color=$GREEN
        [[ $status != "RUNNING" && $status != "RESTARTED" && $status != "CONFIGURED" ]] && color=$RED
        echo -e "${color}$service: $status${NC}"
    done
    echo "----------------------------------------"
}

# Main refresh process
main() {
    check_root
    verify_script_location
    log_message "INFO" "Starting Lister configuration refresh"

    # Check and update repositories
    for repo in "${!REPOS[@]}"; do
        check_repository "$repo"
    done

    # Fix permissions
    fix_permissions

    # Check and fix services
    check_services

    # Print status report
    print_report

    log_message "INFO" "Refresh complete"
}

# Run the refresh
main