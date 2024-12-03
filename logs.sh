#!/bin/bash

# Define colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Define log files and their descriptions
declare -A LOG_FILES=(
    ["klipper"]="/home/pi/printer_data/logs/klippy.log:Klipper main log"
    ["moonraker"]="/home/pi/printer_data/logs/moonraker.log:Moonraker main log"
    ["lister"]="/home/pi/printer_data/logs/lister_config.log:Lister configuration log (includes numpad and sound system)"
    ["numpad"]="/home/pi/printer_data/logs/numpad_event_service.log:Numpad event service log"
)

# Function to print usage
print_usage() {
    echo -e "${BLUE}Usage: $0 {list|klipper|moonraker|lister|numpad}${NC}"
    echo
    echo "Commands:"
    echo -e "  ${GREEN}list${NC}      List all available log files"
    echo -e "  ${GREEN}klipper${NC}   View Klipper logs"
    echo -e "  ${GREEN}moonraker${NC} View Moonraker logs"
    echo -e "  ${GREEN}lister${NC}    View Lister configuration logs"
    echo -e "  ${GREEN}numpad${NC}    View Numpad event service logs"
    echo
    echo "The logs will show the last 500 lines and then follow any new entries."
}

# Function to list available log files
list_logs() {
    echo -e "${BLUE}Available log files:${NC}"
    echo
    for key in "${!LOG_FILES[@]}"; do
        IFS=':' read -r file desc <<< "${LOG_FILES[$key]}"
        echo -e "${GREEN}$key${NC}"
        echo -e "  File: ${YELLOW}$file${NC}"
        echo -e "  Description: $desc"
        echo
    done
}

# Function to check if file exists and is readable
check_file() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo -e "${RED}Error: Log file not found: $file${NC}"
        return 1
    elif [ ! -r "$file" ]; then
        echo -e "${RED}Error: Log file not readable: $file${NC}"
        return 1
    fi
    return 0
}

# Function to view log
view_log() {
    local key="$1"
    IFS=':' read -r file desc <<< "${LOG_FILES[$key]}"
    
    if ! check_file "$file"; then
        exit 1
    fi
    
    echo -e "${BLUE}Viewing $desc${NC}"
    echo -e "${YELLOW}File: $file${NC}"
    echo -e "${GREEN}Showing last 500 lines and following new entries...${NC}"
    echo
    tail -n 500 -f "$file"
}

# Main script
case "$1" in
    "list")
        list_logs
        ;;
    "klipper"|"moonraker"|"lister"|"numpad")
        view_log "$1"
        ;;
    *)
        print_usage
        exit 1
        ;;
esac 