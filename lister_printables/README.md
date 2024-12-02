# Lister Printables Plugin

## Version 2.0.0

## Overview

The Lister Printables plugin is a specialized tool designed exclusively for Lister 3D printers. This plugin enhances your printing experience by providing easy access to the latest sliced gcode files for every part of your Lister printer.

## Key Features

- Automatic updates of printable parts
- Easy access to the latest gcode files
- Regular metadata scans to keep your file information up-to-date
- Seamless integration with your Lister printer's interface

## Purpose

The primary purpose of this plugin is to allow Lister printer users to easily print updated parts as soon as they are released. This ensures that your printer always has access to the most recent improvements and modifications, keeping your Lister printer in optimal condition.

## How It Works

The Lister Printables plugin operates through several key components:

1. **Installation Script**: This script sets up the plugin and its dependencies on your Lister printer.

2. **Cron Job**: The installation process creates a cron job that runs daily. This automated task ensures regular updates and maintenance of the plugin.

3. **Metadata Scanning**: A Python script runs daily to scan all gcode files in the Lister Printables directory. It updates the metadata for each file, which includes information like print time, filament usage, and thumbnail images.

4. **File Management**: The plugin maintains a directory of the latest gcode files for all printable Lister printer parts. These files are regularly updated from the official Lister repository.

5. **Integration with Moonraker**: The plugin interacts with Moonraker (the API for Klipper) to provide seamless access to the printable files through your printer's web interface.

This automated system ensures that your Lister printer always has access to the most up-to-date parts without requiring manual intervention.

## Installation

To install or update the Lister Printables plugin, you can use the following command. This command will work from any computer that has SSH access to your Lister printer.

```bash
ssh pi@printername.local 'bash -s' << EOF
  curl -fsSL https://raw.githubusercontent.com/CWE3D/lister_printables/main/install.sh -o /tmp/install.sh && 
  chmod +x /tmp/install.sh && 
  /tmp/install.sh
EOF
```

### What the Command Does

This command performs the following actions:

1. Connects to your Lister printer via SSH.
2. Downloads the latest installation script from the Lister Printables GitHub repository.
3. Makes the script executable.
4. Runs the installation script, which will either install the plugin for the first time or update an existing installation.

## Post-Installation

After running the installation command, the Lister Printables plugin will be set up on your printer. The installation process includes several key steps:

1. **Directory Setup**: The script creates necessary directories for the plugin if they don't already exist.

2. **File Download**: It downloads or updates the plugin files from the official GitHub repository.

3. **Python Dependencies**: Any required Python packages are installed or updated.

4. **Cron Job Setup**: A daily cron job is set up to run the metadata scanning script. This job is scheduled to run at 2:00 AM every day.

5. **Moonraker Configuration**: The script checks if the Lister Printables configuration is already present in the moonraker.conf file. If not, it appends the necessary configuration:
This configuration allows Moonraker to manage updates for the Lister Printables plugin.

6. **Initial Metadata Scan**: The script triggers an initial metadata scan of all gcode files in the Lister Printables directory.

7. **Installation Flag**: Once the installation is complete, it creates a flag file to indicate successful installation.

## Usage

After installation, the Lister Printables plugin works automatically in the background. You don't need to manually interact with it for regular operation. Here's what you can expect:

1. **Automatic Updates**: The plugin will automatically check for and download updates to printable parts.

2. **Daily Metadata Scans**: Every day at 2:00 AM, the plugin will scan all gcode files and update their metadata.

3. **Web Interface Integration**: You'll see the latest printable parts available in your printer's web interface (e.g., Mainsail or Fluidd).

4. **Printing Parts**: To print an updated part, simply select it from your printer's web interface as you would with any other gcode file.

If you need to manually trigger a metadata scan or check the plugin's status, you can do so through your printer's terminal interface or via SSH.

## Updating the Plugin

To update the Lister Printables plugin, you can run the same installation command that you used for the initial installation. The script will detect the existing installation and perform an update instead of a fresh install.

## Troubleshooting

If you encounter any issues with the Lister Printables plugin, here are some steps you can take:

1. Check the log files in the `/home/pi/printer_data/logs/` directory for any error messages.
2. Ensure that your printer has a stable internet connection for downloading updates.
3. Verify that the cron job is set up correctly by running `crontab -l` in the terminal.
4. Check the moonraker.conf file to ensure the Lister Printables configuration is present and correct.

If problems persist, please reach out to Lister 3D printer support with the relevant log files and a description of the issue.