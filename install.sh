#!/bin/bash

# V2
# Define colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Define repository information
# Format: "repo_url:install_dir:branch"
# Define repository information
# Format: "repo_url:install_dir"
declare -A REPOS=(
    ["lister_numpad_macros"]="https://github.com/CWE3D/lister_numpad_macros.git:/home/pi/lister_numpad_macros"
    ["lister_sound_system"]="https://github.com/CWE3D/lister_sound_system.git:/home/pi/lister_sound_system"
    ["lister_printables"]="https://github.com/CWE3D/lister_printables.git:/home/pi/printer_data/gcodes/lister_printables"
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

    local repo_url=${repo_info%:*}
    local repo_dir=${repo_info##*:}

    log_message "INFO" "Processing repository: $name"
    log_message "INFO" "URL: $repo_url"
    log_message "INFO" "Directory: $repo_dir"

    local retry_count=0

    while [ $retry_count -lt $RETRY_LIMIT ]; do
        if [ -d "$repo_dir" ]; then
            if [ -d "$repo_dir/.git" ]; then
                log_message "INFO" "Updating existing repository: $repo_dir"
                (cd "$repo_dir" && \
                 git reset --hard && \
                 git clean -fd && \
                 git fetch origin && \
                 git checkout -f main && \
                 git reset --hard origin/main) && {
                    # Fix permissions after successful update
                    fix_repo_permissions "$repo_dir"
                    INSTALL_STATUS[$name]="SUCCESS"
                    return 0
                }
            fi

            log_message "WARNING" "Update failed, removing directory and trying fresh clone"
            rm -rf "$repo_dir"
        fi

        log_message "INFO" "Cloning repository: $repo_url to $repo_dir"
        if git clone "$repo_url" "$repo_dir"; then
            # Fix permissions after successful clone
            fix_repo_permissions "$repo_dir"
            INSTALL_STATUS[$name]="SUCCESS"
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

    # Check for and run install script
    local install_script="$repo_dir/install.sh"
    if [ -f "$install_script" ]; then
        log_message "INFO" "Running install script for $name"
        # No need for chmod +x here as fix_repo_permissions handles it
        if $install_script; then
            INSTALL_STATUS[$name]="SUCCESS"
            # Fix permissions again after install script runs
            fix_repo_permissions "$repo_dir"
        else
            INSTALL_STATUS[$name]="FAILED_INSTALL"
            log_message "ERROR" "Installation failed for $name"
            # Fix permissions even if install failed
            fix_repo_permissions "$repo_dir"
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

# New function to handle repository permissions
fix_repo_permissions() {
    local repo_dir=$1
    
    # First, set all directories to 755
    find "$repo_dir" -type d -exec chmod 755 {} \;
    
    # Set all files to 644 by default
    find "$repo_dir" -type f -exec chmod 644 {} \;
    
    # Only if it's a git repository
    if [ -d "$repo_dir/.git" ]; then
        (cd "$repo_dir" && {
            # Make sure we're on the right branch
            git checkout -f main
            
            # Set executable bit only for files marked as executable in .gitattributes
            git ls-files --stage | while read mode hash stage file; do
                if [ "$mode" = "100755" ]; then
                    chmod +x "$file"
                fi
            done
        })
    fi

    # Explicitly ensure install.sh and refresh.sh are executable if they exist
    if [ -f "$repo_dir/install.sh" ]; then
        log_message "INFO" "Making install.sh executable in $repo_dir"
        chmod +x "$repo_dir/install.sh"
    fi
    if [ -f "$repo_dir/refresh.sh" ]; then
        log_message "INFO" "Making refresh.sh executable in $repo_dir"
        chmod +x "$repo_dir/refresh.sh"
    fi
    
    # Set ownership after all permission changes
    chown -R pi:pi "$repo_dir"
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

    # Check cron job for lister_printables without modifying permissions
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
            fix_repo_permissions "$repo_dir"
        fi
    done

    # Fix config and log directories without recursive permission change
    log_message "INFO" "Fixing permissions for config and log directories"
    # Set directory permissions first
    chmod 755 "$CONFIG_DIR" "$LOG_DIR"
    
    # Set ownership
    chown pi:pi "$CONFIG_DIR" "$LOG_DIR"
    
    # Handle files in these directories without making them executable
    find "$CONFIG_DIR" "$LOG_DIR" -type f -exec chown pi:pi {} \; -exec chmod 644 {} \;
    find "$CONFIG_DIR" "$LOG_DIR" -type d -exec chown pi:pi {} \; -exec chmod 755 {} \;
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

    # Install Git LFS
    log_message "INFO" "Installing Git LFS"
    if ! command -v git-lfs &> /dev/null; then
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