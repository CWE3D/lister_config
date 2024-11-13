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
INSTALL_LOG="${LOG_DIR}/lister_install.log"
CONFIG_DIR="/home/pi/printer_data/config"
EXPECTED_SCRIPT_PATH="/home/pi/printer_data/config/lister_config/install.sh"

# Installation status tracking
declare -A INSTALL_STATUS
declare -A SERVICE_STATUS
RETRY_LIMIT=3

# Function to verify script location
verify_script_location() {
    local current_script=$(realpath "$0")
    if [ "$current_script" != "$EXPECTED_SCRIPT_PATH" ]; then
        echo -e "${RED}Error: This script must be run from within the lister_config repository${NC}"
        echo -e "${YELLOW}Expected location: ${EXPECTED_SCRIPT_PATH}${NC}"
        echo -e "${YELLOW}Current location: ${current_script}${NC}"
        echo -e "${YELLOW}Please clone lister_config repository first:${NC}"
        echo "git clone https://github.com/CWE3D/lister_config.git /home/pi/printer_data/config/lister_config"
        exit 1
    fi
}

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

    echo -e "${color}${timestamp} [${level}] ${message}${NC}" | tee -a "$INSTALL_LOG"
}

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_message "ERROR" "Please run as root (sudo)"
        exit 1
    fi
}

# Function to create required directories
create_directories() {
    local dirs=(
        "$LOG_DIR"
        "$CONFIG_DIR"
        "/home/pi/printer_data/gcodes"
    )

    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            log_message "INFO" "Creating directory: $dir"
            mkdir -p "$dir"
            chown pi:pi "$dir"
        fi
    done
}

# Function to clone or update a repository
handle_repository() {
       local name=$1
    local repo_info=${REPOS[$name]}

    # Properly split the repository info using : as delimiter
    IFS=':' read -r repo_url repo_dir branch <<< "$repo_info"

    log_message "INFO" "Processing repository: $name (branch: $branch)"

    local retry_count=0

    while [ $retry_count -lt $RETRY_LIMIT ]; do
        if [ -d "$repo_dir" ]; then
            if [ -d "$repo_dir/.git" ]; then
                log_message "INFO" "Updating existing repository: $repo_dir"
                (cd "$repo_dir" && \
                 git reset --hard && \
                 git clean -fd && \
                 git fetch origin && \
                 git checkout -f "$branch" && \
                 git reset --hard "origin/$branch" && \
                 git pull origin "$branch") && return 0
            fi

            # If update fails, remove directory and try fresh clone
            log_message "WARNING" "Update failed, removing directory and trying fresh clone"
            rm -rf "$repo_dir"
        fi

        # Fresh clone
        log_message "INFO" "Cloning repository: $repo_url (branch: $branch)"
        if git clone -b "$branch" "$repo_url" "$repo_dir"; then
            break
        fi

        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $RETRY_LIMIT ]; then
            log_message "WARNING" "Clone failed, retrying... (attempt $retry_count of $RETRY_LIMIT)"
            rm -rf "$repo_dir"
            sleep 5
        else
            log_message "ERROR" "Failed to clone repository after $RETRY_LIMIT attempts"
            INSTALL_STATUS[$name]="FAILED_CLONE"
            return 1
        fi
    done

    # Set correct ownership and permissions
    chown -R pi:pi "$repo_dir"
    chmod -R 755 "$repo_dir"

    # Make install script executable if it exists
    local install_script="$repo_dir/install.sh"
    if [ -f "$install_script" ]; then
        chmod +x "$install_script"
        log_message "INFO" "Running install script for $name"
        if $install_script; then
            INSTALL_STATUS[$name]="SUCCESS"
        else
            INSTALL_STATUS[$name]="FAILED_INSTALL"
            log_message "ERROR" "Installation failed for $name"
            return 1
        fi
    else
        INSTALL_STATUS[$name]="NO_INSTALL_SCRIPT"
        log_message "WARNING" "No install script found for $name"
    fi

    # Check for requirements.txt and install if present
    local req_file="$repo_dir/requirements.txt"
    if [ -f "$req_file" ]; then
        log_message "INFO" "Installing Python requirements for $name"
        if ! pip3 install -r "$req_file"; then
            log_message "ERROR" "Failed to install Python requirements for $name"
            INSTALL_STATUS[$name]="FAILED_REQUIREMENTS"
            return 1
        fi
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

    # Check system services
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            SERVICE_STATUS[$service]="RUNNING"
            log_message "INFO" "Service $service is running"
        else
            SERVICE_STATUS[$service]="STOPPED"
            log_message "ERROR" "Service $service is not running"
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
    log_message "INFO" "Fixing permissions for all installed components"

    # Fix ownership for all repository directories
    for repo_info in "${REPOS[@]}"; do
        local dir=$(echo $repo_info | cut -d':' -f2)
        if [ -d "$dir" ]; then
            log_message "INFO" "Setting permissions for $dir"
            chown -R pi:pi "$dir"
            chmod -R 755 "$dir"

            # Make all .sh files executable
            find "$dir" -type f -name "*.sh" -exec chmod +x {} \;
        fi
    done

    # Fix permissions for config and log directories
    chown -R pi:pi "$CONFIG_DIR" "$LOG_DIR"
    chmod -R 755 "$CONFIG_DIR" "$LOG_DIR"
}

# Function to print installation report
print_report() {
    log_message "INFO" "Installation Report"
    echo "----------------------------------------"
    echo "Repository Status:"
    for repo in "${!INSTALL_STATUS[@]}"; do
        local status=${INSTALL_STATUS[$repo]}
        local color=$GREEN
        [[ $status != "SUCCESS" ]] && color=$RED
        echo -e "${color}$repo: $status${NC}"
    done

    echo -e "\nService Status:"
    for service in "${!SERVICE_STATUS[@]}"; do
        local status=${SERVICE_STATUS[$service]}
        local color=$GREEN
        [[ $status != "RUNNING" && $status != "CONFIGURED" ]] && color=$RED
        echo -e "${color}$service: $status${NC}"
    done
    echo "----------------------------------------"
}

# Main installation process
main() {
    check_root
    log_message "INFO" "Starting Lister configuration installation"

    create_directories

    # Process each repository
    for repo in "${!REPOS[@]}"; do
        handle_repository "$repo"
    done

    # Fix permissions
    fix_permissions

    # Check services
    check_services

    # Print final report
    print_report

    log_message "INFO" "Installation complete"
}

# Run the installation
main