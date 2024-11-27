#!/bin/bash

# Define colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Define repository information
# Format: "repo_url:install_dir"
declare -A REPOS=(
    ["lister_numpad_macros"]="https://github.com/CWE3D/lister_numpad_macros.git:/home/pi/lister_numpad_macros"
    ["lister_sound_system"]="https://github.com/CWE3D/lister_sound_system.git:/home/pi/lister_sound_system"
    ["lister_printables"]="https://github.com/CWE3D/lister_printables.git:/home/pi/printer_data/gcodes/lister_printables"
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

    # Use the same URL parsing as install.sh
    local repo_url=${repo_info%:*}
    local repo_dir=${repo_info##*:}

    log_message "INFO" "Checking repository: $name"
    log_message "INFO" "Directory: $repo_dir"

    if [ ! -d "$repo_dir/.git" ]; then
        REPO_STATUS[$name]="MISSING"
        log_message "ERROR" "Repository $name not found at $repo_dir"
        return 1
    fi

    # Store original HEAD
    local original_head=$(cd "$repo_dir" && git rev-parse HEAD)

    # Fetch updates
    (cd "$repo_dir" && \
     git fetch origin && \
     git reset --hard "origin/main") || {
        REPO_STATUS[$name]="FETCH_FAILED"
        log_message "ERROR" "Failed to fetch updates for $name"
        return 1
    }

    # Fix permissions after git operations
    chown -R pi:pi "$repo_dir"
    chmod -R 755 "$repo_dir"

    # Check if there were updates
    local new_head=$(cd "$repo_dir" && git rev-parse HEAD)
    if [ "$original_head" != "$new_head" ]; then
        UPDATE_STATUS[$name]="UPDATED"
        log_message "INFO" "Repository $name updated"

        # Check for and run refresh script if it exists
        local refresh_script="$repo_dir/refresh.sh"
        if [ -f "$refresh_script" ]; then
            log_message "INFO" "Running refresh script for $name"
            chmod +x "$refresh_script"
            if $refresh_script; then
                log_message "INFO" "Refresh script completed successfully for $name"
            else
                REPO_STATUS[$name]="REFRESH_FAILED"
                log_message "ERROR" "Refresh script failed for $name"
                return 1
            fi
        fi

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
                # Fix permissions after install script
                log_message "INFO" "Fixing permissions after install script"
                chown -R pi:pi "$repo_dir"
                chmod -R 755 "$repo_dir"
            else
                REPO_STATUS[$name]="INSTALL_FAILED"
                log_message "ERROR" "Install script failed for $name"
                # Fix permissions even if install failed
                chown -R pi:pi "$repo_dir"
                chmod -R 755 "$repo_dir"
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
    log_message "INFO" "Running final permission check for all components"

    for repo_info in "${REPOS[@]}"; do
        local repo_dir=${repo_info##*:}
        if [ -d "$repo_dir" ]; then
            log_message "INFO" "Final permission check for $repo_dir"
            # Fix owner and group recursively
            chown -R pi:pi "$repo_dir"
            # Fix directory permissions
            find "$repo_dir" -type d -exec chmod 755 {} \;
            # Fix file permissions
            find "$repo_dir" -type f -exec chmod 644 {} \;
            # Make shell scripts executable
            find "$repo_dir" -type f -name "*.sh" -exec chmod +x {} \;
        fi
    done

    # Fix config and log directories
    log_message "INFO" "Fixing permissions for config and log directories"
    chown -R pi:pi "$CONFIG_DIR" "$LOG_DIR"
    chmod -R 755 "$CONFIG_DIR" "$LOG_DIR"
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

    # Check Git LFS installation
    log_message "INFO" "Checking Git LFS"
    if ! command -v git-lfs &> /dev/null; then
        log_message "INFO" "Installing Git LFS"
        apt-get update && apt-get install -y git-lfs || {
            log_message "ERROR" "Failed to install Git LFS"
            exit 1
        }
        log_message "INFO" "Git LFS installed successfully"
    else
        log_message "INFO" "Git LFS is already installed"
    fi

    # Initialize Git LFS
    git lfs install || {
        log_message "ERROR" "Failed to initialize Git LFS"
        exit 1
    }
    log_message "INFO" "Git LFS initialized successfully"

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