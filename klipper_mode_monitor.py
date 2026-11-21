#!/usr/bin/env python3

import json
import ipaddress
import os
import re
import stat
import tempfile
import time
import urllib.request
import subprocess
import shutil
import threading

from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

# ============================================================
# CONFIGURATION
# ============================================================

CONFIG_FILE = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "config.json"
)

try:
    with open(CONFIG_FILE, "r", encoding="utf-8") as config_file:
        CONFIG = json.load(config_file)

    CREATOR_IP = str(ipaddress.IPv4Address(CONFIG["creator_ip"]))
    API_PORT = 8765
    PORT = 8765

except (OSError, KeyError, TypeError, ValueError, json.JSONDecodeError) as exc:
    raise SystemExit(f"Invalid or missing configuration file {CONFIG_FILE}: {exc}")

API = f"http://{CREATOR_IP}:{API_PORT}/api/status"

INTERVAL = 5
DELAY = 20
API_RETURN_TIMEOUT = 180

HOST = "0.0.0.0"

TOOLCHANGES_FILE = os.path.join(os.path.expanduser("~"), "printer_data/config/toolchanges.txt")
TOOLCHANGES_PATH = "/api/toolchanges"
VARIABLES_FILE = os.path.join(os.path.expanduser("~"), "printer_data/config/c5_misc_variables.cfg")
NOZZLE_HOURS_PATH = "/api/nozzle_hours"

RADXA_TEMP_FILE = "/sys/class/thermal/thermal_zone0/temp"
CREATOR_TEMP_URL = f"http://{CREATOR_IP}:{API_PORT}/api/pitemp/"

MAX_TOOLCHANGES_SIZE = 4096

ALLOWED_CLIENTS = {
    CREATOR_IP,
    "127.0.0.1"
}
# ============================================================
# LOGGING
# ============================================================

def log(message):
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{now}] {message}", flush=True)


# ============================================================
# TOOLCHANGES VALIDATION
# ============================================================

def validate_toolchanges(content):

    if isinstance(content, bytes):
        content = content.decode("utf-8")

    if len(content.encode("utf-8")) > MAX_TOOLCHANGES_SIZE:
        raise ValueError("toolchanges.txt is too large")

    values = {}

    for line in content.splitlines():

        if not line.strip():
            continue

        match = re.fullmatch(
            r"\s*(Total|T[0-3])\s*:\s*(\d+)\s*",
            line
        )

        if not match:
            raise ValueError("Invalid toolchanges.txt format")

        key = match.group(1)

        if key in values:
            raise ValueError("Duplicate value: " + key)

        values[key] = int(match.group(2))

    required = ("Total", "T0", "T1", "T2", "T3")

    if any(key not in values for key in required):
        raise ValueError("Incomplete toolchanges.txt")

    if values["Total"] != sum(
        values[key] for key in ("T0", "T1", "T2", "T3")
    ):
        raise ValueError("Total does not match the sum of T0-T3")

    return values


# ============================================================
# TOOLCHANGES FILE
# ============================================================

def read_nozzle_hours():
    values = {}

    with open(VARIABLES_FILE, "r", encoding="utf-8") as f:
        for line in f:
            match = re.fullmatch(
                r"\s*nozzle_seconds_t([0-3])\s*=\s*(\d+)\s*",
                line
            )
            if match:
                values["nozzle_seconds_t" + match.group(1)] = int(match.group(2))

    required = [f"nozzle_seconds_t{i}" for i in range(4)]
    if any(key not in values for key in required):
        raise ValueError("Variabili nozzle_seconds_t0..t3 incomplete")

    return values


