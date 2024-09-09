# lister_metadata_scan.py

import logging
import asyncio
import os
from moonraker import MoonrakerRouter
from moonraker.server import ServerComponent


class ListerMetadataScanPlugin(ServerComponent):
    def __init__(self, config):
        self.server = config.get_server()
        self.file_manager = self.server.lookup_component('file_manager')
        self.lister_printables_path = 'gcodes/lister_printables'
        asyncio.create_task(self.initial_scan())

    async def initial_scan(self):
        await self.server.event_loop.run_in_thread(asyncio.sleep, 10)
        logging.info(f"Checking for Lister printables directory: {self.lister_printables_path}")

        try:
            files = await self.file_manager.get_file_list(self.lister_printables_path)
            if not files:
                logging.info(f"No files found in {self.lister_printables_path}. Skipping metadata scan.")
                return

            logging.info("Starting Lister initial metadata scan for lister_printables...")
            for file_info in files:
                if file_info['type'] == 'file' and file_info['name'].endswith('.gcode'):
                    file_path = os.path.join(self.lister_printables_path, file_info['path'])
                    try:
                        metadata = await self.file_manager.get_file_metadata(file_path)
                        if metadata:
                            logging.info(f"Successfully retrieved metadata for {file_path}")
                        else:
                            logging.warning(f"No metadata found for {file_path}")
                    except Exception as e:
                        logging.error(f"Error retrieving metadata for {file_path}: {str(e)}")

            logging.info("Lister initial metadata scan for lister_printables completed.")
            await self.server.send_event("lister_metadata_scan:scan_complete")
        except Exception as e:
            logging.error(f"Error during Lister metadata scan: {str(e)}")

    async def on_server_initialized(self, server):
        self.server.register_notification(
            "lister_metadata_scan:scan_complete", "Status of the Lister Metadata Scan")


def load_component(config):
    return ListerMetadataScanPlugin(config)