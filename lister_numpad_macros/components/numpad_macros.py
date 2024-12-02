from __future__ import annotations
import logging
import time
from typing import TYPE_CHECKING, Dict, Any, Optional, Set as SetType
import re
import subprocess

import asyncio


def strip_comments(code):
    # This regex removes everything after a '#' unless it's inside a string
    return code

if TYPE_CHECKING:
    from moonraker.common import WebRequest
    from moonraker.components.klippy_apis import KlippyAPI
    from moonraker.confighelper import ConfigHelper

class NumpadMacros:
    def __init__(self, config: ConfigHelper) -> None:
        self.server = config.get_server()
        self.event_loop = self.server.get_event_loop()
        self.name = config.get_name()

        # Initialize component logger
        self.debug_log = config.getboolean('debug_log', False)
        self.logger = logging.getLogger(f"moonraker.{self.name}")
        if self.debug_log:
            self.logger.setLevel(logging.DEBUG)
        else:
            self.logger.setLevel(logging.INFO)

        self.pending_key: Optional[str] = None
        self.pending_command: Optional[str] = None
        if self.debug_log:
            self.logger.debug("Initial state - pending_key: None, pending_command: None")

        # Get configuration values
        self.z_adjust_increment = config.getfloat(
            'z_adjust_increment', 0.01, above=-1., below=1.
        )

        # Get speed settings from config with defaults
        default_speed_settings = {
            "increment": 10,
            "max": 300,
            "min": 20
        }
        self.speed_settings = config.getdict('speed_settings', default=default_speed_settings)

        if self.debug_log:
            self.logger.debug(f"Loaded speed settings: {self.speed_settings}")

        # Add configuration for probe adjustments
        self.probe_min_step = config.getfloat(
            'probe_min_step', 0.025, above=0., below=1.
        )
        self.probe_coarse_multiplier = config.getfloat(
            'probe_coarse_multiplier', 0.5, above=0., below=1.
        )
        self.probe_fine_multiplier = config.getfloat(
            'probe_fine_multiplier', 0.2, above=0., below=1.
        )
        self.probe_fine_min_step = config.getfloat(
            'probe_fine_min_step', 0.01, above=0., below=1.
        )
        self.fine_tune_from = config.getfloat(
            'fine_tune_from', 0.05, above=0., below=1.
        )

        # Define default no-confirm and confirmation keys
        default_no_confirm = "key_up,key_down"
        default_confirm = "key_enter,key_enter_alt"

        # Get configuration for no-confirm and confirmation keys
        no_confirm_str = config.get('no_confirmation_keys', default_no_confirm)
        confirm_str = config.get('confirmation_keys', default_confirm)

        # Convert comma-separated strings to sets
        self.no_confirm_keys: SetType[str] = set(k.strip() for k in no_confirm_str.split(','))
        self.confirmation_keys: SetType[str] = set(k.strip() for k in confirm_str.split(','))

        if self.debug_log:
            self.logger.debug(f"No confirmation required for keys: {self.no_confirm_keys}")
            self.logger.debug(f"Confirmation keys: {self.confirmation_keys}")

        # Get command mappings from config
        self.command_mapping: Dict[str,str] = {}
        self.initial_query_command_mapping: Dict[str, str] = {}
        self._load_command_mapping(config)

        # State tracking
        self.pending_key: Optional[str] = None
        self.pending_command: Optional[str] = None
        self.is_probing: bool = False
        self._is_printing: bool = False
        self.z_offset_save_delay = config.getfloat(
            'z_offset_save_delay', 10.0, above=0.
        )
        self._pending_z_offset_save = False
        self._last_z_adjust_time = 0.0
        self._accumulated_z_adjust = 0.0

        # Register endpoints
        self.server.register_endpoint(
            "/server/numpad/event", ['POST'], self._handle_numpad_event
        )
        self.server.register_endpoint(
            "/server/numpad/status", ['GET'], self._handle_status_request
        )

        # Register notifications
        self.server.register_notification('numpad_macros:status_update')
        self.server.register_notification('numpad_macros:command_queued')
        self.server.register_notification('numpad_macros:command_executed')

        # Register event handlers
        self.server.register_event_handler(
            "server:klippy_ready", self._handle_ready
        )
        self.server.register_event_handler(
            "server:klippy_shutdown", self._handle_shutdown
        )

        if self.debug_log:
            self.logger.debug(f"{self.name}: Component Initialized")

    def _load_command_mapping(self, config: ConfigHelper) -> None:
        """Load command mappings from config"""
        key_options = [
            'key_1', 'key_2', 'key_3', 'key_4', 'key_5',
            'key_6', 'key_7', 'key_8', 'key_9', 'key_0',
            'key_dot', 'key_enter', 'key_up', 'key_down',
            'key_1_alt', 'key_2_alt', 'key_3_alt', 'key_4_alt',
            'key_5_alt', 'key_6_alt', 'key_7_alt', 'key_8_alt',
            'key_9_alt', 'key_0_alt', 'key_dot_alt', 'key_enter_alt'
        ]

        for key in key_options:
            # Check if the option exists in config
            if config.has_option(key):
                # Get the command value, strip whitespace
                cmd = config.get(key)
                if cmd:  # If command is not empty after stripping
                    self.command_mapping[key] = cmd
                    # Create QUERY version by adding prefix
                    self.initial_query_command_mapping[key] = f"_QUERY{cmd}" if cmd.startswith('_') else f"_QUERY_{cmd}"

                    if self.debug_log:
                        self.logger.debug(
                            f"Loaded mapping for {key} -> Command: {self.command_mapping[key]}, "
                            f"Query: {self.initial_query_command_mapping[key]}"
                        )
            else:
                # Option not in config - add to both mappings
                self.command_mapping[key] = f'_NO_ASSIGNED_MACRO KEY={key}'
                self.initial_query_command_mapping[key] = f'_NO_ASSIGNED_MACRO KEY={key}'

    async def _handle_numpad_event(self, web_request: WebRequest) -> Dict[str, Any]:
        try:
            event = web_request.get_args()
            key: str = event.get('key', '')
            event_type: str = event.get('event_type', '')

            if self.debug_log:
                self.logger.debug(f"Received event - Key: {key}, Type: {event_type}")
                self.logger.debug(f"Current state - pending_key: {self.pending_key}, "
                                  f"pending_command: {self.pending_command}")

            # THE MOST 1ST ORDER IMPORTANT KEY
            # First, check if it's a confirmation key
            if key in self.confirmation_keys:
                if self.debug_log:
                    self.logger.debug("Processing confirmation key")
                await self._handle_confirmation()
                return {'status': 'confirmed'}

            # THESE COMMAND RUN DIRECTLY AND 2ND ORDER
            # Then check if it's a no-confirmation key
            if key in self.no_confirm_keys:
                if self.debug_log:
                    self.logger.debug(f"Processing no-confirmation key: {key}")

                # Handle adjustment keys specially
                # Check if we are dealing with up and down, they are special 3RD ORDER
                if key in ['key_up', 'key_down']:
                    await self._handle_knob_adjustment(key)
                else:
                    # Now we can run the query command directly because
                    # we are dealing with real command as is no confirmation key.
                    # Execute command directly without query prefix
                    command = self.command_mapping[key]
                    if self.debug_log:
                        self.logger.debug(f"Executing no-confirmation command: {command}")

                    await self._execute_gcode(f'RESPOND MSG="Numpad macros: Executing {command}"')
                    await self._execute_gcode(command)

                    # Maintain status updates and notifications
                    await self.server.send_event(
                        "numpad_macros:command_executed",
                        {'command': command}
                    )
                    self._notify_status_update()

                return {'status': 'executed'}

            # Finally, handle regular command keys that need confirmation
            if self.debug_log:
                self.logger.debug("Processing regular command key")

            await self._handle_command_key(key)
            return {'status': 'queued'}

        except Exception as e:
            self.logger.exception("Error processing numpad event")
            raise

    async def _handle_command_key(self, key: str) -> None:
        """Handle regular command keys that require confirmation"""
        if self.debug_log:
            self.logger.debug(f"Processing command key: {key}")

        # Store as pending command (replaces any existing pending command)
        if self.pending_key and self.pending_key != key:
            await self._execute_gcode(
                f'RESPOND MSG="Numpad macros: Replacing pending command '
                f'{self.command_mapping[self.pending_key]} with {self.command_mapping[key]}"'
            )

        # Store the pending command
        self.pending_key = key
        self.pending_command = self.command_mapping[key]

        # Run the QUERY version for confirmation-required commands
        query_cmd = self.initial_query_command_mapping[key]
        await self._execute_gcode(f'RESPOND MSG="Numpad macros: Running query {query_cmd}"')
        await self._execute_gcode(query_cmd)

        await self._execute_gcode(
            f'RESPOND MSG="Numpad macros: Command {self.pending_command} is ready. Press ENTER to execute"'
        )

        self._notify_status_update()
        await self.server.send_event(
            "numpad_macros:command_queued",
            {'command': self.pending_command}
        )

    async def _handle_confirmation(self) -> None:
        """Handle confirmation key press"""
        if self.debug_log:
            self.logger.debug(f"Handling confirmation with state - pending_key: {self.pending_key}, "
                            f"pending_command: {self.pending_command}")

        if not self.pending_key or not self.pending_command:
            if self.debug_log:
                self.logger.debug("No pending command to confirm")
            await self._execute_gcode('RESPOND MSG="Numpad macros: No command pending for confirmation"')
            return

        try:
            # Store command locally before clearing state
            cmd = self.pending_command
            if self.debug_log:
                self.logger.debug(f"Executing confirmed command: {cmd}")

            # Execute the command
            await self._execute_gcode(f'RESPOND MSG="Numpad macros: Executing confirmed command {cmd}"')

            await self._execute_gcode(cmd)

            # Notify of execution
            await self.server.send_event(
                "numpad_macros:command_executed",
                {'command': cmd}
            )

        except Exception as e:
            self.logger.exception(f"Error executing command: {str(e)}")
            await self._execute_gcode(f'RESPOND TYPE=error MSG="Numpad macros: Error executing command: {str(e)}"')
        finally:
            # Clear pending command state
            self.pending_key = None
            self.pending_command = None
            if self.debug_log:
                self.logger.debug("Cleared pending command state")
            self._notify_status_update()

    # The updated _handle_adjustment method:
    async def _handle_knob_adjustment(self, key: str) -> None:
        """Handle immediate adjustment commands (up/down keys)"""
        try:
            if self.debug_log:
                self.logger.debug(f"Starting adjustment handling - Key: {key}")

            await self._check_klippy_state()
            if self.debug_log:
                self.logger.debug(
                    f"Klippy state checked - is_probing: {self.is_probing}, is_printing: {self._is_printing}")

            # Initialize cmd as None
            cmd = None

            if self.is_probing:
                # Get current Z position
                toolhead = await self._get_toolhead_position()
                current_z = toolhead['z']

                if self.debug_log:
                    self.logger.debug(f"Probe adjustment - Current Z: {current_z}")

                # Determine step size based on height
                if current_z < self.fine_tune_from:  # Use configurable threshold
                    # Fine adjustment mode using configurable multiplier
                    step_size = max(current_z * self.probe_fine_multiplier, self.probe_fine_min_step)
                    if key == 'key_up':
                        await self._execute_gcode('_FURTHER_KNOB_PROBE_MICRO_CALIBRATE')
                        cmd = f"TESTZ Z=+{step_size:.3f}"
                    else:
                        await self._execute_gcode('_NEARER_KNOB_PROBE_MICRO_CALIBRATE')
                        cmd = f"TESTZ Z=-{step_size:.3f}"
                else:
                    # Keep existing coarse adjustment logic
                    step_size = max(current_z * self.probe_coarse_multiplier, self.probe_min_step)
                    if key == 'key_up':
                        await self._execute_gcode('_FURTHER_KNOB_PROBE_CALIBRATE')
                        cmd = f"TESTZ Z=+{step_size:.3f}"
                    else:
                        await self._execute_gcode('_NEARER_KNOB_PROBE_CALIBRATE')
                        cmd = f"TESTZ Z=-{step_size:.3f}"

            elif self._is_printing:
                # Get Z height to determine mode
                toolhead = await self._get_toolhead_position()
                current_z = toolhead['z']

                if self.debug_log:
                    self.logger.debug(f"Print adjustment - Current Z: {current_z}")

                if current_z <= 1.0:
                    # Z offset adjustment during print
                    if key == 'key_up':
                        cmd = f"SET_GCODE_OFFSET Z_ADJUST={self.z_adjust_increment} MOVE=1"
                        adjustment = self.z_adjust_increment
                        await self._execute_gcode('_FURTHER_KNOB_FIRST_LAYER')  # Sound for up
                    else:
                        cmd = f"SET_GCODE_OFFSET Z_ADJUST=-{self.z_adjust_increment} MOVE=1"
                        adjustment = -self.z_adjust_increment
                        await self._execute_gcode('_NEARER_KNOB_FIRST_LAYER')   # Sound for down

                else:
                    # Speed adjustment using M220
                    # Get current speed factor
                    kapis: KlippyAPI = self.server.lookup_component('klippy_apis')
                    result = await kapis.query_objects({'gcode_move': None})
                    current_speed = result.get('gcode_move', {}).get('speed_factor', 1.0) * 100

                    increment = self.speed_settings["increment"]
                    max_speed = self.speed_settings["max"]
                    min_speed = self.speed_settings["min"]

                    # Calculate new speed value
                    if key == 'key_up':
                        new_speed = min(current_speed + increment, max_speed)
                        await self._execute_gcode('_INCREASE_KNOB_SPEED')  # Sound for speed up
                    else:
                        new_speed = max(current_speed - increment, min_speed)
                        await self._execute_gcode('_DEACREASE_KNOB_SPEED')  # Sound for speed down

                    cmd = f"M220 S{int(new_speed)}"

            else:
                # Standby mode: Volume control
                if key == 'key_up':
                    await self._execute_gcode('_INCREASE_KNOB_VOLUME')  # Sound for volume up
                    await self._execute_gcode('VOLUME_UP')
                else:
                    await self._execute_gcode('_DEACREASE_KNOB_VOLUME')  # Sound for volume down
                    await self._execute_gcode('VOLUME_DOWN')

                if self.debug_log:
                    self.logger.debug("No adjustment command was generated")

            # Execute the command only if one was set
            if cmd is not None:
                if self.debug_log:
                    self.logger.debug(f"Executing adjustment command: {cmd}")
                await self._execute_gcode(f'RESPOND MSG="Numpad macros: {cmd}"')
                await self._execute_gcode(cmd)
            else:
                if self.debug_log:
                    self.logger.debug("No adjustment command was generated")

        except Exception as e:
            msg = f"Error handling adjustment: {str(e)}"
            self.logger.exception(msg)
            await self._execute_gcode(f'RESPOND TYPE=error MSG="Numpad macros: {msg}"')
            raise

    async def _check_klippy_state(self) -> None:
        """Update internal state based on Klippy status"""
        kapis: KlippyAPI = self.server.lookup_component('klippy_apis')
        try:
            result = await kapis.query_objects({
                'print_stats': None,
                'gcode_macro CHECK_PROBE_STATUS': None  # Query our macro
            })

            if self.debug_log:
                self.logger.debug(f'Klippy state query result: {result}')
                self.logger.debug(f"CHECK_PROBE_STATUS result: {result.get('gcode_macro CHECK_PROBE_STATUS', {})}")

            probe_status = result.get('gcode_macro CHECK_PROBE_STATUS', {})
            previous_probing = self.is_probing
            self.is_probing = probe_status.get('monitor_active', False)

            if self.debug_log:
                self.logger.debug(f"Probe status change: {previous_probing} -> {self.is_probing}")

            self._is_printing = result.get('print_stats', {}).get('state', '') == 'printing'

            # Get probe status from the macro's variables
            probe_status = result.get('gcode_macro CHECK_PROBE_STATUS', {})
            self.is_probing = probe_status.get('monitor_active', False)

            if self.debug_log:
                await self._execute_gcode(
                    f'RESPOND MSG="Numpad macros: State update - '
                    f'Printing: {self._is_printing}, '
                    f'Probing: {self.is_probing}, '
                    f'Probe Status: {probe_status}"'
                )

            self._notify_status_update()

        except Exception as e:
            msg = f"{self.name}: Error fetching Klippy state: {str(e)}"
            await self._execute_gcode(f'RESPOND TYPE=error MSG="Numpad macros: {msg}"')
            self.logger.exception(msg)
            self._reset_state()
            raise self.server.error(msg, 503)

    def get_status(self) -> Dict[str, Any]:
        """Return component status"""
        return {
            'command_mapping': self.command_mapping,
            'query_mapping': self.initial_query_command_mapping,
            'pending_key': self.pending_key,
            'pending_command': self.pending_command,
            'is_printing': self._is_printing,
            'is_probing': self.is_probing,
            'no_confirm_keys': list(self.no_confirm_keys),
            'confirmation_keys': list(self.confirmation_keys)
        }

    def _notify_status_update(self) -> None:
        """Notify clients of status changes"""
        self.server.send_event(
            "numpad_macros:status_update",
            self.get_status()
        )

    def _restart_numpad_event_service(self):
        """Restart the numpad_event_service using systemctl"""
        try:
            self.logger.info("Restarting numpad_event_service...")
            subprocess.run(["systemctl", "restart", "numpad_event_service"], check=True)
            self.logger.info("numpad_event_service restarted successfully.")
        except subprocess.CalledProcessError as e:
            self.logger.error(f"Failed to restart numpad_event_service: {e}")

    async def _handle_ready(self):
        """Handle the server ready event by restarting the numpad_event_service"""
        self.logger.info("Handling server ready event.")
        self._restart_numpad_event_service()
        await self._check_klippy_state()

    async def _handle_shutdown(self):
        """Handle the server shutdown event"""
        self.logger.info("Handling server shutdown event.")
        self._reset_state()

    async def _delayed_save_z_offset(self) -> None:
        """Save the Z adjustment by modifying true_max_height"""
        try:
            # Wait for the delay period
            await asyncio.sleep(self.z_offset_save_delay)

            # Only proceed if this is the most recent adjustment
            if self._pending_z_offset_save:
                # Get current true_max_height
                kapis: KlippyAPI = self.server.lookup_component('klippy_apis')
                result = await kapis.query_objects({'save_variables': None})
                current_true_max = result.get('save_variables', {}).get('variables', {}).get('true_max_height', 0.0)
                
                # For positive adjustment (up), subtract from true_max_height
                # For negative adjustment (down), add to true_max_height
                new_true_max = float(current_true_max) - self._accumulated_z_adjust

                # Save the new true_max_height
                await self._execute_gcode(
                    f'SAVE_VARIABLE VARIABLE=true_max_height VALUE={new_true_max}'
                )

                if self.debug_log:
                    self.logger.debug(
                        f"Adjusted true_max_height: current({current_true_max}) adjusted by "
                        f"(-{self._accumulated_z_adjust}) = new({new_true_max})"
                    )

                # Reset tracking variables
                self._accumulated_z_adjust = 0.0
                self._pending_z_offset_save = False

                # Update park_z with new true_max_height
                await self._execute_gcode('UPDATE_PARK_Z')

        except Exception as e:
            self.logger.exception("Error saving Z adjustment")
            await self._execute_gcode(
                f'RESPOND TYPE=error MSG="Error saving Z adjustment: {str(e)}"'
            )

    def _reset_state(self) -> None:
        """Reset all state variables"""
        self.pending_key = None
        self.pending_command = None
        self._is_printing = False
        self.is_probing = False
        self._accumulated_z_adjust = 0.0
        self._pending_z_offset_save = False
        self._last_z_adjust_time = 0.0
        self._notify_status_update()

    async def _get_toolhead_position(self) -> Dict[str, float]:
        """Get current toolhead position"""
        kapis: KlippyAPI = self.server.lookup_component('klippy_apis')
        result = await kapis.query_objects({'toolhead': None})
        pos = result.get('toolhead', {}).get('position', [0., 0., 0., 0.])
        return {
            'x': pos[0], 'y': pos[1], 'z': pos[2], 'e': pos[3]
        }

    async def _execute_gcode(self, command: str) -> None:
        """Execute a gcode command"""
        kapis: KlippyAPI = self.server.lookup_component('klippy_apis')
        await kapis.run_gcode(command)

    async def _handle_status_request(
            self, web_request: WebRequest
    ) -> Dict[str, Any]:
        """Handle status request endpoint"""
        return {'status': self.get_status()}

def load_component(config: ConfigHelper) -> NumpadMacros:
    return NumpadMacros(config)