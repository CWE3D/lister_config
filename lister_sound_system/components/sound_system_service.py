import os
import logging
from pathlib import Path
from typing import Dict, Any


class SoundSystemService:
    def __init__(self, config):
        self.server = config.get_server()
        self.klippy = self.server.lookup_component('klippy_apis')

        # Configure paths
        self.sound_dir = Path(config.get('sound_directory',
                                       '/home/pi/lister_config/lister_sound_system/sounds')).expanduser().resolve()

        # Initialize sound cache
        self._sound_cache: Dict[str, str] = {}

        # Register API endpoints
        self.server.register_endpoint(
            "/server/sound/list", ['GET'], self._handle_list_request)
        self.server.register_endpoint(
            "/server/sound/play", ['POST'], self._handle_play_request)
        self.server.register_endpoint(
            "/server/sound/scan", ['POST'], self._handle_scan_request)
        self.server.register_endpoint(
            "/server/sound/info", ['GET'], self._handle_info_request)

        # Register notifications
        self.server.register_notification("sound_system:sound_played")
        self.server.register_notification("sound_system:sounds_updated")

        # Register startup handler
        self.server.register_event_handler(
            "server:klippy_ready", self._handle_ready)

        logging.info(f"Sound System Service initialized with dir: {self.sound_dir}")

    def _verify_sound_file(self, path: Path) -> bool:
        """Verify if file exists and is an MP3 file"""
        try:
            if not path.is_file():
                return False
            
            # Check file extension
            return path.suffix.lower() == '.mp3'
            
        except Exception as e:
            logging.error(f"Error verifying sound file {path}: {e}")
            return False

    async def _scan_sounds(self) -> Dict[str, str]:
        """Scan sound directory and update cache"""
        sounds: Dict[str, str] = {}

        try:
            if not self.sound_dir.exists():
                logging.warning(f"Sound directory not found: {self.sound_dir}")
                return sounds

            # Only scan if cache is empty or force scan requested
            if not self._sound_cache:
                # Scan for MP3 files
                for file_path in self.sound_dir.glob("*.mp3"):
                    if self._verify_sound_file(file_path):
                        sounds[file_path.stem] = str(file_path)

                self._sound_cache = sounds

                # Notify clients
                await self.server.send_event(
                    "sound_system:sounds_updated",
                    {'sounds': sounds}
                )

            return self._sound_cache

        except Exception as e:
            logging.exception(f"Error scanning sounds: {e}")

        return sounds

    async def _handle_ready(self) -> None:
        """Initialize when Klippy is ready"""
        logging.info("Sound System Service Ready")
        await self._scan_sounds()

    async def _handle_list_request(self, web_request) -> Dict[str, Any]:
        """Handle request to list available sounds"""
        # Return cached sounds if available
        if self._sound_cache:
            return {
                'sounds': self._sound_cache,
                'sound_dir': str(self.sound_dir)
            }
        
        # Scan if cache is empty
        sounds = await self._scan_sounds()
        return {
            'sounds': sounds,
            'sound_dir': str(self.sound_dir)
        }

    async def _handle_play_request(self, web_request) -> Dict[str, Any]:
        """Handle request to play a sound"""
        sound = web_request.get_str('sound')
        if not sound:
            raise self.server.error("No sound specified")

        logging.info(f"Received play request for sound: {sound}")

        try:
            # Attempt to play sound through Klipper
            cmd = f"PLAY_SOUND SOUND={sound}"
            await self.klippy.run_method(
                "gcode/script",
                {"script": cmd}
            )

            # Notify clients
            await self.server.send_event(
                "sound_system:sound_played",
                {'sound': sound}
            )

            return {
                'status': 'success',
                'sound': sound
            }

        except Exception as e:
            logging.exception(f"Failed to play sound {sound}")
            raise self.server.error(f"Failed to play sound: {str(e)}")

    async def _handle_scan_request(self, web_request) -> Dict[str, Any]:
        """Handle request to rescan sounds directory"""
        # Clear cache to force rescan
        self._sound_cache.clear()
        sounds = await self._scan_sounds()
        return {
            'status': 'success',
            'sounds': sounds,
            'sound_dir': str(self.sound_dir)
        }

    async def _handle_info_request(self, web_request) -> Dict[str, Any]:
        """Return information about the sound system"""
        audio_info = {'devices': []}

        try:
            # Get audio device information using amixer
            import asyncio
            proc = await asyncio.create_subprocess_exec(
                'amixer', '-l',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, _ = await proc.communicate()

            if stdout:
                audio_info['devices'] = [
                    line.decode().strip()
                    for line in stdout.splitlines()
                    if b'card' in line or b'mixer' in line
                ]

            # Add mpg123 version info
            proc = await asyncio.create_subprocess_exec(
                'mpg123', '--version',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, _ = await proc.communicate()
            if stdout:
                audio_info['mpg123_version'] = stdout.decode().split('\n')[0]

        except Exception as e:
            logging.error(f"Error getting audio info: {e}")

        return {
            'status': 'online',
            'sound_dir': str(self.sound_dir),
            'sound_count': len(self._sound_cache),
            'audio_system': audio_info,
            'player': 'mpg123'
        }

    async def close(self) -> None:
        """Clean up resources"""
        self._sound_cache.clear()


def load_component(config):
    return SoundSystemService(config)