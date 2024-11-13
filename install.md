# Lister Configuration Installation Documentation

## Overview
The Lister installation script (`install.sh`) is a comprehensive tool designed to manage and install various components of the Lister 3D printer system. It handles the installation and configuration of multiple repositories, services, and dependencies in a systematic and error-resistant way.

## Prerequisites

- Root access (sudo privileges)
- Git installed
- Python 3 and pip3 installed
- Access to the following repositories:
  - lister_numpad_macros
  - lister_sound_system
  - lister_printables

## Installation Process

### 1. Initial Setup

First, clone the lister_config repository:
```bash
git clone https://github.com/CWE3D/lister_config.git /home/pi/printer_data/config/lister_config
cd /home/pi/printer_data/config/lister_config
sudo chmod +x install.sh
sudo ./install.sh
```

### 2. Script Operation

The script performs the following operations in sequence:

1. **Verification**
   - Checks if running as root
   - Verifies script location
   - Creates necessary directories

2. **Repository Management**
   - Clones or updates each repository
   - Forces clean state (discards local changes)
   - Retries failed operations up to 3 times

3. **Permission Management**
   - Sets correct ownership (pi:pi)
   - Sets correct permissions (755)
   - Makes all .sh files executable

4. **Service Management**
   - Verifies klipper service
   - Verifies moonraker service
   - Verifies numpad_event_service
   - Checks printables cron job

## Directory Structure

```
/home/pi/
├── lister_numpad_macros/
├── lister_sound_system/
├── printer_data/
│   ├── config/
│   │   └── lister_config/
│   ├── gcodes/
│   │   └── lister_printables/
│   └── logs/
│       └── lister_install.log
```

## Logging

All installation activities are logged to:
```
/home/pi/printer_data/logs/lister_install.log
```

The log includes:
- Timestamp
- Log level (INFO, WARNING, ERROR)
- Detailed operation messages
- Error messages and stack traces

## Repository Management

### Handled Repositories

| Repository | Branch | Installation Directory |
|------------|--------|----------------------|
| lister_numpad_macros | main | /home/pi/lister_numpad_macros |
| lister_sound_system | main | /home/pi/lister_sound_system |
| lister_printables | main | /home/pi/printer_data/gcodes/lister_printables |

### Repository Operations

For each repository, the script:
1. Attempts to update if exists
2. Performs clean clone if update fails
3. Installs Python requirements if requirements.txt exists
4. Runs repository-specific install scripts if present

## Error Handling

The script includes several error handling mechanisms:

1. **Repository Failures**
   - Automatic retry on failed clones
   - Directory cleanup before retries
   - Maximum 3 retry attempts

2. **Service Failures**
   - Detailed service status checking
   - Comprehensive error reporting
   - Service recovery attempts

3. **Permission Issues**
   - Recursive permission fixing
   - Ownership verification
   - Executable bit setting for scripts

## Installation Report

At the end of installation, a detailed report is generated showing:

1. **Repository Status**
   - SUCCESS: Successfully installed
   - FAILED_CLONE: Clone operation failed
   - FAILED_INSTALL: Install script failed
   - FAILED_REQUIREMENTS: Python requirements installation failed
   - NO_INSTALL_SCRIPT: No installation script found

2. **Service Status**
   - RUNNING: Service is active
   - STOPPED: Service is inactive
   - CONFIGURED: (for cron jobs) Successfully set up
   - MISSING: (for cron jobs) Not found

## Troubleshooting

### Common Issues

1. **Permission Denied**
   ```bash
   sudo ./install.sh
   ```

2. **Repository Clone Failures**
   - Check internet connection
   - Verify repository URLs
   - Check disk space

3. **Service Start Failures**
   - Check service logs:
     ```bash
     sudo systemctl status klipper
     sudo systemctl status moonraker
     sudo systemctl status numpad_event_service
     ```

4. **Python Requirements Issues**
   - Verify pip3 installation
   - Check Python version compatibility

### Log Analysis

To view installation logs:
```bash
tail -f /home/pi/printer_data/logs/lister_install.log
```

## Maintenance

### Post-Installation Verification

1. Check service status:
   ```bash
   sudo systemctl status klipper
   sudo systemctl status moonraker
   sudo systemctl status numpad_event_service
   ```

2. Verify cron jobs:
   ```bash
   crontab -l -u pi
   ```

3. Check file permissions:
   ```bash
   ls -la /home/pi/lister_*
   ls -la /home/pi/printer_data/config/lister_config
   ```

### Manual Repository Updates

While the script handles updates automatically, you can manually update repositories:
```bash
cd /path/to/repository
git reset --hard
git clean -fd
git pull origin main
```

## Security Considerations

- Script requires root privileges
- All files are owned by pi:pi
- Standard permissions (755) are used
- No sensitive data is stored in logs

## Support

For issues or questions:
1. Check the installation log
2. Verify service status
3. Contact Lister 3D printer support with log files