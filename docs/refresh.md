# Lister Refresh System Documentation

## Overview
The Lister refresh system consists of two primary scripts: `install.sh` and `refresh.sh`. While `install.sh` handles initial setup and major changes, `refresh.sh` provides routine maintenance and updates. This documentation covers both scripts and their roles in maintaining your Lister 3D printer system.

## Script Comparison

| Feature | install.sh | refresh.sh |
|---------|------------|------------|
| Full repository clone | Yes | No |
| Force clean state | Yes | No |
| Service restart | Yes | Yes, with retry |
| Permission fixes | Full reset | Check and fix |
| Requirements install | Always | Only on updates |
| Local changes | Discarded | Preserved when possible |

## Installation Script (install.sh)

### Purpose
- Initial system setup
- Complete system reset
- Major version upgrades
- Full repository reinstallation

### When to Use
- First-time setup
- After system corruption
- When directed by support
- Major version upgrades

### Usage
```bash
cd /home/pi/printer_data/config/lister_config
sudo ./install.sh
```

## Refresh Script (refresh.sh)

### Purpose
- Routine system maintenance
- Repository updates
- Service health checks
- Permission verification

### When to Use
- Regular maintenance
- After printer firmware updates
- When services are misbehaving
- To check system health

### Usage
```bash
cd /home/pi/printer_data/config/lister_config
sudo ./refresh.sh
```

## Managed Components

### Repositories
```
lister_numpad_macros    → /home/pi/lister_numpad_macros
lister_sound_system     → /home/pi/lister_sound_system
lister_printables       → /home/pi/printer_data/gcodes/lister_printables
```

### Services
```
- klipper
- moonraker
- numpad_event_service
- printables_cron (Cron job)
```

## Logging System

### Log Files
- Install Log: `/home/pi/printer_data/logs/lister_install.log`
- Refresh Log: `/home/pi/printer_data/logs/lister_refresh.log`

### Log Format
```
[TIMESTAMP] [LEVEL] Message
```

### Log Levels
- INFO: Normal operations
- WARNING: Non-critical issues
- ERROR: Critical problems

## Status Reports

### Repository Status
| Status | Meaning |
|--------|----------|
| SUCCESS | Operation completed successfully |
| CURRENT | No updates needed |
| UPDATED | Successfully updated |
| MISSING | Repository not found |
| FETCH_FAILED | Update failed |
| INSTALL_FAILED | Post-update install failed |

### Service Status
| Status | Meaning |
|--------|----------|
| RUNNING | Service is active |
| STOPPED | Service is inactive |
| RESTARTED | Service was restarted |
| CONFIGURED | Cron job is set up |
| MISSING | Service/cron not found |

## Common Operations

### Check System Status
```bash
sudo ./refresh.sh
```

### Reset Everything
```bash
sudo ./install.sh
```

### View Logs
```bash
# View install log
tail -f /home/pi/printer_data/logs/lister_install.log

# View refresh log
tail -f /home/pi/printer_data/logs/lister_refresh.log
```

## Troubleshooting

### Permission Issues
```bash
# Fix permissions manually
sudo chown -R pi:pi /home/pi/lister_*
sudo chmod -R 755 /home/pi/lister_*
```

### Service Issues
```bash
# Check service status
sudo systemctl status klipper
sudo systemctl status moonraker
sudo systemctl status numpad_event_service

# Check cron jobs
crontab -l -u pi
```

### Repository Issues
```bash
# Manual repository reset
cd /path/to/repository
sudo -u pi git reset --hard
sudo -u pi git clean -fd
sudo -u pi git pull origin main
```

## Maintenance Schedule

### Daily
- Automatic cron jobs run

### Weekly
- Run refresh.sh to check updates
- Review log files

### Monthly
- Check disk space
- Verify all services
- Review system status

### As Needed
- After firmware updates
- When adding new features
- When troubleshooting issues

## Best Practices

### Regular Maintenance
1. Run refresh.sh weekly
2. Monitor log files
3. Keep track of changes
4. Document custom modifications

### Before Updates
1. Check printer is idle
2. Backup configuration
3. Review current status

### After Updates
1. Verify services
2. Check printer operation
3. Review logs
4. Test basic functionality

## Security Considerations

### File Permissions
- All files owned by pi:pi
- Scripts require root for execution
- Logs readable by pi user

### Service Management
- Service operations require root
- Cron jobs run as pi user
- Limited scope of automation

## Recovery Procedures

### Service Recovery
1. Run refresh.sh first
2. Check specific service logs
3. Restart individual services
4. Run install.sh as last resort

### Repository Recovery
1. Try refresh.sh first
2. Check for local changes
3. Manual git reset if needed
4. Full reinstall as last resort

## Support

### When to Contact Support
- Persistent service failures
- Repeated repository errors
- Unexplained behavior changes
- Security concerns

### What to Provide
1. Relevant log files
2. Current system status
3. Recent changes
4. Error messages

## Future Maintenance

### Planned Updates
- Regular script improvements
- New feature support
- Security updates
- Performance optimizations

### Version Control
- Scripts are versioned
- Changes are tracked
- Updates are documented