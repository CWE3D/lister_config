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
        self.gcode_metadata = self.server.lookup_component('gcode_metadata')
        self.base_path = os.path.expanduser('~/printer_data/gcodes')
        self.lister_printables_path = os.path.join(self.base_path, 'lister_printables')
        asyncio.create_task(self.initial_scan())

    async def initial_scan(self):
        await self.server.event_loop.run_in_thread(asyncio.sleep, 10)
        logging.info(f"Checking for Lister printables directory: {self.lister_printables_path}")

        if not os.path.exists(self.lister_printables_path):
            logging.info(f"Directory {self.lister_printables_path} does not exist. Skipping metadata scan.")
            return

        logging.info("Starting Lister initial metadata scan for lister_printables...")
        try:
            for root, dirs, files in os.walk(self.lister_printables_path):
                for file in files:
                    if file.endswith('.gcode'):
                        file_path = os.path.join(root, file)
                        relative_path = os.path.relpath(file_path, self.base_path)
                        try:
                            metadata = await self.gcode_metadata.parse_metadata(relative_path)
                            if metadata:
                                logging.info(f"Successfully scanned metadata for {relative_path}")
                            else:
                                logging.warning(f"No metadata found for {relative_path}")
                        except Exception as e:
                            logging.error(f"Error scanning {relative_path}: {str(e)}")

            logging.info("Lister initial metadata scan for lister_printables completed.")
            await self.server.send_event("lister_metadata_scan:scan_complete")
        except Exception as e:
            logging.error(f"Error during Lister metadata scan: {str(e)}")

    async def on_server_initialized(self, server):
        self.server.register_notification(
            "lister_metadata_scan:scan_complete", "Status of the Lister Metadata Scan")

    async def on_exit(self):
        # Cleanup code if needed
        pass


def load_component(config):
    return ListerMetadataScanPlugin(config)