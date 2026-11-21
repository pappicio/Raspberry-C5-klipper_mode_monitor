# Raspberry-C5-klipper_mode_monitor

A companion component for the FlashForge Creator 5 and a Radxa ZERO 3W running Klipper.

This project is designed to work together with the **OpenCreator API Server** plugin installed on the Creator 5.

The two components are complementary and must both be installed. The Radxa monitor alone cannot provide the complete functionality, and the Creator 5 API Server alone cannot provide the Radxa (Raspberry PI)-side monitoring and synchronization services.



# Prerequisites — OpenCreator Tunnel

Important: Install OpenCreator Tunnel before installing Mode Monitor.

Repository:
https://github.com/FlashForge-C5-Modding-Group/opencreator-tunnel

OpenCreator Tunnel provides the Klipper/Moonraker environment and connectivity required by the Creator 5 integration on the Raspberry Pi.

Mode Monitor depends on this environment to access the remote Klipper and Moonraker services. Without OpenCreator Tunnel properly installed and configured, Mode Monitor and the Creator 5 synchronization features will not work.

Required installation order

OpenCreator Tunnel — Install and configure it on the Raspberry Pi first.

Mode Monitor — Install it on the Raspberry Pi after OpenCreator Tunnel is working.

Script Runner — Install it on the Creator 5.

API Server — Install it on the Creator 5 and configure the Raspberry Pi IP address.

All components must be installed and operational for the complete SoC / Tunneled mode switching integration.




## Companion Project — OpenCreator API Server

Raspberry-C5-klipper_mode_monitor is designed to work together with the **OpenCreator API Server** plugin installed on the FlashForge Creator 5.

Repository:

https://github.com/pappicio/api-server

Both components are complementary and required for the complete integration.

### How the two components work together

- **Mode Monitor (Raspberry Pi / Remote Host):** Runs alongside Klipper, monitors the remote system, provides HTTP endpoints, stores synchronization data, and reports SoC temperature.
- **API Server (Creator 5):** Provides the printer-side API, handles switching between SoC and Tunneled modes, coordinates data synchronization, and manages the transition between the two systems.

Before switching modes, the API Server coordinates the synchronization of toolchange counters and nozzle usage data between the Creator 5 and the remote host.

### Installation requirements

1. Install **Mode Monitor** on the Raspberry Pi or compatible Linux host running Klipper.
2. Install **Script Runner** on the Creator 5.
3. Install **OpenCreator API Server** on the Creator 5.
4. Configure the IP addresses of both devices.

Installing only one component does not provide the complete functionality.






## Project components

### 1. Creator 5 — OpenCreator API Server

Repository:

https://github.com/pappicio/api-server

The API Server plugin runs on the Creator 5 and provides the communication interface between the printer and the Radxa.

It handles:

- Creator 5 printer mode detection.
- Switching between SoC and Tunneled modes.
- Communication with the Radxa monitor.
- Toolchange counter synchronization.
- Nozzle usage-time synchronization.
- Radxa SoC temperature reception.
- Mode-switch wait page and automatic redirection after reboot.

**Requirements:**

- OpenCreator plugin environment.
- Script Runner plugin installed and working.
- Correct Radxa IP address configured during API Server installation.

The API Server installer asks for the Radxa IPv4 address and saves it in:

    /usr/data/opencreator/api-server.json

The configuration contains the `remote_host` value.

The API Server listens on port `8765`.

### 2. Radxa ZERO 3W — Raspberry-C5-klipper_mode_monitor

This project runs on the Radxa alongside Klipper.

It provides:

- HTTP endpoints used by the Creator 5 API Server.
- Toolchange counter storage and synchronization.
- Nozzle usage-time storage and synchronization.
- Creator 5 mode monitoring.
- SoC temperature transmission to the Creator 5.
- Klipper restart handling when switching to Tunneled mode.

The monitor listens on:

    0.0.0.0:8765

The Creator 5 API Server and the Radxa monitor both use port `8765`, but they run on different devices.

## Communication and synchronization

Both components must be installed and configured with the correct IP addresses.

The communication flow is:

    FlashForge Creator 5
           |
           | HTTP API :8765
           |
    Radxa ZERO 3W
           |
           | HTTP API :8765
           |
    Klipper data files

### Toolchange counters

The following file is synchronized between the two devices:

    toolchanges.txt

It contains the counters for:

- Total
- T0
- T1
- T2
- T3

### Nozzle usage time

The following file is synchronized:

    c5_misc_variables.cfg

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

The API Server validates the received data before updating the destination files.

The existing files are backed up before being modified.

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

Installation requires two separate steps.

### Step 1 — Install the Creator 5 API Server

On the Creator 5:

1. Install and enable Script Runner.
2. Install the OpenCreator API Server plugin:

   https://github.com/pappicio/api-server

3. Run the API Server installer.
4. When requested, enter the Radxa IPv4 address.
5. Verify that the API Server starts successfully.

The installer stores the Radxa address in:

    /usr/data/opencreator/api-server.json

The expected configuration key is:

    remote_host

### Step 2 — Install the Radxa monitor


## Install with one command from shell


