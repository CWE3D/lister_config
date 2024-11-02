import evdev
from evdev import InputDevice, categorize, ecodes
import threading
import logging

class NumpadMacros:
    def __init__(self, config):
        self.printer = config.get_printer()
        self.reactor = self.printer.get_reactor()
        self.gcode = self.printer.lookup_object('gcode')
        self.shutdown = False

        # Get configuration
        self.device_path = config.get('device_path', '/dev/input/by-id/usb-SIGMACHIP_USB_Keyboard-event-kbd')

        # Register event handlers
        self.printer.register_event_handler("klippy:connect", self.handle_connect)
        self.printer.register_event_handler("klippy:shutdown", self.handle_shutdown)

        # Register commands
        self.gcode.register_command(
            'NUMPAD_TEST',
            self.cmd_NUMPAD_TEST,
            desc="Test numpad functionality"
        )

        # Key mapping for numpad (adjust these based on your device)
        self.key_mapping = {
            # Numpad key codes to their corresponding values
            evdev.ecodes.KEY_KP1: "1",
            evdev.ecodes.KEY_KP2: "2",
            evdev.ecodes.KEY_KP3: "3",
            evdev.ecodes.KEY_KP4: "4",
            evdev.ecodes.KEY_KP5: "5",
            evdev.ecodes.KEY_KP6: "6",
            evdev.ecodes.KEY_KP7: "7",
            evdev.ecodes.KEY_KP8: "8",
            evdev.ecodes.KEY_KP9: "9",
            evdev.ecodes.KEY_KP0: "0",
            evdev.ecodes.KEY_KPENTER: "ENTER",
            evdev.ecodes.KEY_KPDOT: "DOT"
        }

        # Start the input monitoring thread
        self.input_thread = None

    def handle_connect(self):
        """Called when printer connects"""
        try:
            self.device = InputDevice(self.device_path)
            logging.info(f"NumpadMacros: Connected to device {self.device.name}")

            # Start monitoring thread
            self.input_thread = threading.Thread(target=self._monitor_input)
            self.input_thread.daemon = True
            self.input_thread.start()

        except Exception as e:
            logging.error(f"NumpadMacros: Failed to initialize device: {str(e)}")
            raise self.printer.config_error(f"Failed to initialize numpad device: {str(e)}")

    def handle_shutdown(self):
        """Called when printer shuts down"""
        self.shutdown = True
        if hasattr(self, 'device'):
            self.device.close()

    def _monitor_input(self):
        """Monitor numpad input in a separate thread"""
        try:
            for event in self.device.read_loop():
                if self.shutdown:
                    break

                if event.type == evdev.ecodes.EV_KEY:
                    key_event = categorize(event)

                    # Only process key press events (not releases)
                    if key_event.keystate == key_event.key_down:
                        key_code = key_event.scancode

                        if key_code in self.key_mapping:
                            key_value = self.key_mapping[key_code]
                            # Schedule the key handling in the main thread
                            self.reactor.register_callback(
                                lambda e, k=key_value: self._handle_key_press(k))

        except Exception as e:
            logging.error(f"NumpadMacros: Error in input monitoring: {str(e)}")

    def _handle_key_press(self, key):
        """Handle a key press event"""
        try:
            # For testing, just respond with the key pressed
            self.gcode.run_script_from_command(f'RESPOND MSG="Numpad key pressed: {key}"')

            # Here you would implement the actual G-code execution for each key
            # For example:
            if key == "1":
                # Example: Move to home position when 1 is pressed
                # self.gcode.run_script_from_command('G28')
                pass

        except Exception as e:
            logging.error(f"NumpadMacros: Error handling key press: {str(e)}")

    def cmd_NUMPAD_TEST(self, gcmd):
        """G-code command to test numpad functionality"""
        gcmd.respond_info("NumpadMacros test command received")
        if hasattr(self, 'device'):
            gcmd.respond_info(f"Connected to: {self.device.name}")
        else:
            gcmd.respond_info("No numpad device connected")


def load_config(config):
    return NumpadMacros(config)