# Z-Axis Calibration System for Lister 3D Printer

## Introduction

The Z-Axis Calibration System ensures accurate Z-axis positioning on your Lister 3D printer, combining sensorless homing reliability with probe-based calibration precision. This system offers both manual maintenance calibrations and automatic periodic checks, adapting to your printing needs.

## Features

- Manual calibration for maintenance
- Automatic periodic calibration checks
- Option to force calibration before every print
- Persistent calibration data across printer restarts

## File Structure and Configuration

Before we dive into using the calibration system, it's important to understand the file structure:

- The `printer-template.cfg` file is located in the `klipper/lister_config/` directory.
- Your active `printer.cfg` file is located one directory up from the `lister_config` folder.

To make changes:

1. If you haven't already, copy the `printer-template.cfg` from `klipper/lister_config/` to the main directory (where your current `printer.cfg` is located).
2. Rename this copy to `printer.cfg` (replace the existing one if present).
3. Make your modifications in this new `printer.cfg` file.

This approach allows you to easily revert to a default configuration if needed by repeating steps 1 and 2.

## How to Use

### 1. Manual Calibration (Maintenance)

For manual calibration and result saving:

```
CALIBRATE_Z_AXIS FORCE=TRUE SAVE=TRUE
```

Use this when you've altered your printer setup or suspect Z-axis calibration issues.

### 2. Automatic Periodic Checks

The system automatically checks and recalibrates every 7 days as part of the `START_PRINT` macro.

### 3. Force Calibration Before Every Print

To ensure calibration before every print:

1. Open your `printer.cfg` file in the main directory.
2. Add the following macro override at the end of the file:

```gcode
[gcode_macro START_PRINT]
rename_existing: START_PRINT_BASE
gcode:
    CALIBRATE_Z_AXIS FORCE=TRUE
    START_PRINT_BASE
```

This method overrides the default `START_PRINT` macro, forcing Z-axis calibration before each print while maintaining other startup procedures.

## Understanding the Calibration Process

1. Z-axis homes using sensorless homing
2. Print head moves to predefined probing position
3. Probe measures bed distance
4. System calculates deviation from expected position
5. Z-offset applies to compensate for deviation

## Calibration Frequency

Default automatic calibration occurs if more than 7 days have passed since the last calibration. This interval is adjustable in the configuration.

## Saving Calibration Data

Using `SAVE=TRUE` stores calibration data for automatic loading at printer startup, ensuring persistence across restarts.

## Troubleshooting

For first layer or Z-axis positioning issues:

1. Run `CALIBRATE_Z_AXIS FORCE=TRUE SAVE=TRUE`
2. Check probe for physical issues or obstructions
3. Ensure clean and level bed before calibrating

## Customization

Advanced users can modify calibration interval or probing position in the `CALIBRATE_Z_AXIS` macro within their `printer.cfg` file. Always backup configurations before making changes.

Regular mechanical component checks and maintenance remain crucial despite this system's assistance in maintaining accurate Z-axis positioning.

For further questions or issues, consult the Lister 3D Printer manual or contact support.

### `probe_z_offset`
This is the offset between the probe and the nozzle.

**Where it's saved:**
1. In `macros-probe.cfg`:
   - Saved during probe calibration via `PROBE_CALIBRATE` and `CHECK_PROBE_CALIBRATION_STATUS`
   - Saved using `SAVE_VARIABLE VARIABLE=probe_z_offset VALUE={new_offset}`

**Where it's used:**
1. In `macros-probe.cfg`:
   - Used in `MEASURE_Z_HEIGHT` to calculate the true height:
   ```python
   {% set saved_probe_z_offset = printer.save_variables.variables.get('probe_z_offset', printer.configfile.settings['probe']['z_offset']|float) %}
   {% set CALCULATED_OFFSET = MEASURED_Z - PROBE_Z_OFFSET %}
   ```

### `real_z_offset`
This is the offset of the nozzle from the bed.

**Where it's saved:**
1. In `macros-probe.cfg`:
   - Used in `CALIBRATE_Z_HEIGHT` to adjust the true height:
   ```python
   {% set saved_z_offset = printer.save_variables.variables.get('real_z_offset', 0.0)|float %}
   {% set adjusted_true_height = base_true_height - saved_z_offset %}
   ```

### `true_max_height`
This is the actual maximum Z height of the printer after calibration.

**Where it's saved:**
1. In `macros-probe.cfg`:
   - Initially saved in `MEASURE_Z_HEIGHT`:
   ```python
   {% set TRUE_MAX_HEIGHT = EXPECTED_MAX - CALCULATED_OFFSET %}
   SAVE_VARIABLE VARIABLE=true_max_height VALUE={TRUE_MAX_HEIGHT}
   ```
   - Adjusted and saved again in `CALIBRATE_Z_HEIGHT`:
   ```python
   SAVE_VARIABLE VARIABLE=true_max_height VALUE={adjusted_true_height}
   ```

2. In `numpad_macros.py`:
   - Updated during Z adjustments via the numpad:
   ```python
   new_true_max = float(current_true_max) - self._accumulated_z_adjust
   await self._execute_gcode(f'SAVE_VARIABLE VARIABLE=true_max_height VALUE={new_true_max}')
   ```

**Where it's used:**
1. In `macros-base.cfg`:
   - Used in `UPDATE_PARK_Z` to set safe parking height:
   ```python
   {% set true_max = printer.save_variables.variables.get('true_max_height', 0) %}
   SET_GCODE_VARIABLE MACRO=Lister VARIABLE=park_z VALUE={safe_park_z}
   ```

2. In `macros-probe.cfg`:
   - Used in `_APPLY_SAVED_Z_HEIGHT` to set kinematic position:
   ```python
   {% set saved_z = printer.save_variables.variables.get('true_max_height', 0) %}
   SET_Z_KINEMATIC_POSITION Z={saved_z}
   ```

### `z_offset`
This appears to be a general Z offset value.

**Where it's saved:**
- Not directly saved in the provided files, but appears to be calculated or used internally by Klipper

The flow of these variables:
1. `probe_z_offset` is set during probe calibration
2. This is used with the measured probe height to calculate `true_max_height`
3. `real_z_offset` is used to adjust `true_max_height` for final positioning
4. The adjusted `true_max_height` is then used for:
   - Setting safe parking positions
   - Setting kinematic positions
   - Real-time adjustments during printing via the numpad

The key relationship is:
```python
true_max_height = EXPECTED_MAX - (MEASURED_Z - probe_z_offset) - real_z_offset
```

This system allows for:
1. Accurate probe measurements
2. Real-time adjustments during printing
3. Safe parking positions
4. Persistent storage of calibration values
