#!/bin/bash

# Define colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Define paths
LISTER_CONFIG_DIR="/home/pi/lister_config"
CONFIG_DIR="/home/pi/printer_data/config"
LOG_DIR="/home/pi/printer_data/logs"
LOG_FILE="${LOG_DIR}/lister_config.log"
KLIPPER_DIR="/home/pi/klipper"
MOONRAKER_DIR="/home/pi/moonraker"
KLIPPY_ENV="/home/pi/klippy-env"
MOONRAKER_ENV="/home/pi/moonraker-env"
EXPECTED_SCRIPT_PATH="/home/pi/lister_config/lister.sh"

# Component paths
PRINTABLES_DIR="${LISTER_CONFIG_DIR}/lister_printables"
SOUND_DIR="${LISTER_CONFIG_DIR}/lister_sound_system"
SOUND_FILES_DIR="${SOUND_DIR}/sounds"
SOUND_MP3_DIR="${SOUND_FILES_DIR}/mp3"
SOUND_WAV_DIR="${SOUND_FILES_DIR}/wav"
NUMPAD_DIR="${LISTER_CONFIG_DIR}/lister_numpad_macros"
SERVICE_FILE="${NUMPAD_DIR}/extras/numpad_event_service.service"

# Installation directories
PRINTABLES_INSTALL_DIR="/home/pi/printer_data/gcodes/lister_printables"

# Status tracking
declare -A SERVICE_STATUS

# Define paths
PRINTABLES_SCRIPTS_DIR="${PRINTABLES_DIR}/scripts"
UPDATE_CLIENT_SCRIPT="${PRINTABLES_SCRIPTS_DIR}/update_client.py"

# Function to verify printables setup
verify_printables_setup() {
    log_message "INFO" "Verifying printables setup..." "INSTALL"
    
    # Create required directories first
    mkdir -p "$PRINTABLES_INSTALL_DIR"
    mkdir -p "$PRINTABLES_SCRIPTS_DIR"
    
    # Check required directories
    local required_dirs=(
        "$PRINTABLES_DIR"
        "$PRINTABLES_INSTALL_DIR"
        "$PRINTABLES_SCRIPTS_DIR"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            log_message "ERROR" "Required directory not found: $dir" "INSTALL"
            return 1
        fi
    done
    
    # Check required scripts
    local required_scripts=(
        "$UPDATE_CLIENT_SCRIPT"
    )
    
    for script in "${required_scripts[@]}"; do
        if [ ! -f "$script" ]; then
            log_message "ERROR" "Required script not found: $script" "INSTALL"
            return 1
        fi
    done
    
    return 0
}

# Function to log messages
log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local color=""
    local component="${3:-MAIN}"  # Optional third parameter for component name

    case $level in
        "INFO") color=$GREEN ;;
        "ERROR") color=$RED ;;
        "WARNING") color=$YELLOW ;;
        *) color=$NC ;;
    esac

    echo -e "${color}${timestamp} [${level}] [${component}] ${message}${NC}" | tee -a "$LOG_FILE"
}

# Function to install system dependencies
install_system_deps() {
    log_message "INFO" "Installing system dependencies..." "INSTALL"
    apt-get update
    apt-get install -y git-lfs alsa-utils python3-pip mpv
}

# Function to install Python requirements
install_python_deps() {
    log_message "INFO" "Installing Python requirements..." "INSTALL"
    
    local req_file="${LISTER_CONFIG_DIR}/requirements.txt"
    
    if [ ! -f "$req_file" ]; then
        log_message "ERROR" "Requirements file not found at $req_file" "INSTALL"
        return 1
    fi
    
    # Install in each environment
    for env in "system" "klippy" "moonraker"; do
        log_message "INFO" "Installing in $env environment..." "INSTALL"
        case $env in
            "system")
                pip3 install -r "$req_file"
                ;;
            "klippy")
                "${KLIPPY_ENV}/bin/pip" install -r "$req_file"
                ;;
            "moonraker")
                "${MOONRAKER_ENV}/bin/pip" install -r "$req_file"
                ;;
        esac
    done
}

