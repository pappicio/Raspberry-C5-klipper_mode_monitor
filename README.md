# Raspberry-C5-klipper_mode_monitor

Unified monitoring and dashboard companion for the FlashForge Creator 5 and a Radxa ZERO 3W running Klipper.

The project combines the Radxa-side Klipper mode monitor and OpenCreator Dashboard in one application, one project directory, one systemd service and one HTTP server.

The Creator 5 communicates with this project through the separate OpenCreator API Server plugin.

## Architecture

### Creator 5 — OpenCreator API Server

Repository:

https://github.com/pappicio/api-server

The API Server runs on the Creator 5 and provides the printer-side communication interface.

It handles:

- Creator 5 printer mode detection.
- Switching between SoC and Tunneled modes.
- Communication with the Radxa.
- Toolchange counter synchronization.
- Nozzle usage-time synchronization.
- Radxa SoC temperature reception.
- Mode-switch wait page and automatic redirection after reboot.

Requirements:

- OpenCreator plugin environment.
- Script Runner installed and working.
- Correct Radxa IP address configured in the API Server.

The API Server stores its configuration in:

    /usr/data/opencreator/api-server.json

The configuration key for the Radxa address is:

    radxa_host

The Creator 5 API Server listens on port `8765`.

### Radxa ZERO 3W — Unified application

The Radxa project runs alongside Klipper and Moonraker.

It combines:

- Klipper mode monitoring.
- HTTP endpoints for the Creator 5.
- Toolchange counter storage and synchronization.
- Nozzle usage-time storage and synchronization.
- Firmware calibration data synchronization.
- SoC temperature transmission.
- OpenCreator Dashboard.
- Custom project information.
- Printer screen switching controls.

The application uses:

    One project directory
    One Python process
    One systemd service
    One HTTP port: 8765

The HTTP server listens on:

    0.0.0.0:8765

The Creator 5 and Radxa use the same port number on different devices.

## Project structure

    klipper_mode_monitor/
    ├── backend/
    │   ├── custom_projects.py
    │   └── dashboard_server.py
    ├── frontend/
    │   ├── index.html
    │   ├── dashboard.js
    │   └── dashboard.css
    ├── integration/
    │   └── opencreator-inject.js
    ├── config.json
    ├── install.sh
    ├── uninstall.sh
    ├── klipper_mode_monitor.py
    └── README.md

The installer and application use the project directory dynamically.

## Dashboard integration

The Dashboard is integrated into the existing Mainsail and Fluidd pages through:

    integration/opencreator-inject.js

The integration script adds the OpenCreator interface to the existing printer UI.

Its Dashboard address is derived dynamically from the current browser protocol and hostname, using port `8765`.

No additional Dashboard port is required.

The integration uses the existing Mainsail and Fluidd web-server injection configuration. The project installer does not modify Nginx, Mainsail, Fluidd or Moonraker configuration files.

The Dashboard is served by the same HTTP server as the Klipper mode monitor.

## Communication and synchronization

The communication flow is:

    FlashForge Creator 5
           |
           | HTTP API :8765
           |
    Radxa ZERO 3W
           |
           | Unified HTTP server :8765
           |
    ┌──────────────────────────────┐
    │ Klipper Mode Monitor         │
    │ OpenCreator Dashboard        │
    │ Synchronization API          │
    └──────────────────────────────┘
           |
           | Local data files
           |
    Klipper configuration directory

### Toolchange counters

The synchronized file is:

    ~/printer_data/config/toolchanges.txt

It stores the counters for:

- Total
- T0
- T1
- T2
- T3

### Nozzle usage time

The synchronized file is:

    ~/printer_data/config/c5_misc_variables.cfg

The synchronized variables are:

- nozzle_seconds_t0
- nozzle_seconds_t1
- nozzle_seconds_t2
- nozzle_seconds_t3

### Synchronization direction

Synchronization takes place before the mode switch and reboot.

| Requested mode | Synchronization direction |
| --- | --- |
| SoC | Radxa → Creator 5 |
| Tunneled | Creator 5 → Radxa |

The Creator 5 API Server validates received data before updating destination files.

Existing data files are backed up before modification.

### Firmware calibration

The Radxa exposes firmware calibration data through:

    GET /api/firmware_res
    POST /api/firmware_res

The Creator 5 API Server uses these endpoints to synchronize calibration files.

### Temperature

The Radxa monitor periodically sends the SoC temperature to the Creator 5 API Server through:

    /api/pitemp/

## Requirements

### Creator 5

- FlashForge Creator 5.
- OpenCreator API Server plugin.
- Script Runner plugin.
- Network connectivity to the Radxa.

### Radxa ZERO 3W

