# lister_metadata_scan.py

import logging
import asyncio
import os
import aiohttp
from moonraker import MoonrakerRouter
from moonraker.server import ServerComponent


class ListerMetadataScanPlugin(ServerComponent):
    def __init__(self, config):
        self.server = config.get_server()
        self.file_manager = self.server.lookup_component('file_manager')
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

            gcode_files = []
            for root, dirs, files in os.walk(full_path):
                if '.thumbs' in dirs:
                    dirs.remove('.thumbs')  # don't visit .thumbs directories
                for file in files:
                    if file.lower().endswith(('.gcode', '.g', '.gco')):
                        rel_path = os.path.relpath(os.path.join(root, file), root_dir)
                        gcode_files.append(rel_path)

            await self.scan_files(gcode_files)

            logging.info("Lister initial metadata scan completed.")
            await self.server.send_event("lister_metadata_scan:scan_complete")
        except Exception as e:
            logging.exception(f"Error during Lister metadata scan: {str(e)}")

    async def scan_files(self, files):
        async with aiohttp.ClientSession() as session:
            tasks = []
            for file in files:
                task = asyncio.create_task(self.scan_file(session, file))
                tasks.append(task)
            await asyncio.gather(*tasks)

    async def scan_file(self, session, file_path):
        url = f"http://localhost/server/files/metascan?filename={file_path}"
        try:
            async with session.get(url) as response:
                if response.status == 200:
                    logging.info(f"Successfully scanned metadata for {file_path}")
                else:
                    logging.warning(f"Failed to scan metadata for {file_path}. Status: {response.status}")
        except Exception as e:
            logging.error(f"Error scanning metadata for {file_path}: {str(e)}")

    async def on_server_initialized(self, server):
        self.server.register_notification(
            "lister_metadata_scan:scan_complete", "Status of the Lister Metadata Scan")


def load_component(config):
    return ListerMetadataScanPlugin(config)