# Function to sync config files
sync_config_files() {
    log_message "INFO" "Syncing configuration files..." "INSTALL"
    
    # Create required config directories if they don't exist
    mkdir -p "${CONFIG_DIR}/lister_config/macros"
    mkdir -p "${CONFIG_DIR}/.theme"
    
    # Function to sync with change detection
    sync_with_check() {
        local src="$1"
        local dst="$2"
        local desc="$3"
        
        # Use rsync in dry-run mode first to check for changes
        if rsync -avn --update --modify-window=1 "$src" "$dst" | grep -q '^>f'; then
            log_message "INFO" "Changes detected in ${desc}, syncing..." "INSTALL"
            if ! rsync -av --update --modify-window=1 "$src" "$dst"; then
                log_message "ERROR" "Failed to sync ${desc}" "INSTALL"
                return 1
            fi
        else
            log_message "INFO" "No changes detected in ${desc}, skipping" "INSTALL"
        fi
        return 0
    }
    
    # Sync each component with change detection
    sync_with_check "${PRINTABLES_DIR}/gcodes/" "$PRINTABLES_INSTALL_DIR/" "printables files" || return 1
    
    # Sync specific root config files
    sync_with_check "${LISTER_CONFIG_DIR}/lister_printer.cfg" "${CONFIG_DIR}/" "lister_printer.cfg" || return 1
    sync_with_check "${LISTER_CONFIG_DIR}/lister_moonraker.cfg" "${CONFIG_DIR}/" "lister_moonraker.cfg" || return 1
    
    # Sync other config files
    sync_with_check "${LISTER_CONFIG_DIR}/config/"*.cfg "${CONFIG_DIR}/lister_config/" "lister config files" || return 1
    sync_with_check "${LISTER_CONFIG_DIR}/macros/"*.cfg "${CONFIG_DIR}/lister_config/macros/" "macro config files" || return 1
    sync_with_check "${LISTER_CONFIG_DIR}/lister_theme/" "${CONFIG_DIR}/.theme/" "theme files" || return 1
    
    log_message "INFO" "Config sync completed" "INSTALL"
    return 0
}

# Function to setup symlinks
setup_symlinks() {
    log_message "INFO" "Setting up component symlinks..." "INSTALL"
    
    # Numpad macros links (remove the incorrect symlink)
    ln -sf "${NUMPAD_DIR}/components/numpad_macros.py" \
        "${MOONRAKER_DIR}/moonraker/components/numpad_macros.py"
    
    # Sound system links
    ln -sf "${SOUND_DIR}/extras/sound_system.py" \
        "${KLIPPER_DIR}/klippy/extras/sound_system.py"
    ln -sf "${SOUND_DIR}/components/sound_system_service.py" \
        "${MOONRAKER_DIR}/moonraker/components/sound_system_service.py"
        
    # Z Force Move link
    ln -sf "${LISTER_CONFIG_DIR}/extras/z_force_move.py" \
        "${KLIPPER_DIR}/klippy/extras/z_force_move.py"
        
    # Reload systemd after setting up symlinks
    systemctl daemon-reload
}

# Function to setup services
setup_services() {
    log_message "INFO" "Setting up services..." "INSTALL"
    
    # Load required kernel module
    modprobe uinput
    
    # Add module to load at boot
    if ! grep -q "uinput" /etc/modules; then
        echo "uinput" >> /etc/modules
    fi
    
    # Setup symlinks first
    setup_symlinks
    
    # Then setup numpad event service
    ln -sf "$SERVICE_FILE" \
        "/etc/systemd/system/numpad_event_service.service"
    
    # Reload systemd right after creating the service symlink
    systemctl daemon-reload
    systemctl enable numpad_event_service.service
    
    # Verify setup after everything is in place
    verify_numpad_setup || {
        log_message "ERROR" "Numpad setup verification failed" "INSTALL"
        return 1
    }
}

# Function to fix permissions
fix_permissions() {
    log_message "INFO" "Setting permissions..." "INSTALL"
    
    # Add user pi to input group
    usermod -a -G input pi
    
    # Fix directory permissions
    find "$LISTER_CONFIG_DIR" -type d -exec chmod 755 {} \;
    find "$LISTER_CONFIG_DIR" -type f -exec chmod 644 {} \;
    
    # Make scripts executable
    chmod +x "${LISTER_CONFIG_DIR}/lister.sh"
    chmod +x "${PRINTABLES_DIR}/scripts/"*.py
    chmod +x "${LISTER_CONFIG_DIR}/extras/z_force_move.py"  # Make z_force_move executable
    
    # Set ownership
    chown -R pi:pi "$LISTER_CONFIG_DIR"
    chown -R pi:pi "$CONFIG_DIR"
    chown -R pi:pi "$LOG_DIR"
    chown -R pi:pi "$PRINTABLES_INSTALL_DIR"
    
    # Fix symlink permissions
    chown -h pi:pi "${KLIPPER_DIR}/klippy/extras/"*.py
    chown -h pi:pi "${MOONRAKER_DIR}/moonraker/components/"*.py
}

# Function to restart services
restart_services() {
    log_message "INFO" "Restarting services..." "INSTALL"
    
    systemctl restart klipper
    sleep 2
    systemctl restart moonraker
    sleep 2
    systemctl restart numpad_event_service
}