def atomic_write_nozzle_hours(values):

    keys = ["nozzle_seconds_t%d" % i for i in range(4)]

    if not isinstance(values, dict):
        raise ValueError("Invalid nozzle hours format")

    for key in keys:
        value = values.get(key)
        if isinstance(value, bool) or not isinstance(value, int) or value < 0:
            raise ValueError("Invalid value for " + key)

    with open(VARIABLES_FILE, "r", encoding="utf-8") as f:
        lines = f.readlines()

    found = dict((key, 0) for key in keys)
    updated = []

    for line in lines:
        replaced = False

        for key in keys:
            match = re.match(
                r"^(\s*" + re.escape(key) + r"\s*=\s*)\d+(\s*(?:#.*)?)(\r?\n)?$",
                line
            )

            if match:
                found[key] += 1
                updated.append(
                    match.group(1) + str(values[key]) +
                    match.group(2) + (match.group(3) or "")
                )
                replaced = True
                break

        if not replaced:
            updated.append(line)

    for key, count in found.items():
        if count != 1:
            raise ValueError(
                "%s deve comparire una sola volta (trovato %d)" % (key, count)
            )

    content = "".join(updated).encode("utf-8")

    with open(VARIABLES_FILE, "rb") as f:
        previous = f.read()

    if previous == content:
        return False

    file_stat = os.stat(VARIABLES_FILE)
    shutil.copy2(VARIABLES_FILE, VARIABLES_FILE + ".bak")

    directory = os.path.dirname(VARIABLES_FILE)
    fd, temporary_path = tempfile.mkstemp(
        prefix=".nozzle-hours-",
        suffix=".tmp",
        dir=directory
    )

    try:
        with os.fdopen(fd, "wb") as f:
            f.write(content)
            f.flush()
            os.fsync(f.fileno())

        os.chown(temporary_path, file_stat.st_uid, file_stat.st_gid)
        os.chmod(temporary_path, stat.S_IMODE(file_stat.st_mode))
        os.replace(temporary_path, VARIABLES_FILE)

    except Exception:
        try:
            os.unlink(temporary_path)
        except OSError:
            pass
        raise

    return True


def read_toolchanges():

    with open(TOOLCHANGES_FILE, "rb") as f:
        content = f.read(MAX_TOOLCHANGES_SIZE + 1)

    validate_toolchanges(content)

    return content



def read_radxa_temperature():

    with open(RADXA_TEMP_FILE, "r") as f:
        value = f.read().strip()

    if not value.isdigit():
        raise ValueError("Invalid SoC temperature value")

    return value

def send_radxa_temperature():
    while True:
        try:
            temperature = read_radxa_temperature()
            request = urllib.request.Request(
                CREATOR_TEMP_URL,
                data=temperature.encode("utf-8"),
                headers={"Content-Type": "text/plain"},
                method="POST"
            )
            with urllib.request.urlopen(request, timeout=5) as response:
                response.read()
        except Exception as exc:
            log("Error sending SoC temperature to Creator: %s" % exc)
        time.sleep(1)


def atomic_write_toolchanges(content):

    data = content.encode("utf-8") if isinstance(content, str) else content

    validate_toolchanges(data)

    if not os.path.isfile(TOOLCHANGES_FILE):
        raise RuntimeError("toolchanges.txt file not found")

    with open(TOOLCHANGES_FILE, "rb") as f:
        previous = f.read(MAX_TOOLCHANGES_SIZE + 1)

    if previous == data:
        return False

    file_stat = os.stat(TOOLCHANGES_FILE)

    # Backup creato dall'utente pi
    shutil.copy2(
        TOOLCHANGES_FILE,
        TOOLCHANGES_FILE + ".bak"
    )

    directory = os.path.dirname(TOOLCHANGES_FILE)

    fd, temporary_path = tempfile.mkstemp(
        prefix=".toolchanges-",
        suffix=".tmp",
        dir=directory
    )

    try:

        with os.fdopen(fd, "wb") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())

        os.chmod(
            temporary_path,
            stat.S_IMODE(file_stat.st_mode)
        )

        os.replace(
            temporary_path,
            TOOLCHANGES_FILE
        )

    except Exception:

        try:
            os.unlink(temporary_path)
        except OSError:
            pass

        raise

    return True


# ============================================================
# HTTP SERVER
# ============================================================