### git clone --depth 1 https://github.com/pappicio/Raspberry-C5-klipper_mode_monitor.git /tmp/klipper-mode-monitor && bash /tmp/klipper-mode-monitor/install.sh

On the Radxa, run the installer as the regular Linux user:

    chmod +x install.sh
    ./install.sh

The installer asks only for the Creator 5 IP address.

Default address:

    192.168.1.194

The following settings are fixed:

- Creator API port: `8765`
- Monitor HTTP port: `8765`
- HTTP bind address: `0.0.0.0`

The installer creates:

    config.json

With this structure:

    {
        "creator_ip": "192.168.1.194"
    }

It automatically installs and enables:

    klipper-mode-monitor.service

The service runs under the Linux user who launches the installer.

## Moonraker navigation menu

Both devices can have an additional navigation entry to switch between SoC and Tunneled modes.

The buttons call the Creator 5 API Server directly.

Replace `CREATOR_IP` with the actual Creator 5 IP address.

Merge each entry into the existing navigation JSON array. Do not overwrite the entire file.

### Creator 5 — Switch to Tunneled

File:

    /usr/data/opencreator/klipper/config/.theme/navi.json

Add this entry:

    {
        "title": "Tunneled",
        "href": "http://CREATOR_IP:8765/go_tunneled",
        "target": "_self",
        "position": 90
    }

This button requests the switch to Tunneled mode.

### Radxa — Switch to SoC

File:

    ~/printer_data/config/.theme/navi.json

Add this entry:

    {
        "title": "SoC Mode",
        "href": "http://CREATOR_IP:8765/go_soc",
        "target": "_self",
        "position": 90
    }

This button requests the switch back to SoC mode.

### Mode-switch endpoints

The following endpoints belong to the Creator 5 API Server:

- `GET /go_tunneled`
- `GET /go_soc`

The API Server performs the required synchronization before changing mode and rebooting the printer.

It also provides a wait page that checks when the destination system becomes available and redirects the browser automatically.

## API endpoints

### Creator 5 API Server

Base address:

    http://CREATOR_IP:8765

Relevant endpoints:

- `GET /api/status`
- `POST /api/pitemp/`
- `GET /go_tunneled`
- `GET /go_soc`

### Radxa monitor

Base address:

    http://REMOTE_IP:8765

Endpoints:

- `GET /status`
- `GET /api/toolchanges`
- `POST /api/toolchanges`
- `GET /api/nozzle_hours`
- `POST /api/nozzle_hours`

The Radxa monitor does not provide the mode-switch endpoints. Those belong to the Creator 5 API Server.

## Configuration

The Radxa monitor configuration is stored in:

    config.json

Only the Creator 5 IP address is required:

    {
        "creator_ip": "192.168.1.194"
    }

The Creator 5 API Server has its own configuration file:

    /usr/data/opencreator/api-server.json

It stores the Radxa address using:

    remote_host

These are separate configuration files on separate devices.

## Service management

Check service status:

    sudo systemctl status klipper-mode-monitor

Follow logs:

    sudo journalctl -u klipper-mode-monitor -f

Restart:

    sudo systemctl restart klipper-mode-monitor

Stop:

    sudo systemctl stop klipper-mode-monitor

## Klipper restart permissions

The monitor runs as the Linux user who launches the installer.

That user must be allowed to execute the following command without password interaction:

    sudo -n /usr/bin/systemctl restart klipper.service

The installer checks the available sudo permissions and configures a restricted rule when necessary.

## Data files

The monitor uses the following Klipper configuration files:

    ~/printer_data/config/toolchanges.txt
    ~/printer_data/config/c5_misc_variables.cfg

These files contain persistent printer data.

Uninstallation does not delete or remove these files.

## Uninstallation

Run the uninstaller as the regular installation user:

    ./uninstall.sh

Type:

    REMOVE

The uninstaller:

- Stops and disables the systemd service.
- Removes the systemd service definition.
- Removes the installer-managed sudoers rule, if applicable.
- Preserves application files.
- Preserves all Klipper data files.

## Important

**Raspberry-C5-klipper_mode_monitor and OpenCreator API Server are designed to work together.**

Both components are required for the complete Creator 5 / Radxa integration, including mode switching, toolchange synchronization and nozzle usage-time synchronization.


## Mainsail and Fluidd navigation

The installer automatically adds a **SoC Mode** entry to the Mainsail
sidebar through `printer_data/config/.theme/navi.json`. Selecting it
calls the Creator 5 API Server `/go_soc` endpoint.

Fluidd 1.37.7 does not support custom sidebar navigation entries.
Adding a navigation object to the Moonraker database alone does not
make the entry appear, so no Fluidd database modification is attempted.

## SOC_MODE Klipper macro

The installer creates `printer_data/config/oc_macros.cfg` if it does
not exist and ensures that `printer.base.cfg` includes it.

The file contains the `SOC_MODE` macro and its dedicated
`gcode_shell_command`, configured with the Creator 5 IP address supplied
during installation. The macro calls the Creator 5 API Server `/go_soc`
endpoint.

This provides a `SOC_MODE` command from the Klipper console in both
Mainsail and Fluidd, independently of sidebar navigation.

Existing contents of `oc_macros.cfg` are preserved. The installer
does not overwrite an existing file.