# Function to verify services
verify_services() {
    local all_good=true

    # Check numpad component
    if [ ! -L "${MOONRAKER_DIR}/moonraker/components/numpad_macros.py" ]; then
        log_message "ERROR" "Numpad Moonraker component not installed" "INSTALL"
        all_good=false
    else
        # Also verify the symlink points to the correct file
        local target=$(readlink -f "${MOONRAKER_DIR}/moonraker/components/numpad_macros.py")
        local expected="${NUMPAD_DIR}/components/numpad_macros.py"
        if [ "$target" != "$expected" ]; then
            log_message "ERROR" "Numpad component symlink points to wrong location: $target" "INSTALL"
            all_good=false
        else
            log_message "INFO" "Numpad Moonraker component is installed correctly" "INSTALL"
        fi
    fi

    # Check z_force_move component
    if [ ! -L "${KLIPPER_DIR}/klippy/extras/z_force_move.py" ]; then
        log_message "ERROR" "Z Force Move component not installed" "INSTALL"
        all_good=false
    else
        log_message "INFO" "Z Force Move component is installed" "INSTALL"
    fi

    for service in klipper moonraker numpad_event_service; do
        if ! systemctl is-active --quiet "$service"; then
            log_message "ERROR" "$service failed to start" "INSTALL"
            all_good=false
        else
            SERVICE_STATUS[$service]="RUNNING"
            log_message "INFO" "$service is running" "INSTALL"
        fi
    done

    return $([ "$all_good" = true ])
}

# Function to update repository with LFS support
update_repo() {
    log_message "INFO" "Updating repository with LFS files..." "INSTALL"
    
    cd "$LISTER_CONFIG_DIR" || {
        log_message "ERROR" "Failed to change to repository directory" "INSTALL"
        return 1
    }
    
    # Setup and fetch LFS files
    git lfs install
    
    # Reset any local changes (including file modes)
    git reset --hard
    git clean -fd
    
    log_message "INFO" "Fetching LFS files..." "INSTALL"
    git lfs fetch --all
    git lfs checkout
    git pull --force origin main
    
    log_message "INFO" "Repository update completed" "INSTALL"
    return 0
}

# Function to verify numpad setup
verify_numpad_setup() {
    log_message "INFO" "Verifying numpad setup..." "INSTALL"
    
    # Ensure no incorrect symlink exists
    if [ -L "${KLIPPER_DIR}/klippy/extras/numpad_event_service.py" ]; then
        log_message "WARNING" "Removing incorrect numpad service symlink" "INSTALL"
        rm -f "${KLIPPER_DIR}/klippy/extras/numpad_event_service.py"
    fi
    
    # Check input group
    if ! groups pi | grep -q "input"; then
        log_message "ERROR" "User 'pi' not in input group" "INSTALL"
        return 1
    fi
    
    # Check keyboard module
    if ! lsmod | grep -q "uinput"; then
        log_message "ERROR" "Required kernel module 'uinput' not loaded" "INSTALL"
        return 1
    fi
    
    # Verify service file
    if [ ! -L "/etc/systemd/system/numpad_event_service.service" ]; then
        log_message "ERROR" "Numpad service symlink not found" "INSTALL"
        return 1
    fi
    
    # Check component installation
    if [ ! -L "${MOONRAKER_DIR}/moonraker/components/numpad_macros.py" ]; then
        log_message "ERROR" "Numpad component not installed" "INSTALL"
        return 1
    fi
    
    # Verify log file setup
    local numpad_log="/home/pi/printer_data/logs/numpad_event_service.log"
    if [ ! -f "$numpad_log" ]; then
        touch "$numpad_log"
        chown pi:pi "$numpad_log"
        chmod 644 "$numpad_log"
    fi
    
    return 0
}

# Function to verify sound system
verify_sound_setup() {
    log_message "INFO" "Verifying sound system setup..." "INSTALL"
    
    # Check audio tools
    for cmd in aplay amixer mpv; do
        if ! command -v $cmd &> /dev/null; then
            log_message "ERROR" "Required command not found: $cmd" "INSTALL"
            return 1
        fi
    done
    
    # Check audio device
    if ! aplay -l | grep -q "card"; then
        log_message "ERROR" "No audio devices found" "INSTALL"
        return 1
    fi
    
    # Check sound directories
    local sound_dirs=(
        "$SOUND_FILES_DIR"
        "$SOUND_MP3_DIR"
        "$SOUND_WAV_DIR"
    )
    
    for dir in "${sound_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            log_message "ERROR" "Sound directory not found: $dir" "INSTALL"
            return 1
        fi
    done
    
    # Check for sound files
    if [ -z "$(ls -A $SOUND_MP3_DIR)" ]; then
        log_message "WARNING" "No MP3 files found in sounds directory" "INSTALL"
    fi
    
    # Check component symlinks
    if [ ! -L "${KLIPPER_DIR}/klippy/extras/sound_system.py" ]; then
        log_message "ERROR" "Sound system Klipper component not linked" "INSTALL"
        return 1
    fi
    
    if [ ! -L "${MOONRAKER_DIR}/moonraker/components/sound_system_service.py" ]; then
        log_message "ERROR" "Sound system Moonraker component not linked" "INSTALL"
        return 1
    fi
    
    # Test audio system
    if ! amixer sget 'PCM' &> /dev/null; then
        log_message "ERROR" "Unable to access audio mixer" "INSTALL"
        return 1
    fi
    
    return 0
}

