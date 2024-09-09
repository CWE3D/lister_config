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
        self.lister_printables_path = os.path.join('gcodes', 'lister_printables')
        asyncio.create_task(self.initial_scan())

    async def initial_scan(self):
        await self.server.event_loop.run_in_thread(asyncio.sleep, 10)
        logging.info("Starting Lister initial metadata scan for lister_printables...")
        try:
            gcode_files = await self.file_manager.get_file_list(self.lister_printables_path)
            for file_info in gcode_files:
                if file_info['type'] == 'file' and file_info['name'].endswith('.gcode'):
                    file_path = os.path.join(self.lister_printables_path, file_info['path'])
                    try:
                        await self.gcode_metadata.parse_metadata(file_path)
                        logging.info(f"Scanned metadata for {file_path}")
                    except Exception as e:
                        logging.error(f"Error scanning {file_path}: {str(e)}")
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