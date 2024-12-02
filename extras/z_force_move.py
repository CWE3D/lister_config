# Z axis kinematic position utility
#
# Copyright (C) 2024  Your Name <your@email.com>
#
# This file may be distributed under the terms of the GNU GPLv3 license.
import logging

class ZForceMove:
    def __init__(self, config):
        self.printer = config.get_printer()
        self.gcode = self.printer.lookup_object('gcode')
        # Register command
        self.gcode.register_command('SET_Z_KINEMATIC_POSITION',
                                  self.cmd_SET_Z_KINEMATIC_POSITION,
                                  desc=self.cmd_SET_Z_KINEMATIC_POSITION_help)

    cmd_SET_Z_KINEMATIC_POSITION_help = "Force a low-level kinematic Z position"
    def cmd_SET_Z_KINEMATIC_POSITION(self, gcmd):
        toolhead = self.printer.lookup_object('toolhead')
        toolhead.get_last_move_time()
        curpos = toolhead.get_position()
        # Only get and set Z, maintain current X,Y,E positions
        z = gcmd.get_float('Z', curpos[2])
        logging.info("SET_Z_KINEMATIC_POSITION z=%.3f", z)
        # Set position with only Z as homing axis
        toolhead.set_position([curpos[0], curpos[1], z, curpos[3]], 
                            homing_axes=(2,))

def load_config(config):
    return ZForceMove(config)