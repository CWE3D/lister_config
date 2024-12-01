#!/bin/bash

# Update script for lister_numpad_macros plugin.
# Define colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Define paths
REPO_DIR="/home/pi/lister_numpad_macros"
LOG_DIR="/home/pi/printer_data/logs"
UPDATE_LOG="$LOG_DIR/numpad_update.log"

# Function to log messages
log_message() {
    echo -e "${GREEN}$(date): $1${NC}" | tee -a "$UPDATE_LOG"
}

log_error() {
    echo -e "${RED}$(date): $1${NC}" | tee -a "$UPDATE_LOG"
}

log_warning() {
    echo -e "${YELLOW}$(date): $1${NC}" | tee -a "$UPDATE_LOG"
}

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Please run as root (sudo)"
        exit 1
    fi
}

# Function to update repository
update_repo() {
    log_message "Updating numpad macros repository..."

    if [ ! -d "$REPO_DIR" ]; then
        log_message "Repository not found. Cloning..."
        git clone https://github.com/CWE3D/lister_numpad_macros.git "$REPO_DIR"
    else
        cd "$REPO_DIR" || exit 1
        log_message "Resetting repository to clean state..."
        git reset --hard
        git clean -fd
        git fetch
        
        LOCAL=$(git rev-parse @)
        REMOTE=$(git rev-parse @{u})

        if [ "$LOCAL" != "$REMOTE" ]; then
            log_message "Updates found. Pulling changes..."
            git pull
            return 0
        else
            log_message "Already up to date"
            return 1
        fi
    fi
}

# Function to restart services
restart_services() {
    log_message "Restarting services..."

    # Stop services in reverse dependency order
    log_message "Stopping numpad event service..."
    systemctl stop numpad_event_service

    log_message "Stopping Moonraker..."
    systemctl stop moonraker

    log_message "Stopping Klipper..."
    systemctl stop klipper

    # Small delay to ensure clean shutdown
    sleep 2

    # Start services in dependency order
    log_message "Starting Klipper..."
    systemctl start klipper
    sleep 2

    log_message "Starting Moonraker..."
    systemctl start moonraker
    sleep 2

    log_message "Starting numpad event service..."
    systemctl start numpad_event_service
}

# Function to verify services
verify_services() {
    local all_good=true

    # Check each service
    for service in klipper moonraker numpad_event_service; do
        if ! systemctl is-active --quiet "$service"; then
            log_error "$service failed to start"
            all_good=false
        else
            log_message "$service is running"
        fi
    done

    if [ "$all_good" = false ]; then
        log_error "Some services failed to start. Check the logs for details:"
        log_error "- Klipper log: ${LOG_DIR}/klippy.log"
        log_error "- Moonraker log: ${LOG_DIR}/moonraker.log"
        log_error "- Numpad service log: ${LOG_DIR}/numpad_event_service.log"
        return 1
    fi

    return 0
}

# Main update process
main() {
    log_message "Starting numpad macros update process..."

    check_root

    # Update repository
    if update_repo; then
        # Only restart services if there were updates
        verify_services
    else
        log_message "No updates found. Skipping service restart."
    fi

    restart_services

    log_message "Update process completed!"

    # Print verification steps
    echo -e "\n${GREEN}Verify the services:${NC}"
    echo -e "1. Check Klipper status: ${YELLOW}systemctl status klipper${NC}"
    echo -e "2. Check Moonraker status: ${YELLOW}systemctl status moonraker${NC}"
    echo -e "3. Check numpad service status: ${YELLOW}systemctl status numpad_event_service${NC}"
    echo -e "4. View logs: ${YELLOW}tail -f ${LOG_DIR}/{klippy,moonraker,numpad_event_service}.log${NC}"
}

# Run the update
main