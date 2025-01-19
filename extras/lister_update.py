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
        self.lister_script = os.path.join(self.lister_config_dir, "lister.sh")
        
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
            # Make script executable first
            self._make_executable()
            
            # Run the update command with shell=True to handle sudo properly
            cmd = f"sudo {self.lister_script} {mode}"
            process = subprocess.Popen(
                cmd,
                shell=True,  # Use shell to handle sudo
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
            
            # Wait for completion with timeout
            try:
                stdout, stderr = process.communicate(timeout=300)  # 5 minute timeout
                
                if process.returncode != 0:
                    raise gcmd.error(
                        f"Lister update failed (code {process.returncode}): {stderr}"
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

    def _make_executable(self):
        """Make the lister.sh script executable"""
        try:
            # Use shell=True to handle sudo properly
            result = subprocess.run(
                f"sudo chmod +x {self.lister_script}",
                shell=True,
                check=True,
                capture_output=True,
                text=True,
                timeout=10
            )
            if result.returncode != 0:
                raise RuntimeError(f"chmod failed: {result.stderr}")
        except subprocess.SubprocessError as e:
            logging.exception("Error making lister.sh executable")
            raise RuntimeError(f"Failed to make lister.sh executable: {str(e)}")

    def _restart_klipper(self, gcmd):
        """Restart Klipper"""
        gcmd.respond_info("Restarting Klipper...")
        self.printer.request_exit('restart')

def load_config(config):
    return ListerUpdate(config) 