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
        self.gcode_metadata = self.file_manager.get_metadata_storage()
        self.lister_printables_path = 'lister_printables'
        self.sync_lock = asyncio.Lock()
        self.server.register_event_handler(
            "server:klippy_ready", self.handle_server_ready)

    async def handle_server_ready(self):
        await asyncio.sleep(10)  # Wait for other components to initialize
        await self.initial_scan()

    async def initial_scan(self):
        logging.info(f"Starting Lister initial metadata scan for {self.lister_printables_path}")
        try:
            root_dir = self.file_manager.get_directory('gcodes')
            full_path = os.path.join(root_dir, self.lister_printables_path)

            if not os.path.exists(full_path):
                logging.info(f"Directory {full_path} does not exist. Skipping metadata scan.")
                return

            for root, _, files in os.walk(full_path):
                for filename in files:
                    if filename.lower().endswith(('.gcode', '.g', '.gco')):
                        file_path = os.path.join(root, filename)
                        rel_path = os.path.relpath(file_path, root_dir)
                        await self.scan_file_metadata(rel_path)

            logging.info("Lister initial metadata scan completed.")
            await self.server.send_event("lister_metadata_scan:scan_complete")
        except Exception as e:
            logging.exception(f"Error during Lister metadata scan: {str(e)}")

    async def scan_file_metadata(self, rel_path: str):
        async with self.sync_lock:
            try:
                logging.info(f"Scanning metadata for {rel_path}")

                # Check if metadata already exists and is valid
                existing_metadata = self.gcode_metadata.get(rel_path)
                if existing_metadata and self.is_metadata_valid(existing_metadata):
                    logging.info(f"Valid metadata already exists for {rel_path}")
                    return

                # Get path info and parse metadata
                full_path = os.path.join(self.file_manager.get_directory('gcodes'), rel_path)
                path_info = self.file_manager.get_path_info(full_path, "gcodes")
                evt = self.gcode_metadata.parse_metadata(rel_path, path_info)
                await evt.wait()

                # Verify metadata was parsed successfully
                metadata = self.gcode_metadata.get(rel_path)
                if metadata:
                    logging.info(f"Successfully scanned metadata for {rel_path}")
                else:
                    logging.warning(f"Failed to parse metadata for file '{rel_path}'")
            except Exception as e:
                logging.exception(f"Error scanning metadata for {rel_path}: {str(e)}")

    def is_metadata_valid(self, metadata):
        # Add your own validation logic here
        return 'thumbnails' in metadata and metadata['thumbnails']

    async def on_server_initialized(self, server):
        self.server.register_notification(
            "lister_metadata_scan:scan_complete", "Status of the Lister Metadata Scan")


def load_component(config):
    return ListerMetadataScanPlugin(config)