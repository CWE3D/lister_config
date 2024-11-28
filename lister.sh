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
EXPECTED_SCRIPT_PATH="/home/pi/printer_data/config/lister_config/lister.sh"
RETRY_LIMIT=3

# Status tracking
declare -A REPO_STATUS
declare -A SERVICE_STATUS
declare -A UPDATE_STATUS

# Function to configure Git settings
configure_git() {
    log_message "INFO" "Configuring Git settings"
    
    # Configure global Git settings
    git config --global core.fileMode true
    git config --global core.autocrlf input
    
    # Verify configurations
    local fileMode=$(git config --global core.fileMode)
    local autoCRLF=$(git config --global core.autocrlf)
    
    if [ "$fileMode" = "true" ] && [ "$autoCRLF" = "input" ]; then
        log_message "INFO" "Git configurations set successfully"
    else
        log_message "WARNING" "Git configurations may not have been set correctly"
        log_message "INFO" "core.fileMode: $fileMode"
        log_message "INFO" "core.autocrlf: $autoCRLF"
    fi
}

# Function to log messages
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

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_message "ERROR" "Please run as root (sudo)"
        exit 1
    fi
}

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

# Function to create required directories (install only)
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
            chmod 755 "$dir"
            chown pi:pi "$dir"
        fi
    done
}

# Function to install Git LFS (install only)
install_git_lfs() {
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
        
        # Force reset any local changes before updating
        (cd "$repo_dir" && {
            git reset --hard
            git clean -fd
            git fetch origin
            git checkout -f main
            git reset --hard origin/main
        }) || {
            REPO_STATUS[$name]="UPDATE_FAILED"
            UPDATE_STATUS[$name]="ERROR"
            return 1
        }
        
        local new_head=$(cd "$repo_dir" && git rev-parse HEAD)
        
        if [ "$original_head" != "$new_head" ]; then
            UPDATE_STATUS[$name]="UPDATED"
            REPO_STATUS[$name]="UPDATED"
        else
            UPDATE_STATUS[$name]="UNCHANGED"
            REPO_STATUS[$name]="CURRENT"
        fi
        return 0
    fi
}

# Function to handle repository scripts
handle_repo_scripts() {
    local name=$1
    local repo_dir=$2

    # Check for and run install/refresh script
    local script_name="${MODE}.sh"
    local script_path="$repo_dir/$script_name"
    
    if [ -f "$script_path" ]; then
        log_message "INFO" "Running $script_name for $name"
        if $script_path; then
            REPO_STATUS[$name]="SUCCESS"
            fix_repo_permissions "$repo_dir"
        else
            REPO_STATUS[$name]="FAILED_SCRIPT"
            log_message "ERROR" "$script_name failed for $name"
            fix_repo_permissions "$repo_dir"
            return 1
        fi
    fi

    # Check for requirements.txt and install if present
    local req_file="$repo_dir/requirements.txt"
    if [ -f "$req_file" ]; then
        log_message "INFO" "Installing Python requirements for $name"
        if ! pip3 install -r "$req_file"; then
            log_message "ERROR" "Failed to install Python requirements for $name"
            REPO_STATUS[$name]="FAILED_REQUIREMENTS"
            return 1
        fi
    fi

    return 0
}

# Function to fix repository permissions
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

    # Explicitly ensure our scripts are executable
    if [ -f "$repo_dir/install.sh" ]; then
        log_message "INFO" "Making install.sh executable in $repo_dir"
        chmod +x "$repo_dir/install.sh"
    fi
    if [ -f "$repo_dir/refresh.sh" ]; then
        log_message "INFO" "Making refresh.sh executable in $repo_dir"
        chmod +x "$repo_dir/refresh.sh"
    fi
    if [ -f "$repo_dir/lister.sh" ]; then
        log_message "INFO" "Making lister.sh executable in $repo_dir"
        chmod +x "$repo_dir/lister.sh"
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

    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            SERVICE_STATUS[$service]="RUNNING"
            log_message "INFO" "Service $service is running"
        else
            SERVICE_STATUS[$service]="STOPPED"
            log_message "ERROR" "Service $service is not running"
            
            # Attempt to restart service in refresh mode
            if [ "$MODE" = "refresh" ]; then
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

# Function to print status report
print_report() {
    log_message "INFO" "${MODE^} Status Report"
    echo "----------------------------------------"
    echo "Repository Status:"
    for repo in "${!REPO_STATUS[@]}"; do
        local status=${REPO_STATUS[$repo]}
        local update=${UPDATE_STATUS[$repo]}
        local color=$GREEN
        [[ $status != "SUCCESS" ]] && color=$RED
        if [ "$MODE" = "refresh" ]; then
            echo -e "${color}$repo: $status ($update)${NC}"
        else
            echo -e "${color}$repo: $status${NC}"
        fi
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
        handle_repository "lister_config" || {
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

    # Final check to ensure lister.sh remains executable
    if [ -f "$EXPECTED_SCRIPT_PATH" ]; then
        log_message "INFO" "Ensuring lister.sh remains executable"
        chmod +x "$EXPECTED_SCRIPT_PATH"
    fi

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