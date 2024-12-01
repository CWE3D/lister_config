#!/usr/bin/env python3

import os
from crontab import CronTab

METADATA_SCRIPT = "/home/pi/printer_data/gcodes/lister_printables/scripts/update_lister_metadata.py"
MOONRAKER_CONF = "/home/pi/printer_data/config/moonraker.conf"
INSTALL_FLAG = "/home/pi/printer_data/logs/lister_printables_installed.log"

LISTER_PRINTABLES_CONFIG = """
[update_manager client lister_printables]
type: git_repo
path: ~/printer_data/gcodes/lister_printables
origin: https://github.com/CWE3D/lister_printables.git
is_system_service: False
primary_branch: main
managed_services: klipper
"""

def setup_daily_cron_job():
    user_cron = CronTab(user='pi')

    # Remove any existing jobs that run our script
    user_cron.remove_all(command=METADATA_SCRIPT)

    # Create a new job to run daily at 2:00 AM
    job = user_cron.new(command=f'{METADATA_SCRIPT}')
    job.setall('0 2 * * *')

    # Write the changes
    user_cron.write()

    print("Daily cron job set up successfully. Metadata scan will run every day at 2:00 AM.")

def update_moonraker_conf():
    # Check if the install flag exists
    if os.path.exists(INSTALL_FLAG):
        print("Install flag found. Skipping moonraker.conf update.")
        return

    # Check if the configuration already exists in moonraker.conf
    with open(MOONRAKER_CONF, 'r') as f:
        if '[update_manager client lister_printables]' in f.read():
            print("Lister printables configuration already exists in moonraker.conf. Skipping update.")
            return

    # Append the configuration to moonraker.conf
    with open(MOONRAKER_CONF, 'a') as f:
        f.write(LISTER_PRINTABLES_CONFIG)

    print("Lister printables configuration added to moonraker.conf.")

if __name__ == "__main__":
    setup_daily_cron_job()
    update_moonraker_conf()