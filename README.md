# lister_config
This is the official Klipper config directory, this should sit in the lister_config directory and called by the printer.cfg.


## Version 2.5.0

Hi Anita, please follow the instructions below to update our inner workings.

The current project is about the merger of four different projects related to the 3D printer Lister.
It was decided to merge them since it is all related to the same printer and is dependent on each other.

All folders, not repositories was moved into the /home/pi/lister_config directory.
So it a single repository now.

Those projects are (repositories are):

lister_config
This is the main repository that all merged to. From here we will be able to update the other merged folders.

This used to sit in /home/pi/printer_data/config/lister_config/*
and will now move to /home/pi/lister_config/[rest of merged folders]

This was here because the printer macros etc should sit in the printer_data folder.

Study its lister.sh script and see what it does because it commands all the sub-repositories to install / refresh.

Specific lister.sh script instructions:
- Since this moved out of printer_data/config/lister_config/*.cfg to /home/pi/lister_config/*.cfg directory, we need to rsync over the needed contents to printer_data/config/lister_config/*.cfg
- Remember that there is also a /home/pi/lister_config/macros/*.cfg that needs to be rsynced over as well
- Update the lister.sh script to reflect the new directory structure changes
- Lets keep the lister.sh for main management and all the sub-repositories to install / refresh for its specific tasks.
--------------------------------

lister_numpad_macros
This repository contains the macros and services, components for the numpad macro actions.

This used to sit in /home/pi/lister_numpad_macros
and will now move to /home/pi/lister_config/lister_numpad_macros

Study its install.sh / refresh.sh script and see what it does.

Specific install/refresh.sh script instructions:
- Since this moved out of /home/pi/lister_numpad_macros to /home/pi/lister_config/lister_numpad_macros, we need to handle some scripts changes;
  - Look at the install.sh/refresh.sh script it takes care of extras/numpad_event_service.py which is a service that needs to be linked correctly again.
  - Then there is also a moonraker components/numpad_macros.py that needs to be symlinked correctly to the new directory
--------------------------------

lister_sound_system
This repository contains the sound system for the printer.

This used to sit in /home/pi/lister_sound_system
and will now move to /home/pi/lister_config/lister_sound_system

Study its install.sh / refresh.sh script and see what it does.

Specific install/refresh.sh script instructions:
- Since this moved out of /home/pi/lister_sound_system to /home/pi/lister_config/lister_sound_system, we need to handle some scripts changes;
  - Look at the install.sh/refresh.sh script it takes care of extras/sound_system.py which is a klipper plugin that needs to be linked correctly again.
  - Then there is also a moonraker components/sound_system_service.py that needs to be symlinked correctly to the new directory

--------------------------------

lister_printables
This repository contains the gcode files for the printer to print parts of the Lister 3D printer.

This used to sit in /home/pi/lister_printables
and will now move to /home/pi/lister_config/lister_printables

Study its install.sh / refresh.sh script and see what it does.

Specific install/refresh.sh script instructions:
- Since this moved from of printer_data/gcodes/lister_printables to /home/pi/lister_config/lister_printables directory, we need to rsync over the needed contents /home/pi/lister_config/lister_printables/gcodes/*.gcode to /home/pi/printer_data/gcodes/lister_printables/*.gcode (all subdirectories must be included)
