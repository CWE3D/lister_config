# Lister Update System
#
# Copyright (C) 2024 Jason Schoeman <jason@schoeman.me>
#
# This file may be distributed under the terms of the GNU GPLv3 license.

import logging
import os
import subprocess

class ListerUpdate:
    def __init__(self, config):
        self.printer = config.get_printer()
        self.gcode = self.printer.lookup_object('gcode')
        
        # Set up paths
        self.lister_config_dir = "/home/pi/lister_config"
        self.update_service = "/home/pi/lister_config/extras/lister_update_service.py"
        
        # Register commands
        self.gcode.register_command(
            'UPDATE_LISTER', 
            self.cmd_UPDATE_LISTER,
            desc=self.cmd_UPDATE_LISTER.__doc__
        )

    def cmd_UPDATE_LISTER(self, gcmd):
        """Update Lister configuration: UPDATE_LISTER MODE=refresh
        Modes: install, refresh, sync, restart, permissions"""
        mode = gcmd.get('MODE', 'refresh').lower()
        
        # Validate mode
        valid_modes = ['install', 'refresh', 'sync', 'restart', 'permissions']
        if mode not in valid_modes:
            raise gcmd.error(f"Invalid mode: {mode}. Must be one of: {', '.join(valid_modes)}")
        
        try:
            # Call the update service
            process = subprocess.Popen(
                [self.update_service, mode],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
            
            try:
                stdout, stderr = process.communicate(timeout=300)
                
                if process.returncode != 0:
                    raise gcmd.error(
                        f"Lister update failed: {stderr}"
                    )
                
                # Restart Klipper if needed
                if mode in ['install', 'refresh', 'sync']:
                    self._restart_klipper(gcmd)
                
                gcmd.respond_info(
                    f"Lister update ({mode}) completed successfully\n"
                    f"Output: {stdout}"
                )
                
            except subprocess.TimeoutExpired:
                process.kill()
                raise gcmd.error("Lister update timed out after 5 minutes")
                
        except Exception as e:
            logging.exception("Error during Lister update")
            raise gcmd.error(f"Lister update failed: {str(e)}")

    def _restart_klipper(self, gcmd):
        """Restart Klipper"""
        gcmd.respond_info("Restarting Klipper...")
        self.printer.request_exit('restart')

def load_config(config):
    return ListerUpdate(config) 