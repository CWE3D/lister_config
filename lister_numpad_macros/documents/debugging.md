# Numpad Macros Logging and Debugging Guide

## Overview
The Numpad Macros system uses Moonraker's logging infrastructure for debugging and troubleshooting. Understanding how to enable and interpret these logs is crucial for development and troubleshooting.

## Log File Locations

### Moonraker Logs
- Primary log file: `~/printer_data/logs/moonraker.log`
- Contains all Numpad Macros component logs
- Component logs are prefixed with `moonraker.numpad_macros`

### Klipper Logs
- Primary log file: `~/printer_data/logs/klippy.log`
- Contains related G-code execution logs
- Useful for tracking command execution results

## Enabling Debug Logging

### 1. Configure Moonraker Component
Add to your `moonraker.conf`:
```ini
[numpad_macros]
debug_log: True  # Enable detailed debug logging
```

### 2. Restart Moonraker
```bash
sudo systemctl restart moonraker
```

## Monitoring Logs

### Watch Numpad Macros Logs
```bash
tail -f ~/printer_data/logs/moonraker.log | grep "moonraker.numpad_macros"
```

### Watch Both Moonraker and Klipper Logs
```bash
tail -f ~/printer_data/logs/moonraker.log ~/printer_data/logs/klippy.log
```

## Debug Log Categories

### 1. State Changes
```
moonraker.numpad_macros: State change - pending_key: key_1, pending_command: _HOME_ALL
moonraker.numpad_macros: State after command key - pending_key: None, pending_command: None
```

### 2. Command Processing
```
moonraker.numpad_macros: Processing key: key_up, type: down
moonraker.numpad_macros: Running query _QUERY_HOME_ALL
```

### 3. Probe Status
```
moonraker.numpad_macros: Probe adjustment - Current Z: 0.05
moonraker.numpad_macros: Using fine adjustment mode
```

### 4. Error Messages
```
moonraker.numpad_macros: Error processing numpad event: Invalid key code
moonraker.numpad_macros: Error fetching Klippy state: {'code': 503, 'message': 'Klippy not ready'}
```

## Key Debug Points

### 1. Command Reception
```python
if self.debug_log:
    self.logger.debug(f"Received event: {web_request.get_args()}")
```
- Logs incoming key events
- Shows event type and key code

### 2. State Tracking
```python
if self.debug_log:
    self.logger.debug(f"State before command key - pending_key: {self.pending_key}, "
                     f"pending_command: {self.pending_command}")
```
- Tracks command state changes
- Shows pending commands

### 3. Probe Adjustments
```python
if self.debug_log:
    self.logger.debug(f"Probe adjustment - Current Z: {current_z}")
    self.logger.debug(f"Using {'fine' if current_z < 0.1 else 'coarse'} adjustment mode")
```
- Shows probe height adjustments
- Indicates adjustment mode

## Common Debug Scenarios

### 1. Verify Command Reception
Look for:
```
moonraker.numpad_macros: Processing key: key_X, type: down
```

### 2. Check Probe Status
Look for:
```
moonraker.numpad_macros: Klippy state query result: {...}
moonraker.numpad_macros: Probe status change: False -> True
```

### 3. Verify Command Execution
Look for:
```
moonraker.numpad_macros: Executing confirmed command: _HOME_ALL
moonraker.numpad_macros: Command execution completed
```

## Troubleshooting Tips

### 1. Missing Logs
- Verify `debug_log: True` in configuration
- Check Moonraker service status
- Verify log file permissions

### 2. Command Not Executing
- Check for key reception logs
- Verify state transition logs
- Look for error messages

### 3. Probe Issues
- Monitor probe status changes
- Check Z-height reporting
- Verify TESTZ command generation

## Log Analysis Tools

### 1. Basic Filtering
```bash
grep "numpad_macros" moonraker.log | grep "Probe"
```

### 2. Time-Based Analysis
```bash
grep "numpad_macros" moonraker.log | grep "$(date +%Y-%m-%d)"
```

### 3. Error Detection
```bash
grep "numpad_macros.*Error" moonraker.log
```

## Best Practices

1. **Enable Temporary Debugging**
   - Enable debug logging when needed
   - Disable for production use
   - Monitor log file size

2. **Log File Management**
   - Regularly rotate log files
   - Archive important debug sessions
   - Clean up old logs

3. **Systematic Debugging**
   - Start with state verification
   - Check command flow
   - Verify execution results