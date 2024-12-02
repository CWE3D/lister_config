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
METADATA_SCRIPT="${PRINTABLES_SCRIPTS_DIR}/update_lister_metadata.py"
CRON_SETUP_SCRIPT="${PRINTABLES_SCRIPTS_DIR}/setup_one_time_cron.py"
UPDATE_CLIENT_SCRIPT="${PRINTABLES_SCRIPTS_DIR}/update_client.py"

# Add function to verify printables setup
verify_printables_setup() {
    log_message "INFO" "Verifying printables setup..."
    
    # Check required directories
    local required_dirs=(
        "$PRINTABLES_DIR"
        "$PRINTABLES_INSTALL_DIR"
        "$PRINTABLES_SCRIPTS_DIR"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            log_error "Required directory not found: $dir"
            return 1
        fi
    }
    
    # Check required scripts
    local required_scripts=(
        "$METADATA_SCRIPT"
        "$CRON_SETUP_SCRIPT"
        "$UPDATE_CLIENT_SCRIPT"
    )
    
    for script in "${required_scripts[@]}"; do
        if [ ! -f "$script" ]; then
            log_error "Required script not found: $script"
            return 1
        fi
        # Make script executable
        chmod +x "$script"
    }
    
    # Verify cron job
    if ! crontab -l -u pi | grep -q "$METADATA_SCRIPT"; then
        log_warning "Cron job not found for metadata script"
        # Don't fail here as it might be first install
    }
    
    return 0
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

# Function to install system dependencies
install_system_deps() {
    log_message "INFO" "Installing system dependencies..."
    apt-get update
    apt-get install -y git-lfs alsa-utils python3-pip mpv
}

# Function to install Python requirements
install_python_deps() {
    log_message "INFO" "Installing Python requirements..."
    
    local req_file="${LISTER_CONFIG_DIR}/requirements.txt"
    
    if [ ! -f "$req_file" ]; then
        log_error "Requirements file not found at $req_file"
        return 1
    fi
    
    # Install in each environment
    for env in "system" "klippy" "moonraker"; do
        log_message "INFO" "Installing in $env environment..."
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
    log_message "INFO" "Syncing configuration files..."
    
    # Create required directories
    mkdir -p "$PRINTABLES_INSTALL_DIR"
    
    # Sync printables
    if ! rsync -av --delete "${PRINTABLES_DIR}/gcodes/" "$PRINTABLES_INSTALL_DIR/"; then
        log_error "Failed to sync printables files"
        return 1
    }
    
    # Verify file copying
    local source_count=$(find "${PRINTABLES_DIR}/gcodes/" -type f -name "*.gcode" | wc -l)
    local dest_count=$(find "$PRINTABLES_INSTALL_DIR" -type f -name "*.gcode" | wc -l)
    
    if [ "$source_count" -ne "$dest_count" ]; then
        log_error "File count mismatch after sync"
        return 1
    }
    
    log_message "INFO" "Successfully synced $source_count gcode files"
    return 0
}

# Function to setup symlinks
setup_symlinks() {
    log_message "INFO" "Setting up component symlinks..."
    
    # Numpad macros links
    ln -sf "${NUMPAD_DIR}/extras/numpad_event_service.py" \
        "${KLIPPER_DIR}/klippy/extras/numpad_event_service.py"
    ln -sf "${NUMPAD_DIR}/components/numpad_macros.py" \
        "${MOONRAKER_DIR}/moonraker/components/numpad_macros.py"
    
    # Sound system links
    ln -sf "${SOUND_DIR}/extras/sound_system.py" \
        "${KLIPPER_DIR}/klippy/extras/sound_system.py"
    ln -sf "${SOUND_DIR}/components/sound_system_service.py" \
        "${MOONRAKER_DIR}/moonraker/components/sound_system_service.py"
}

# Function to setup services
setup_services() {
    log_message "INFO" "Setting up services..."
    
    # Load required kernel module
    modprobe uinput
    
    # Add module to load at boot
    if ! grep -q "uinput" /etc/modules; then
        echo "uinput" >> /etc/modules
    fi
    
    # Setup numpad event service
    ln -sf "$SERVICE_FILE" \
        "/etc/systemd/system/numpad_event_service.service"
    
    systemctl daemon-reload
    systemctl enable numpad_event_service.service
    
    # Verify setup
    verify_numpad_setup || {
        log_error "Numpad setup verification failed"
        return 1
    }
}

# Function to setup cron jobs
setup_cron_jobs() {
    log_message "INFO" "Setting up cron jobs..."
    
    if ! python3 "$CRON_SETUP_SCRIPT"; then
        log_error "Failed to setup cron job"
        return 1
    }
    
    log_message "INFO" "Cron jobs setup successfully"
}

# Function to update metadata
update_metadata() {
    log_message "INFO" "Updating printables metadata..."
    
    if ! python3 "$METADATA_SCRIPT"; then
        log_error "Failed to update metadata"
        return 1
    }
    
    log_message "INFO" "Metadata updated successfully"
}

