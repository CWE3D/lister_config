# Lister Update System
#
# Copyright (C) 2024 Jason Schoeman <jason@schoeman.me>
#
# This file may be distributed under the terms of the GNU GPLv3 license.

import logging
import subprocess

class ListerUpdate:
    def __init__(self, config):
        self.printer = config.get_printer()
        self.gcode = self.printer.lookup_object('gcode')
        
        # Register commands
        self.gcode.register_command(
            'UPDATE_LISTER', 
            self.cmd_UPDATE_LISTER,
            desc=self.cmd_UPDATE_LISTER.__doc__
        )

    def cmd_UPDATE_LISTER(self, gcmd):
        """Update Lister configuration"""
        try:
            # Call the service through systemctl
            process = subprocess.Popen(
                ['systemctl', 'start', 'lister_update_service'],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
            
            try:
                stdout, stderr = process.communicate(timeout=300)
                
                # Check service status
                status_proc = subprocess.run(
                    ['systemctl', 'is-active', 'lister_update_service'],
                    capture_output=True,
                    text=True
                )
                
                if status_proc.returncode != 0:
                    # Get service logs if failed
                    log_proc = subprocess.run(
                        ['journalctl', '-u', 'lister_update_service', '-n', '50', '--no-pager'],
                        capture_output=True,
                        text=True
                    )
                    raise gcmd.error(
                        f"Lister update failed. Service logs:\n{log_proc.stdout}"
                    )
                
                # Restart Klipper
                # self._restart_klipper(gcmd)
                
                gcmd.respond_info("Lister update completed successfully")
                
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