# Function to setup sound system
setup_sound_system() {
    log_message "INFO" "Setting up sound system..." "SOUND"
    
    # Create sound directories
    mkdir -p "$SOUND_WAV_DIR"
    mkdir -p "$SOUND_MP3_DIR"
    
    # Set permissions
    chown -R pi:pi "$SOUND_FILES_DIR"
    find "$SOUND_FILES_DIR" -type d -exec chmod 755 {} \;
    find "$SOUND_FILES_DIR" -type f -exec chmod 644 {} \;
    
    # Set initial volume
    if amixer sget 'PCM' &> /dev/null; then
        amixer -M sset 'PCM' 75%
        log_message "INFO" "Set initial volume to 75%" "SOUND"
    fi
    
    # Verify setup
    verify_sound_setup || {
        log_message "ERROR" "Sound system verification failed" "SOUND"
        return 1
    }
}

# Function to verify system requirements
verify_system_requirements() {
    log_message "INFO" "Verifying system requirements..." "INSTALL"
    
    # Check disk space (need at least 500MB free)
    local free_space=$(df -m /home/pi | awk 'NR==2 {print $4}')
    if [ "$free_space" -lt 500 ]; then
        log_message "ERROR" "Insufficient disk space. Need at least 500MB free" "INSTALL"
        return 1
    fi
    
    # Check network connectivity
    if ! ping -c 1 github.com &> /dev/null; then
        log_message "ERROR" "No network connectivity to GitHub" "INSTALL"
        return 1
    fi
    
    # Check Python version (need 3.7+)
    if ! python3 -c "import sys; exit(0 if sys.version_info >= (3, 7) else 1)"; then
        log_message "ERROR" "Python 3.7 or higher required" "INSTALL"
        return 1
    fi
    
    return 0
}

# Function to check if script is run as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root"
        exit 1
    fi
}

# Function to verify script location
verify_script_location() {
    local current_path=$(readlink -f "$0")
    if [ "$current_path" != "$EXPECTED_SCRIPT_PATH" ]; then
        echo "Script must be run from $EXPECTED_SCRIPT_PATH"
        echo "Current location: $current_path"
        exit 1
    fi
}

# Main process
main() {
    check_root
    verify_script_location
    
    # Verify system requirements first
    verify_system_requirements || {
        log_message "ERROR" "System requirements not met" "INSTALL"
        exit 1
    }
    
    log_message "INFO" "Starting Lister configuration ${MODE}" "INSTALL"
    
    case "$MODE" in
        "install")
            install_system_deps
            install_python_deps
            setup_services || {
                log_message "ERROR" "Service setup failed" "INSTALL"
                exit 1
            }
            setup_sound_system || {
                log_message "ERROR" "Sound system setup failed" "INSTALL"
                exit 1
            }
            verify_printables_setup || {
                log_message "ERROR" "Printables verification failed" "INSTALL"
                exit 1
            }
            ;;
        "refresh")
            # Update repository in refresh mode
            update_repo || {
                log_message "ERROR" "Failed to update repository" "INSTALL"
                exit 1
            }
            ;;
        "sync")
            # Update repository first
            log_message "INFO" "Updating repository before sync..." "INSTALL"
            update_repo || {
                log_message "ERROR" "Failed to update repository" "INSTALL"
                exit 1
            }
            
            # Then sync files and fix permissions
            log_message "INFO" "Syncing files..." "INSTALL"
            sync_config_files || {
                log_message "ERROR" "Config sync failed" "INSTALL"
                exit 1
            }
            setup_symlinks
            fix_permissions
            log_message "INFO" "Sync complete" "INSTALL"
            exit 0
            ;;
    esac
    
    # Common operations for install and refresh
    if [ "$MODE" != "sync" ]; then
        sync_config_files || {
            log_message "ERROR" "Config sync failed" "INSTALL"
            exit 1
        }
        setup_symlinks
        fix_permissions
        
        restart_services
        verify_services
        
        log_message "INFO" "${MODE^} complete" "INSTALL"
    fi
}

# Script entry point
case "$1" in
    "install"|"refresh"|"sync")
        MODE="$1"
        main
        ;;
    *)
        echo "Usage: $0 {install|refresh|sync}"
        exit 1
        ;;
esac