class ToolchangesHandler(BaseHTTPRequestHandler):

    server_version = "Creator5Toolchanges/1.0"

    def log_message(self, fmt, *args):

        log("[HTTP] %s - %s" % (
            self.client_address[0],
            fmt % args
        ))

    def send_json(self, code, data):

        body = json.dumps(
            data,
            ensure_ascii=False
        ).encode("utf-8")

        self.send_response(code)
        self.send_header(
            "Content-Type",
            "application/json; charset=utf-8"
        )
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_text(self, code, text):

        body = text.encode("utf-8")

        self.send_response(code)
        self.send_header(
            "Content-Type",
            "text/plain; charset=utf-8"
        )
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def check_access(self):

        address = self.client_address[0]

        if address not in ALLOWED_CLIENTS:

            self.send_json(403, {
                "success": False,
                "error": "Access denied"
            })

            return False

        return True

    def do_GET(self):

        if not self.check_access():
            return

        path = urlparse(self.path).path

        # Legacy endpoint compatibility
        if path == "/status":

            mode = get_mode(log_errors=False)

            if mode is None:
                self.send_text(503, "unknown")
            else:
                self.send_text(
                    200,
                    "on" if mode == "tunneled" else "off"
                )

            return



        if path == NOZZLE_HOURS_PATH:
            try:
                body = json.dumps(read_nozzle_hours()).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                self.wfile.write(body)
                log("Nozzle hours values sent to Creator")
            except Exception as exc:
                log("Error reading nozzle hours: %s" % exc)
                self.send_json(500, {"success": False, "error": str(exc)})
            return

        if path != TOOLCHANGES_PATH:

            self.send_json(404, {
                "success": False,
                "error": "Endpoint not found"
            })

            return

        try:

            content = read_toolchanges()

            self.send_response(200)
            self.send_header(
                "Content-Type",
                "text/plain; charset=utf-8"
            )
            self.send_header(
                "Content-Length",
                str(len(content))
            )
            self.send_header("Cache-Control", "no-store")
            self.end_headers()

            self.wfile.write(content)

            log("toolchanges.txt sent to Creator")

        except Exception as exc:

            log("Error reading toolchanges.txt: %s" % exc)

            self.send_json(500, {
                "success": False,
                "error": str(exc)
            })

    def do_POST(self):

        if not self.check_access():
            return

        path = urlparse(self.path).path

        if path == NOZZLE_HOURS_PATH:
            try:
                length = int(self.headers.get("Content-Length", "0"))

                if length <= 0 or length > 1024:
                    raise ValueError("Invalid request size")

                content = self.rfile.read(length)
                if len(content) != length:
                    raise ValueError("Incomplete transfer")

                values = json.loads(content.decode("utf-8"))
                changed = atomic_write_nozzle_hours(values)

                log("Nozzle hours received from Creator (changed=%s)" % changed)

                self.send_json(200, {
                    "success": True,
                    "changed": changed,
                    "values": values
                })

            except Exception as exc:
                log("Error saving nozzle hours: %s" % exc)
                self.send_json(400, {
                    "success": False,
                    "error": str(exc)
                })

            return

        if path != TOOLCHANGES_PATH:
            self.send_json(404, {
                "success": False,
                "error": "Endpoint not found"
            })
            return

        try:

            length = int(
                self.headers.get("Content-Length", "0")
            )

            if length <= 0 or length > MAX_TOOLCHANGES_SIZE:
                raise ValueError("Invalid request size")

            content = self.rfile.read(length)

            if len(content) != length:
                raise ValueError("Incomplete transfer")

            values = validate_toolchanges(content)

            changed = atomic_write_toolchanges(content)

            log(
                "toolchanges.txt received from Creator "
                "(changed=%s, Total=%s)" %
                (changed, values["Total"])
            )

            self.send_json(200, {
                "success": True,
                "changed": changed,
                "values": values
            })

        except Exception as exc:

            log("Error saving toolchanges.txt: %s" % exc)

            self.send_json(400, {
                "success": False,
                "error": str(exc)
            })


