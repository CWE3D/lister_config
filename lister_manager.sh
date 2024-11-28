#!/bin/bash

# Define colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Define repository information based on mode
declare -A REPOS
setup_repositories() {
    if [ "$MODE" = "install" ]; then
        # Install mode excludes lister_config as it's the running script
        REPOS=(
            ["lister_numpad_macros"]="https://github.com/CWE3D/lister_numpad_macros.git:/home/pi/lister_numpad_macros"
            ["lister_sound_system"]="https://github.com/CWE3D/lister_sound_system.git:/home/pi/lister_sound_system"
            ["lister_printables"]="https://github.com/CWE3D/lister_printables.git:/home/pi/printer_data/gcodes/lister_printables"
        )
    else
        # Refresh mode includes all repositories
        REPOS=(
            ["lister_config"]="https://github.com/CWE3D/lister_config.git:/home/pi/printer_data/config/lister_config"
            ["lister_numpad_macros"]="https://github.com/CWE3D/lister_numpad_macros.git:/home/pi/lister_numpad_macros"
            ["lister_sound_system"]="https://github.com/CWE3D/lister_sound_system.git:/home/pi/lister_sound_system"
            ["lister_printables"]="https://github.com/CWE3D/lister_printables.git:/home/pi/printer_data/gcodes/lister_printables"
        )
    fi
}

# Define paths
LOG_DIR="/home/pi/printer_data/logs"
CONFIG_DIR="/home/pi/printer_data/config"
EXPECTED_SCRIPT_PATH="/home/pi/printer_data/config/lister_config/lister_manager.sh"
RETRY_LIMIT=3

# Unified status tracking
declare -A REPO_STATUS
declare -A SERVICE_STATUS
declare -A UPDATE_STATUS

# Function to log messages with mode-specific log file
log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local color=""
    local log_file="${LOG_DIR}/lister_${MODE}.log"

    case $level in
        "INFO") color=$GREEN ;;
        "ERROR") color=$RED ;;
        "WARNING") color=$YELLOW ;;
        *) color=$NC ;;
    esac

    echo -e "${color}${timestamp} [${level}] ${message}${NC}" | tee -a "$log_file"
}

# Function to handle repository operations
handle_repository() {
    local name=$1
    local repo_info=${REPOS[$name]}
    local repo_url=${repo_info%:*}
    local repo_dir=${repo_info##*:}
    local retry_count=0

    log_message "INFO" "Processing repository: $name"
    log_message "INFO" "URL: $repo_url"
    log_message "INFO" "Directory: $repo_dir"

    # Store original HEAD if repository exists
    local original_head=""
    [ -d "$repo_dir/.git" ] && original_head=$(cd "$repo_dir" && git rev-parse HEAD)

    if [ "$MODE" = "install" ]; then
        # Installation logic with retry
        while [ $retry_count -lt $RETRY_LIMIT ]; do
            if [ -d "$repo_dir/.git" ]; then
                handle_existing_repo "$name" "$repo_dir" && return 0
            fi
            handle_new_repo "$name" "$repo_url" "$repo_dir" && return 0
            
            retry_count=$((retry_count + 1))
            [ $retry_count -lt $RETRY_LIMIT ] && sleep 5
        done
        REPO_STATUS[$name]="FAILED"
        return 1
    else
        # Refresh logic
        if [ ! -d "$repo_dir/.git" ]; then
            REPO_STATUS[$name]="MISSING"
            UPDATE_STATUS[$name]="NONE"
            return 1
        fi
        
        handle_existing_repo "$name" "$repo_dir"
        local new_head=$(cd "$repo_dir" && git rev-parse HEAD)
        
        if [ "$original_head" != "$new_head" ]; then
            UPDATE_STATUS[$name]="UPDATED"
        else
            UPDATE_STATUS[$name]="UNCHANGED"
        fi
        return 0
    fi
}

# Function to check services with mode-specific behavior
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
            
            # Only attempt restart in refresh mode
            if [ "$MODE" = "refresh" ]; then
                log_message "INFO" "Attempting to restart $service"
                systemctl restart "$service"
                sleep 2
                if systemctl is-active --quiet "$service"; then
                    SERVICE_STATUS[$service]="RESTARTED"
                    log_message "INFO" "Successfully restarted $service"
                fi
            fi
        fi
    done
}

# Main process
main() {
    check_root
    verify_script_location
    setup_repositories
    
    log_message "INFO" "Starting Lister configuration ${MODE}"

    # Configure Git settings
    configure_git

    # Installation-specific tasks
    if [ "$MODE" = "install" ]; then
        create_directories
        install_git_lfs
    fi

    # Process repositories
    if [ "$MODE" = "refresh" ]; then
        # Handle lister_config first in refresh mode
        check_repository "lister_config" || {
            log_message "ERROR" "Failed to update lister_config repository. Aborting."
            exit 1
        }
    fi

    # Process remaining repositories
    for repo in "${!REPOS[@]}"; do
        [ "$MODE" = "refresh" ] && [ "$repo" = "lister_config" ] && continue
        handle_repository "$repo"
    done

    fix_permissions
    check_services
    print_report

    log_message "INFO" "${MODE^} complete"
}

# Script entry point
case "$1" in
    "install"|"refresh")
        MODE="$1"
        main
        ;;
    *)
        echo "Usage: $0 {install|refresh}"
        exit 1
        ;;
esac 