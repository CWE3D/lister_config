#!/bin/bash

# Update script for lister_printables plugin.
# Define colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Define paths
REPO_DIR="/home/pi/printer_data/gcodes/lister_printables"
LOG_DIR="/home/pi/printer_data/logs"
UPDATE_LOG="$LOG_DIR/lister_printables_update.log"
SCRIPTS_DIR="$REPO_DIR/scripts"

# Function to log messages with severity
log_message() {
    local severity=$1
    local message=$2
    local color=$GREEN
    
    case $severity in
        "ERROR") color=$RED ;;
        "WARN") color=$YELLOW ;;
        *) color=$GREEN ;;
    esac
    
    echo -e "${color}$(date): [$severity] $message${NC}" | tee -a "$UPDATE_LOG"
}

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_message "ERROR" "Please run as root (sudo)"
        exit 1
    fi
}

# Function to fix permissions
fix_permissions() {
    log_message "INFO" "Fixing permissions for repository"
    
    if [ -d "$REPO_DIR" ]; then
        # First, set all directories to 755
        find "$REPO_DIR" -type d -exec chmod 755 {} \;
        
        # Set all files to 644 by default
        find "$REPO_DIR" -type f -exec chmod 644 {} \;
        
        # Only if it's a git repository
        if [ -d "$REPO_DIR/.git" ]; then
            (cd "$REPO_DIR" && {
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
        
        # Set ownership after all permission changes
        chown -R pi:pi "$REPO_DIR"
    fi

    # Fix log directory permissions
    log_message "INFO" "Fixing permissions for log directory"
    find "$LOG_DIR" -type d -exec chmod 755 {} \;
    find "$LOG_DIR" -type f -exec chmod 644 {} \;
    chown -R pi:pi "$LOG_DIR"
}

# Function to update repository
update_repo() {
    log_message "INFO" "Updating lister printables repository..."

    if [ ! -d "$REPO_DIR" ]; then
        log_message "INFO" "Repository not found. Cloning..."
        git lfs install
        git clone https://github.com/CWE3D/lister_printables.git "$REPO_DIR"
        fix_permissions
    else
        cd "$REPO_DIR" || exit 1
        
        git lfs install
        
        log_message "INFO" "Fetching LFS files..."
        git lfs fetch --all
        git lfs checkout
        
        git fetch

        LOCAL=$(git rev-parse @)
        REMOTE=$(git rev-parse @{u})

        if [ "$LOCAL" != "$REMOTE" ]; then
            log_message "INFO" "Updates found. Pulling changes..."
            git reset --hard
            git clean -fd
            git pull --force
            
            git lfs fetch --all
            git lfs checkout
            
            fix_permissions
            return 0
        else
            log_message "INFO" "Already up to date"
            return 1
        fi
    fi
}

# Function to update metadata
update_metadata() {
    log_message "INFO" "Updating printables metadata..."
    if [ -f "$SCRIPTS_DIR/update_lister_metadata.py" ]; then
        python3 "$SCRIPTS_DIR/update_lister_metadata.py"
    else
        log_message "ERROR" "Metadata update script not found"
        return 1
    fi
}

# Main update process
main() {
    log_message "INFO" "Starting lister printables update process..."

    check_root

    # Update repository
    if update_repo; then
        update_metadata
    else
        log_message "INFO" "No updates found. Skipping metadata update."
    fi

    # Final permission check
    fix_permissions

    log_message "INFO" "Update process completed!"

    # Print verification steps
    echo -e "\n${GREEN}Verify the update:${NC}"
    echo -e "1. Check metadata logs: ${YELLOW}tail -f ${LOG_DIR}/lister_printables_metadata.log${NC}"
    echo -e "2. Verify printables directory: ${YELLOW}ls -l ${REPO_DIR}${NC}"
}

# Run the update
main