- Linux operating system.
- Klipper and Moonraker.
- Python 3.
- systemd.
- sudo permissions.
- Network connectivity to the Creator 5.

Both devices must be reachable over the network.

## Installation

### Creator 5

Install and configure the OpenCreator API Server separately:

https://github.com/pappicio/api-server

Verify that:

- Script Runner is installed and working.
- The API Server is installed and enabled.
- Its `radxa_host` configuration contains the correct Radxa IPv4 address.
- The API Server is listening on port `8765`.

The Creator 5 API Server remains a separate component.

### Radxa

Run the installer as the regular Linux user from the project directory:


cd ~/printer_data/config &&
git clone https://github.com/pappicio/Raspberry-C5-klipper_mode_monitor.git klipper_mode_monitor &&
cd klipper_mode_monitor &&
bash install.sh


The installer:

1. Validates the existing `config.json`.
2. Checks Python syntax.
3. Checks the required sudo permissions.
4. Creates a restricted Klipper restart permission only when required.
5. Creates the systemd service definition.
6. Enables and starts the unified application.

The installer does not:

- Install Python packages or other dependencies.
- Modify Klipper configuration files.
- Modify Moonraker configuration.
- Create Klipper macros.
- Modify Mainsail or Fluidd navigation.
- Modify Nginx configuration.
- Restart Klipper.
- Overwrite the existing application configuration.

## Configuration

The Radxa configuration file is:

    config.json

Example:

    {
        "creator_ip": "192.168.1.194"
    }

The installer validates the existing configuration and preserves its contents.

The Creator 5 API Server has its own configuration:

    /usr/data/opencreator/api-server.json

It stores the Radxa address using:

    radxa_host

These configuration files belong to separate devices and applications.

## HTTP endpoints

### Radxa — Monitor

Base address:

    http://RADXA_IP:8765

Endpoints include:

- `GET /status`
- `GET /api/toolchanges`
- `POST /api/toolchanges`
- `GET /api/nozzle_hours`
- `POST /api/nozzle_hours`
- `GET /api/firmware_res`
- `POST /api/firmware_res`

### Radxa — Dashboard

The Dashboard is served by the same HTTP server.

Frontend:

- `GET /`
- `GET /index.html`
- `GET /dashboard.js`
- `GET /dashboard.css`

Dashboard API:

- `GET /api/dashboard`
- `GET /api/custom-projects`
- `GET /api/synchronization`
- `GET /api/go-soc`
- `POST /api/synchronization/<item>`
- `POST /api/screen/grumpy`
- `POST /api/screen/helix`

### Creator 5 — API Server

Base address:

    http://CREATOR_IP:8765

Relevant endpoints include:

- `GET /api/status`
- `POST /api/pitemp/`
- `GET /go_tunneled`
- `GET /go_soc`

Mode-switch endpoints belong to the Creator 5 API Server.

The API Server performs the required synchronization before changing mode and rebooting the printer.

## Network access

The Radxa HTTP server listens on all IPv4 interfaces.

Access is restricted to:

- Localhost.
- The configured Creator 5 IP address.
- Networks detected from the Radxa default-route interface.

The application detects the LAN network automatically at startup.

## Service management

Service name:

    klipper-mode-monitor.service

Check status:

    sudo systemctl status klipper-mode-monitor.service

Follow logs:

    sudo journalctl -u klipper-mode-monitor.service -f

Restart the unified application:

    sudo systemctl restart klipper-mode-monitor.service

Stop:

    sudo systemctl stop klipper-mode-monitor.service

The monitor and Dashboard run in the same process. Restarting the service restarts both components.

## Klipper restart permissions

The application runs as the regular Linux user who installs it.

When required, the installer configures this restricted passwordless command:

    /usr/bin/systemctl restart klipper.service

The permission is used by the existing monitor functionality when a Klipper restart is required.

The installer does not restart Klipper during installation.

## Data preservation

The application uses existing Klipper data files, including:

    ~/printer_data/config/toolchanges.txt
    ~/printer_data/config/c5_misc_variables.cfg

These files contain persistent printer data.

The installer does not overwrite them.

Uninstallation does not delete these files.

## Uninstallation

Run the uninstaller as the regular installation user:

    ./uninstall.sh

Confirm by typing:

    REMOVE

The uninstaller:

- Stops and disables the unified systemd service.
- Removes the project systemd service definition.
- Removes the installer-managed sudoers rule when it can be verified.
- Preserves application files.
- Preserves `config.json`.
- Preserves Klipper configuration and data files.

## Important

The Radxa unified application and the Creator 5 OpenCreator API Server are complementary components.

Both are required for the complete Creator 5 and Radxa integration, including mode switching, monitoring and data synchronization.
