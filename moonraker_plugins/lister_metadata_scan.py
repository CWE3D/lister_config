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

                # Force a rescan by removing existing metadata
                self.gcode_metadata.remove_file_metadata(rel_path)

                # Get path info and parse metadata
                full_path = os.path.join(self.file_manager.get_directory('gcodes'), rel_path)
                path_info = self.file_manager.get_path_info(full_path, "gcodes")
                evt = self.gcode_metadata.parse_metadata(rel_path, path_info)
                await evt.wait()

                # Verify metadata was parsed successfully
                metadata = self.gcode_metadata.get(rel_path)
                if metadata:
                    logging.info(f"Successfully scanned metadata for {rel_path}")
                    # Ensure thumbnails are generated
                    await self.generate_thumbnails(rel_path, metadata)
                else:
                    logging.warning(f"Failed to parse metadata for file '{rel_path}'")
            except Exception as e:
                logging.exception(f"Error scanning metadata for {rel_path}: {str(e)}")

    async def generate_thumbnails(self, rel_path: str, metadata: dict):
        if 'thumbnails' not in metadata or not metadata['thumbnails']:
            logging.warning(f"No thumbnail data found for {rel_path}")
            return

        root_dir = self.file_manager.get_directory('gcodes')
        file_dir = os.path.dirname(os.path.join(root_dir, rel_path))
        thumbs_dir = os.path.join(file_dir, '.thumbs')

        if not os.path.exists(thumbs_dir):
            os.makedirs(thumbs_dir)

        for thumb in metadata['thumbnails']:
            if 'relative_path' in thumb:
                thumb_path = os.path.join(file_dir, thumb['relative_path'])
                if not os.path.exists(thumb_path):
                    logging.warning(f"Thumbnail file not found: {thumb_path}")
                    continue

                # Copy or move the thumbnail to the .thumbs directory
                new_thumb_path = os.path.join(thumbs_dir, os.path.basename(thumb_path))
                if not os.path.exists(new_thumb_path):
                    await self.server.event_loop.run_in_thread(
                        self._copy_file, thumb_path, new_thumb_path)
                    logging.info(f"Generated thumbnail: {new_thumb_path}")

    def _copy_file(self, src, dst):
        import shutil
        shutil.copy2(src, dst)

    async def on_server_initialized(self, server):
        self.server.register_notification(
            "lister_metadata_scan:scan_complete", "Status of the Lister Metadata Scan")


def load_component(config):
    return ListerMetadataScanPlugin(config)