# Function to fix permissions
fix_permissions() {
    log_message "INFO" "Setting permissions..."
    
    # Add user pi to input group
    usermod -a -G input pi
    
    # Fix directory permissions
    find "$LISTER_CONFIG_DIR" -type d -exec chmod 755 {} \;
    find "$LISTER_CONFIG_DIR" -type f -exec chmod 644 {} \;
    
    # Make scripts executable
    chmod +x "${LISTER_CONFIG_DIR}/lister.sh"
    chmod +x "${PRINTABLES_DIR}/scripts/"*.py
    chmod +x "${PRINTABLES_DIR}/scripts/"*.sh
    
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
    log_message "INFO" "Restarting services..."
    
    systemctl restart klipper
    sleep 2
    systemctl restart moonraker
    sleep 2
    systemctl restart numpad_event_service
}

# Function to verify services
verify_services() {
    local all_good=true

    for service in klipper moonraker numpad_event_service; do
        if ! systemctl is-active --quiet "$service"; then
            log_error "$service failed to start"
            all_good=false
        else
            SERVICE_STATUS[$service]="RUNNING"
            log_message "INFO" "$service is running"
        fi
    done

    return $([ "$all_good" = true ])
}

# Function to update repository with LFS support
update_repo() {
    log_message "INFO" "Updating repository with LFS files..."
    
    cd "$LISTER_CONFIG_DIR" || {
        log_error "Failed to change to repository directory"
        return 1
    }
    
    # Setup and fetch LFS files
    git lfs install
    log_message "INFO" "Fetching LFS files..."
    git lfs fetch --all
    git lfs checkout
    
    # Clean and update repository
    git reset --hard
    git clean -fd
    git pull --force origin main
    
    log_message "INFO" "Repository update completed"
    return 0
}

# Function to verify numpad setup
verify_numpad_setup() {
    log_message "INFO" "Verifying numpad setup..."
    
    # Check input group
    if ! groups pi | grep -q "input"; then
        log_error "User 'pi' not in input group"
        return 1
    }
    
    # Check keyboard module
    if ! lsmod | grep -q "uinput"; then
        log_error "Required kernel module 'uinput' not loaded"
        return 1
    }
    
    # Verify service file
    if [ ! -L "/etc/systemd/system/numpad_event_service.service" ]; then
        log_error "Numpad service symlink not found"
        return 1
    }
    
    # Check component installation
    if [ ! -L "${MOONRAKER_DIR}/moonraker/components/numpad_macros.py" ]; then
        log_error "Numpad component not installed"
        return 1
    }
    
    # Verify log file setup
    local numpad_log="/home/pi/printer_data/logs/numpad_event_service.log"
    if [ ! -f "$numpad_log" ]; then
        touch "$numpad_log"
        chown pi:pi "$numpad_log"
        chmod 644 "$numpad_log"
    }
    
    return 0
}

# Function to verify sound system
verify_sound_setup() {
    log_message "INFO" "Verifying sound system setup..."
    
    # Check audio tools
    for cmd in aplay amixer mpv; do
        if ! command -v $cmd &> /dev/null; then
            log_error "Required command not found: $cmd"
            return 1
        fi
    }
    
    # Check audio device
    if ! aplay -l | grep -q "card"; then
        log_error "No audio devices found"
        return 1
    }
    
    # Check sound directories
    local sound_dirs=(
        "$SOUND_FILES_DIR"
        "$SOUND_MP3_DIR"
        "$SOUND_WAV_DIR"
    )
    
    for dir in "${sound_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            log_error "Sound directory not found: $dir"
            return 1
        fi
    }
    
    # Check for sound files
    if [ -z "$(ls -A $SOUND_MP3_DIR)" ]; then
        log_warning "No MP3 files found in sounds directory"
    fi
    
    # Check component symlinks
    if [ ! -L "${KLIPPER_DIR}/klippy/extras/sound_system.py" ]; then
        log_error "Sound system Klipper component not linked"
        return 1
    }
    
    if [ ! -L "${MOONRAKER_DIR}/moonraker/components/sound_system_service.py" ]; then
        log_error "Sound system Moonraker component not linked"
        return 1
    }
    
    # Test audio system
    if ! amixer sget 'PCM' &> /dev/null; then
        log_error "Unable to access audio mixer"
        return 1
    }
    
    return 0
}

# Function to setup sound system
setup_sound_system() {
    log_message "INFO" "Setting up sound system..."
    
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
        log_message "INFO" "Set initial volume to 75%"
    fi
    
    # Verify setup
    verify_sound_setup || {
        log_error "Sound system verification failed"
        return 1
    }
}

# Main process
main() {
    check_root
    verify_script_location
    
    log_message "INFO" "Starting Lister configuration ${MODE}"
    
    if [ "$MODE" = "install" ]; then
        install_system_deps
        install_python_deps
        setup_services || {
            log_error "Service setup failed"
            exit 1
        }
        setup_sound_system || {
            log_error "Sound system setup failed"
            exit 1
        }
        verify_printables_setup || {
            log_error "Printables verification failed"
            exit 1
        }
        setup_cron_jobs || {
            log_error "Cron setup failed"
            exit 1
        }
    else
        # Update repository in refresh mode
        update_repo || {
            log_error "Failed to update repository"
            exit 1
        }
    fi
    
    sync_config_files || {
        log_error "Config sync failed"
        exit 1
    }
    setup_symlinks
    fix_permissions
    update_metadata || {
        log_error "Metadata update failed"
        exit 1
    }
    restart_services
    verify_services
    
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