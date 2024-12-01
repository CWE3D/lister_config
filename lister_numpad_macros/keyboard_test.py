import keyboard
import time
import logging

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(message)s',
    filename='keyboard_test.log'
)

# Also print to console
console = logging.StreamHandler()
console.setLevel(logging.INFO)
logging.getLogger('').addHandler(console)


def on_key_event(event):
    """Log any key event"""
    logging.info(f'Key event - Name: {event.name}, Event Type: {event.event_type}, Scan Code: {event.scan_code}')


def main():
    logging.info("Starting keyboard event monitoring...")
    logging.info("Press keys to see events (Ctrl+C to exit)")

    # Register for all key events
    keyboard.on_press(on_key_event)

    try:
        # Keep the script running
        while True:
            time.sleep(0.1)
    except KeyboardInterrupt:
        logging.info("Shutting down...")
    finally:
        keyboard.unhook_all()


if __name__ == "__main__":
    main()