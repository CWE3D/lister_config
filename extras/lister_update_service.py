#!/usr/bin/env python3
#
# Lister Update Service
#
# Copyright (C) 2024 Jason Schoeman <jason@schoeman.me>
#
# This file may be distributed under the terms of the GNU GPLv3 license.

import os
import sys
import time
import logging
import argparse
import subprocess
from pathlib import Path

# Configure logging
def setup_logging():
    log_file = "/home/pi/printer_data/logs/lister_update_service.log"
    log_format = '%(asctime)s [%(levelname)s] - %(message)s'
    
    logging.basicConfig(
        filename=log_file,
        level=logging.INFO,
        format=log_format
    )
    
    # Also log to console
    console = logging.StreamHandler()
    console.setFormatter(logging.Formatter(log_format))
    logging.getLogger('').addHandler(console)

class ListerUpdateService:
    def __init__(self):
        self.lister_config_dir = "/home/pi/lister_config"
        self.lister_script = os.path.join(self.lister_config_dir, "lister.sh")

    def run_update(self, mode):
        """Execute lister.sh with specified mode"""
        if not os.path.exists(self.lister_script):
            raise RuntimeError(f"Lister script not found: {self.lister_script}")

        # Make script executable
        try:
            os.chmod(self.lister_script, 0o755)
            logging.info(f"Made {self.lister_script} executable")
        except Exception as e:
            logging.error(f"Failed to make script executable: {e}")
            raise

        # Run the update command
        try:
            logging.info(f"Running lister update with mode: {mode}")
            result = subprocess.run(
                [self.lister_script, mode],
                capture_output=True,
                text=True,
                check=False  # Don't raise on non-zero exit
            )
            
            # Log the complete output
            if result.stdout:
                logging.info(f"Command output: {result.stdout}")
            if result.stderr:
                logging.error(f"Command error output: {result.stderr}")
            
            if result.returncode != 0:
                error_msg = f"Command failed with code {result.returncode}"
                if result.stderr:
                    error_msg += f": {result.stderr}"
                logging.error(error_msg)
                raise RuntimeError(error_msg)
                
            logging.info(f"Update completed successfully")
            return {"status": "success", "output": result.stdout}
            
        except subprocess.SubprocessError as e:
            error_msg = f"Update failed: {str(e)}"
            logging.error(error_msg)
            raise RuntimeError(error_msg)

def main():
    parser = argparse.ArgumentParser(description="Lister Update Service")
    parser.add_argument('mode', help="Update mode (install, refresh, sync, restart, permissions)")
    args = parser.parse_args()

    setup_logging()
    service = ListerUpdateService()

    try:
        result = service.run_update(args.mode)
        print(result)
        sys.exit(0)
    except Exception as e:
        logging.error(f"Service error: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main() 