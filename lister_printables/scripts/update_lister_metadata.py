import os
import sys
import requests
import logging
from urllib.parse import quote
import time
from requests.exceptions import RequestException

# Configuration
MOONRAKER_URL = "http://localhost:7125"
LISTER_PRINTABLES_PATH = "/home/pi/printer_data/gcodes/lister_printables/gcodes"
LOG_FILE = "/home/pi/printer_data/logs/metadata_scan.log"
GCODES_ROOT = "/home/pi/printer_data/gcodes"
MAX_RETRIES = 30
RETRY_DELAY = 10  # seconds


def setup_logging():
    try:
        os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
        logging.basicConfig(filename=LOG_FILE, level=logging.INFO,
                            format='%(asctime)s - %(levelname)s - %(message)s')
        logging.info(f"Script started. Python version: {sys.version}")
        logging.info(f"Script path: {os.path.abspath(__file__)}")
        logging.info(f"Working directory: {os.getcwd()}")
    except Exception as e:
        print(f"Failed to set up logging: {str(e)}")
        sys.exit(1)


def is_moonraker_ready():
    try:
        response = requests.get(f"{MOONRAKER_URL}/server/info", timeout=5)
        return response.status_code == 200
    except RequestException:
        return False


def wait_for_moonraker():
    for attempt in range(MAX_RETRIES):
        if is_moonraker_ready():
            logging.info("Moonraker is ready.")
            return True
        logging.info(
            f"Waiting for Moonraker to be ready. Attempt {attempt + 1}/{MAX_RETRIES}. Retrying in {RETRY_DELAY} seconds...")
        time.sleep(RETRY_DELAY)
    return False


def scan_file_metadata(file_path, max_retries=3):
    relative_path = os.path.relpath(file_path, GCODES_ROOT)
    encoded_path = quote(relative_path)
    url = f"{MOONRAKER_URL}/server/files/metascan"

    for attempt in range(max_retries):
        try:
            data = {"filename": encoded_path}
            response = requests.post(url, json=data, timeout=60)
            response.raise_for_status()
            logging.info(f"Successfully scanned metadata for {relative_path}")
            return True
        except RequestException as e:
            logging.warning(
                f"Error scanning metadata for {relative_path} (Attempt {attempt + 1}/{max_retries}): {str(e)}")
            if hasattr(e, 'response') and e.response is not None:
                logging.warning(f"Response content: {e.response.content}")
            if attempt < max_retries - 1:
                time.sleep(2 ** attempt)  # Exponential backoff
            else:
                logging.error(f"Failed to scan metadata for {relative_path} after {max_retries} attempts")
                return False


def walk_directory(directory):
    for root, dirs, files in os.walk(directory):
        if '.thumbs' in dirs:
            dirs.remove('.thumbs')
        for file in files:
            if file.lower().endswith(('.gcode', '.g', '.gco')):
                full_path = os.path.join(root, file)
                logging.info(f"Found file: {full_path}")
                yield full_path


def main():
    setup_logging()
    logging.info("Starting Lister metadata scan")

    if not os.path.exists(GCODES_ROOT):
        logging.error(f"Gcodes root directory does not exist: {GCODES_ROOT}")
        sys.exit(1)

    if not wait_for_moonraker():
        logging.error("Moonraker is not ready after maximum retries. Aborting metadata scan.")
        return

    start_time = time.time()
    file_count = 0
    success_count = 0
    failed_files = []
    new_files = []
    updated_files = []

    try:
        for file_path in walk_directory(LISTER_PRINTABLES_PATH):
            file_count += 1
            if os.path.getmtime(file_path) > (time.time() - 86400):  # Check if file was modified in the last 24 hours
                if os.path.getctime(file_path) > (time.time() - 86400):
                    new_files.append(file_path)
                else:
                    updated_files.append(file_path)

            if scan_file_metadata(file_path):
                success_count += 1
            else:
                failed_files.append(file_path)

        end_time = time.time()
        duration = end_time - start_time
        logging.info(
            f"Lister metadata scan completed. Scanned {file_count} files, {success_count} successful, in {duration:.2f} seconds.")
        logging.info(f"New files: {len(new_files)}, Updated files: {len(updated_files)}")

        if failed_files:
            logging.warning(f"Failed to scan {len(failed_files)} files.")

    except Exception as e:
        logging.exception(f"An unexpected error occurred during the scan: {str(e)}")


if __name__ == "__main__":
    main()