# ============================================================
# START TOOLCHANGES SERVER
# ============================================================

def start_toolchanges_server():

    server = ThreadingHTTPServer(
        (HOST, PORT),
        ToolchangesHandler
    )

    server.daemon_threads = True

    thread = threading.Thread(
        target=server.serve_forever,
        name="toolchanges-http",
        daemon=True
    )

    thread.start()

    log("Toolchanges server listening on %s:%s" % (HOST, PORT))

    return server


# ============================================================
# CREATOR MODE
# ============================================================

def get_mode(log_errors=True):

    try:

        req = urllib.request.Request(
            API,
            headers={"Cache-Control": "no-cache"}
        )

        with urllib.request.urlopen(req, timeout=5) as response:

            data = json.loads(
                response.read().decode("utf-8")
            )

            mode = data.get("mode")

            return mode if mode in ("soc", "tunneled") else None

    except Exception as exc:

        if log_errors:
            log("Creator API unreachable: %s" % exc)

        return None


# ============================================================
# KLIPPER RESTART
# ============================================================

def restart_klipper():

    log("Restarting Klipper on Radxa...")

    try:

        result = subprocess.run(
            [
                "/usr/bin/sudo",
                "-n",
                "/usr/bin/systemctl",
                "restart",
                "klipper.service"
            ],
            capture_output=True,
            text=True,
            timeout=60
        )

        if result.returncode == 0:
            log("Klipper restarted successfully.")
        else:
            log(
                "Klipper restart error (code %s): %s" %
                (result.returncode, result.stderr.strip())
            )

    except Exception as exc:

        log("Klipper restart error: %s" % exc)


# ============================================================
# WAIT FOR CREATOR REBOOT
# ============================================================

def wait_for_mode_after_switch():

    deadline = time.monotonic() + DELAY
    saw_unreachable = False

    log(
        "Waiting %s seconds before checking Creator reboot..."
        % DELAY
    )

    while time.monotonic() < deadline:

        time.sleep(
            min(
                INTERVAL,
                max(0, deadline - time.monotonic())
            )
        )

        mode = get_mode(log_errors=False)

        if mode == "soc":
            log("Switched back to SoC: Klipper restart cancelled.")
            return "soc"

        if mode is None:
            saw_unreachable = True

    if saw_unreachable:
        log(
            "Creator API temporarily unreachable: "
            "waiting for boot to complete."
        )

    recovery_deadline = time.monotonic() + API_RETURN_TIMEOUT

    while time.monotonic() < recovery_deadline:

        mode = get_mode(log_errors=False)

        if mode == "tunneled":
            log("Creator API available again in Tunneled mode.")
            return "tunneled"

        if mode == "soc":
            log("SoC mode detected: Klipper restart cancelled.")
            return "soc"

        time.sleep(INTERVAL)

    log(
        "Timeout: Creator API did not become available "
        "after the mode switch."
    )

    return None


# ============================================================
# MAIN MONITOR
# ============================================================

def main():

    http_server = start_toolchanges_server()


####################################################
    temperature_thread = threading.Thread(
        target=send_radxa_temperature,
        name="radxa-temperature",
        daemon=True
    )
    temperature_thread.start()

    log("Sending SoC temperature to Creator every second")

    try:
        previous = get_mode()

        log("Monitor started. Initial state: %s" % previous)

        while True:

            time.sleep(INTERVAL)

            current = get_mode()

            if current is None:
                continue

            if previous == "soc" and current == "tunneled":

                log("Transizione SoC -> Tunneled rilevata.")

                confirmed_mode = wait_for_mode_after_switch()

                if confirmed_mode == "tunneled":

                    restart_klipper()
                    previous = "tunneled"

                elif confirmed_mode == "soc":

                    previous = "soc"

                else:

                    previous = "soc"

            else:

                previous = current

    finally:

        http_server.shutdown()
        http_server.server_close()


if __name__ == "__main__":
    main()
