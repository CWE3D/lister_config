# Information

For the open source Lister 3D printer, add a feature that when adjusting the z_offset when printing the first layer
to remember the z_offset for the next print.

# Objective

The printer has a numpad knob controller feature that allows knob adjusting the
z_offset when printing the first layer.

It is a great way to to finetune the printers first layer perfectly. It is easy
to adjust, making it remembering it for the next print an excellent feature.

# Things to consider

    - When adjusting the knob, before saving it to the config we should delay a few seconds.
    - It will probably have to be done in numpad_macros.py file, as this is where this logic sits.
    - When adjusting it through the UI, it is not a feature we might want to use which gives one that option.
        - However it is a feature of the numpad_macros component.
        - We should just have a MACRO to reset this value to zero again.
        - I have implemented this z_offset = 4.508250016365447 (from variables)
            - This is the value that is saved in the config.
            - This value is a little deceptive, as it is not the z_offset one would expect.
            - Investigate this and maybe we should fix it system wide to use the correct name.
            - In this process we will actually calculate the true z_offset as last set in numpad_macros first layer.

    - We should remember to reset this the z offset when it is needed.
    - We should remmeber to also include in our calculations the z_offset that is passed through from the slicer for spesific filament offset.
        - It should all be considered since when printing again the same filament adjusted z offset will be passed through again.
        - So we want to remember just the just the adjustment the user makes through the knob in the first print -
            - For example, I am starting a print, in my slicer I have it set to include a 0.05mm offset for this specific filament.
            - The print starts, the first layer begins and I turn the know twice and it adjusts 0.06 and the height is now perfect so we see a total if 0.11 adjustement.
                - Now in Variables real_z_offset (for example) is set to 0.06, so that when I start the new print it will automatically be 0.11
                - But if I want it to print closer again I turn the know down and I deduct -0.02 from it, so the new saved value should be 0.04
            - We must make sure that the printers passed through z_offset does not simply override our variable restored but calculated together by doing that after receiving any z offset from slicer.
        - Take into account that when the probe calibrate process is running, this variable real_z_offset should be reset to 0.

### VARIABLE

```
[Variables]
calibration_count = 1
last_printed_file = '/home/pi/printer_data/gcodes/lister_printables_/speaker_box_set.gcode'
probe_z_offset = 0.918
true_max_height = 240.49174998363455
z_offset = 4.508250016365447

# It gets saved like this in macros:
# SAVE_VARIABLE VARIABLE=z_offset VALUE={CALCULATED_OFFSET}

```

## Some requirements:

    - Please be very careful not to just change things that does not have anything to do with this objective.
        - AI have a tendency to pass real negative and positive values for macros that can receive commands like =-Z
    - Focus on the task at hand and if things are unsure, please just ask, it is too sensitive as it is production code.
    - Investigate the files carefully so you know exactly what is going on with the things we need to change.
    - Remember to have fun.
    - You may mentions definitive issues you notices or recommendations for enhancements.