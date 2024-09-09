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
        self.lister_printables_path = 'gcodes/lister_printables'
        self.sync_lock = asyncio.Lock()
        asyncio.create_task(self.initial_scan())

    async def initial_scan(self):
        await self.server.event_loop.run_in_thread(asyncio.sleep, 10)
        logging.info(f"Starting Lister initial metadata scan for {self.lister_printables_path}")

        try:
            files = await self.file_manager.get_file_list(self.lister_printables_path)
            if not files:
                logging.info(f"No files found in {self.lister_printables_path}. Skipping metadata scan.")
                return

            for file_info in files:
                if file_info['type'] == 'file' and file_info['name'].lower().endswith(('.gcode', '.g', '.gco')):
                    await self.scan_file_metadata(file_info['path'])

            logging.info("Lister initial metadata scan completed.")
            await self.server.send_event("lister_metadata_scan:scan_complete")
        except Exception as e:
            logging.error(f"Error during Lister metadata scan: {str(e)}")

    async def scan_file_metadata(self, filename: str):
        async with self.sync_lock:
            try:
                full_path = os.path.join(self.lister_printables_path, filename)
                logging.info(f"Scanning metadata for {full_path}")

                # Remove existing metadata to force a rescan
                ret = self.gcode_metadata.remove_file_metadata(full_path)
                if ret is not None:
                    await ret

                # Get path info and parse metadata
                path_info = self.file_manager.get_path_info(full_path, "gcodes")
                evt = self.gcode_metadata.parse_metadata(full_path, path_info)
                await evt.wait()

                # Retrieve and log the metadata
                metadata = self.gcode_metadata.get(full_path, None)
                if metadata is None:
                    logging.warning(f"Failed to parse metadata for file '{full_path}'")
                else:
                    logging.info(f"Successfully scanned metadata for {full_path}")
            except Exception as e:
                logging.error(f"Error scanning metadata for {full_path}: {str(e)}")

    async def on_server_initialized(self, server):
        self.server.register_notification(
            "lister_metadata_scan:scan_complete", "Status of the Lister Metadata Scan")


def load_component(config):
    return ListerMetadataScanPlugin(config)