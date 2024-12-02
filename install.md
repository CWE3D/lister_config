# Lister Configuration Installation Guide

This guide details the installation process for the Lister 3D printer configuration system. The system includes printer configuration, numpad macros, sound system, and printables management.

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Cleanup Old Installation](#cleanup-old-installation)
3. [Installation Process](#installation-process)
4. [Post-Installation](#post-installation)
5. [Maintenance](#maintenance)
6. [Component Details](#component-details)

## Prerequisites

- Klipper installed
- Moonraker installed
- Python 3.7 or higher
- Git with LFS support
- 500MB free disk space
- Network connectivity
- Root access (sudo)

Required packages:
```bash
sudo apt-get update
sudo apt-get install -y git-lfs alsa-utils python3-pip mpv
```

## Cleanup Old Installation

Before installing the new system, run the cleanup script to remove old installations:

1. Download the cleanup script:
```bash
wget https://raw.githubusercontent.com/CWE3D/lister_config/main/cleanup.sh
chmod +x cleanup.sh
```

2. Run the cleanup script:
```bash
sudo ./cleanup.sh
```

The cleanup script will:
- Stop related services (klipper, moonraker, numpad_event_service)
- Remove old repository directories
- Remove old symlinks
- Clean up old service files
- Remove old log files
- Remove old cron jobs
- Restart essential services

## Installation Process

1. Clone the repository:
```bash
cd /home/pi
git clone https://github.com/CWE3D/lister_config.git
cd lister_config
```

2. Run the installation script:
```bash
sudo ./lister.sh install
```

### What the Install Script Does

The installation script (`lister.sh`) performs the following tasks:

1. **System Verification**
   - Checks disk space (minimum 500MB)
   - Verifies network connectivity
   - Checks Python version
   - Creates backup directory

2. **Backup**
   - Creates backup of existing configuration
   - Maintains last 5 backups
   - Stores backups in `/home/pi/printer_data/config/backups`

3. **Dependencies Installation**
   - Installs system packages (git-lfs, alsa-utils, python3-pip, mpv)
   - Installs Python requirements in all environments:
     - System Python
     - Klippy environment
     - Moonraker environment

4. **Service Setup**
   - Configures numpad event service
   - Sets up uinput kernel module
   - Enables services on boot

5. **Sound System Setup**
   - Creates sound directories
   - Sets initial volume (75%)
   - Verifies audio system

6. **Printables Setup**
   - Creates required directories
   - Sets up daily metadata scan (cron job)
   - Syncs gcode files

7. **Component Setup**
   - Creates required symlinks
   - Sets correct permissions
   - Verifies all components

8. **Configuration**
   - Syncs configuration files
   - Sets up macros
   - Configures moonraker integration

## Post-Installation

After installation, verify:
1. All services are running:
```bash
systemctl status klipper moonraker numpad_event_service
```

2. Check logs for any errors:
```bash
tail -f /home/pi/printer_data/logs/lister_config.log
```

3. Test sound system:
```bash
ls /home/pi/lister_config/lister_sound_system/sounds
```

## Maintenance

### Refresh Installation
To update the installation:
```bash
sudo ./lister.sh refresh
```

The refresh process:
1. Updates repository with LFS files
2. Syncs configuration files
3. Updates metadata
4. Restarts services

### Logs
All logs are consolidated in:
```bash
/home/pi/printer_data/logs/lister_config.log
```

## Component Details

### 1. Numpad Macros
- Location: `/home/pi/lister_config/lister_numpad_macros`
- Service: numpad_event_service
- Handles keypad input for printer control

### 2. Sound System
- Location: `/home/pi/lister_config/lister_sound_system`
- Provides audio feedback and music streaming
- Volume control through numpad

### 3. Printables
- Location: `/home/pi/lister_config/lister_printables`
- Manages gcode files for Lister parts
- Daily metadata scanning

### 4. Configuration Files
- Main config: `/home/pi/printer_data/config/printer.cfg`
- Moonraker config: `/home/pi/printer_data/config/moonraker.conf`
- Macros: `/home/pi/lister_config/macros/*.cfg`

## Troubleshooting

If installation fails:
1. Check logs: `/home/pi/printer_data/logs/lister_config.log`
2. Verify all prerequisites are met
3. Ensure network connectivity
4. Check disk space
5. Verify Python version

For service issues:
```bash
systemctl status klipper
systemctl status moonraker
systemctl status numpad_event_service
```

## Support

For issues and support:
- GitHub Issues: [Lister Config Issues](https://github.com/CWE3D/lister_config/issues)
- Documentation: [Lister Config Wiki](https://github.com/CWE3D/lister_config/wiki)
