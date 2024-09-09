from moonraker.components.base_component import BaseComponent
from moonraker.confighelper import ConfigHelper
import logging
import asyncio
import os


class ListerMetadataScanPlugin(BaseComponent):
    def __init__(self, config: ConfigHelper):
        super().__init__(config)
        self.server = config.get_server()
        self.file_manager = self.server.lookup_component('file_manager')
        self.gcode_metadata = self.file_manager.get_metadata_storage()
        self.lister_printables_path = 'lister_printables'
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

            for file_path in self.walk_directory(full_path):
                if file_path.lower().endswith(('.gcode', '.g', '.gco')):
                    rel_path = os.path.relpath(file_path, root_dir)
                    await self.scan_file_metadata(rel_path)

            logging.info("Lister initial metadata scan completed.")
            await self.server.send_event("lister_metadata_scan:scan_complete")
        except Exception as e:
            logging.exception(f"Error during Lister metadata scan: {str(e)}")

    def walk_directory(self, directory):
        for root, dirs, files in os.walk(directory):
            if '.thumbs' in dirs:
                dirs.remove('.thumbs')  # don't visit .thumbs directories
            for file in files:
                yield os.path.join(root, file)

    async def scan_file_metadata(self, rel_path: str):
        try:
            logging.info(f"Scanning metadata for {rel_path}")

            full_path = os.path.join(self.file_manager.get_directory('gcodes'), rel_path)

            # Force a rescan
            self.gcode_metadata.remove_file_metadata(rel_path)

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


def load_component(config: ConfigHelper):
    return ListerMetadataScanPlugin(config)