#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="klipper-mode-monitor"
SERVICE_NAME="${APP_NAME}.service"
SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CURRENT_USER="$(id -un)"
CURRENT_GROUP="$(id -gn)"
USER_HOME="$(getent passwd "$CURRENT_USER" | cut -d: -f6)"

[[ "$CURRENT_USER" != "root" ]] || {
    echo "Run this installer as the regular Linux user, not root."
    exit 1
}
[[ -n "$USER_HOME" && -d "$USER_HOME" ]] || {
    echo "Could not determine the user's home directory."
    exit 1
}
[[ -x /usr/bin/python3 ]] || {
    echo "Python 3 is required."
    exit 1
}
command -v sudo >/dev/null 2>&1 || {
    echo "sudo is required."
    exit 1
}

DEST_DIR="$USER_HOME/printer_data/config/klipper_mode_monitor"
SERVICE_DEST="/etc/systemd/system/$SERVICE_NAME"

log() { printf '\n[%s] %s\n' "$APP_NAME" "$1"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

validate_ip() {
    /usr/bin/python3 -c 'import ipaddress,sys; ipaddress.IPv4Address(sys.argv[1])' "$1" \
        >/dev/null 2>&1
}

for file in klipper_mode_monitor.py README.md uninstall.sh; do
    [[ -f "$SOURCE_DIR/$file" ]] || fail "Missing package file: $file"
done

# Read the existing Creator IP as the installation default.
CREATOR_DEFAULT="192.168.1.194"
if [[ -f "$SOURCE_DIR/config.json" ]]; then
    CREATOR_DEFAULT=$(/usr/bin/python3 - "$SOURCE_DIR/config.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    print(json.load(f).get("creator_ip", "192.168.1.194"))
PY
    )
fi

printf '\n========================================\n'
printf '       Creator 5 Klipper Mode Monitor\n'
printf '========================================\n'
printf 'Installation user: %s\nHome: %s\nTarget: %s\n' \
    "$CURRENT_USER" "$USER_HOME" "$DEST_DIR"

while true; do
    read -r -p "Creator 5 IP address [$CREATOR_DEFAULT]: " CREATOR_IP
    CREATOR_IP="${CREATOR_IP:-$CREATOR_DEFAULT}"
    validate_ip "$CREATOR_IP" && break
    echo "Invalid IPv4 address."
done


log "Requesting administrative permissions..."
sudo -v

log "Preparing installation directory..."
mkdir -p "$DEST_DIR"

SUDOERS_FILE="/etc/sudoers.d/${APP_NAME}-${CURRENT_USER}"
SUDOERS_MARKER="$DEST_DIR/.sudoers-managed"
SUDO_LIST="$(sudo -n -l 2>/dev/null || true)"

if ! grep -Eq 'NOPASSWD: (ALL|/usr/bin/systemctl restart klipper\.service)' <<< "$SUDO_LIST"; then
    log "Configuring restricted Klipper restart permission..."

    if sudo test -e "$SUDOERS_FILE"; then
        fail "Sudoers file already exists. Refusing to overwrite it: $SUDOERS_FILE"
    fi

    SUDOERS_TMP="$(mktemp)"
    printf '%s ALL=(root) NOPASSWD: /usr/bin/systemctl restart klipper.service\n' "$CURRENT_USER" > "$SUDOERS_TMP"

    if ! sudo visudo -cf "$SUDOERS_TMP"; then
        rm -f "$SUDOERS_TMP"
        fail "Invalid sudoers rule. Installation stopped."
    fi

    sudo install -o root -g root -m 0440 "$SUDOERS_TMP" "$SUDOERS_FILE"
    rm -f "$SUDOERS_TMP"

    printf '%s\n' "$SUDOERS_FILE" > "$SUDOERS_MARKER"
else
    log "Required passwordless sudo permission already available."
fi

# If installer is run from the target directory, avoid copying files onto themselves.
if [[ "$SOURCE_DIR" != "$DEST_DIR" ]]; then
    for file in klipper_mode_monitor.py README.md uninstall.sh; do
        install -m 644 "$SOURCE_DIR/$file" "$DEST_DIR/$file"
    done
    chmod 755 "$DEST_DIR/uninstall.sh"
fi

log "Writing network configuration..."
/usr/bin/python3 - "$DEST_DIR/config.json" "$CREATOR_IP" <<'PY'
import json, os, sys, tempfile
path, creator = sys.argv[1:]
data = {
    "creator_ip": creator
}
fd, tmp = tempfile.mkstemp(prefix=".config-", dir=os.path.dirname(path))
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=4)
        f.write("\n")
    os.chmod(tmp, 0o640)
    os.replace(tmp, path)
except Exception:
    try:
        os.unlink(tmp)
    except OSError:
        pass
    raise
PY


log "Integrating SoC Mode entry into Mainsail navigation..."

MENU_FILE="$USER_HOME/printer_data/config/.theme/navi.json"

/usr/bin/python3 - "$MENU_FILE" "$CREATOR_IP" <<'MENU_PY'
import json
import os
import shutil
import sys
import tempfile
from datetime import datetime
from pathlib import Path

path = Path(sys.argv[1])
creator_ip = sys.argv[2]

path.parent.mkdir(parents=True, exist_ok=True)

if path.exists():
    with path.open("r", encoding="utf-8") as f:
        entries = json.load(f)
    if not isinstance(entries, list):
        raise SystemExit("Invalid Mainsail navigation format: expected a JSON array.")
    original = json.dumps(entries, ensure_ascii=False, indent=2)
    mode = path.stat().st_mode & 0o777
else:
    entries = []
    original = None
    mode = 0o664

matches = [
    i for i, item in enumerate(entries)
    if isinstance(item, dict) and (
        item.get("title") == "SoC Mode"
        or item.get("href", "").endswith("/go_soc")
    )
]

entry = {
    "title": "SoC Mode",
    "href": f"http://{creator_ip}:8765/go_soc",
    "target": "_self",
    "position": 90
}

if matches:
    index = matches[0]
    entries[index].update(entry)
    for duplicate in reversed(matches[1:]):
        del entries[duplicate]
    action = "updated"
else:
    entries.append(entry)
    action = "added"

updated = json.dumps(entries, ensure_ascii=False, indent=2)

if updated != original:
    if path.exists():
        backup = path.with_name(
            path.name + ".bak." + datetime.now().strftime("%Y%m%d-%H%M%S")
        )
        shutil.copy2(path, backup)
        print(f"Backup created: {backup}")

    fd, temporary = tempfile.mkstemp(
        prefix=".navi-", dir=str(path.parent)
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(updated + "\n")
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    except Exception:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise

    print(f"Mainsail navigation entry {action}: {entry['href']}")
else:
    print("Mainsail navigation already configured correctly.")
MENU_PY


log "Installing SOC_MODE Klipper macro..."

CONFIG_DIR="$USER_HOME/printer_data/config"
MACRO_FILE="$CONFIG_DIR/oc_macros.cfg"
BASE_FILE="$CONFIG_DIR/printer.base.cfg"

[[ -f "$BASE_FILE" ]] || fail "Missing Klipper configuration: $BASE_FILE"

/usr/bin/python3 - "$MACRO_FILE" "$BASE_FILE" "$CREATOR_IP" <<'MACRO_PY'
import re
import shutil
import sys
from datetime import datetime
from pathlib import Path

macro_path = Path(sys.argv[1])
base_path = Path(sys.argv[2])
creator_ip = sys.argv[3]

def backup(path):
    if path.exists():
        suffix = datetime.now().strftime("%Y%m%d-%H%M%S")
        dest = path.with_name(path.name + ".bak." + suffix)
        shutil.copy2(path, dest)
        print(f"Backup created: {dest}")

def add_section(content, header, body):
    pattern = re.compile(
        r"(?ms)^" + re.escape(header) + r"\s*\n(.*?)(?=^\[|\Z)"
    )
    match = pattern.search(content)
    if match:
        return content

    return content.rstrip() + "\n\n" + header + "\n" + body.strip() + "\n"

content = macro_path.read_text(encoding="utf-8") if macro_path.exists() else ""
original = content

content = add_section(
    content,
    "[gcode_shell_command oc_soc_mode]",
    f'''command: curl -fsS --max-time 10 "http://{creator_ip}:8765/go_soc"
timeout: 15.
verbose: True'''
)

content = add_section(
    content,
    "[gcode_macro SOC_MODE]",
    '''description: Switch Creator 5 to SoC mode
gcode:
    RUN_SHELL_COMMAND CMD=oc_soc_mode'''
)

if content != original:
    backup(macro_path)
    macro_path.parent.mkdir(parents=True, exist_ok=True)
    macro_path.write_text(content, encoding="utf-8")
    print("SOC_MODE macro installed.")
else:
    print("SOC_MODE macro already exists.")

base = base_path.read_text(encoding="utf-8")
include = "[include oc_macros.cfg]"

if not re.search(r"(?m)^\s*\[include\s+oc_macros\.cfg\]\s*$", base):
    backup(base_path)
    base_path.write_text(base.rstrip() + "\n\n" + include + "\n", encoding="utf-8")
    print("oc_macros.cfg included in printer.base.cfg.")
else:
    print("oc_macros.cfg already included.")
MACRO_PY

log "Checking Python syntax..."
/usr/bin/python3 -m py_compile "$DEST_DIR/klipper_mode_monitor.py"

log "Installing systemd service..."
UNIT_TMP="$(mktemp)"
cat > "$UNIT_TMP" <<EOF
[Unit]
Description=Creator 5 Tunneled Mode Monitor
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$CURRENT_USER
Group=$CURRENT_GROUP
Environment=HOME=$USER_HOME
WorkingDirectory=$DEST_DIR
ExecStart=/usr/bin/python3 -u $DEST_DIR/klipper_mode_monitor.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo install -m 644 "$UNIT_TMP" "$SERVICE_DEST"
rm -f "$UNIT_TMP"

printf '%s\n' "$CURRENT_USER" > "$DEST_DIR/.installed-user"

log "Reloading systemd and starting service..."
sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl restart "$SERVICE_NAME"

sleep 2
if ! sudo systemctl is-active --quiet "$SERVICE_NAME"; then
    sudo systemctl status "$SERVICE_NAME" --no-pager || true
    fail "Service did not start. Check: sudo journalctl -u $SERVICE_NAME -n 80"
fi

log "Restarting Klipper to load the new SOC_MODE macro..."

if ! curl -fsS --max-time 10 -X POST \
    http://127.0.0.1:7125/printer/restart; then
    fail "Unable to request Klipper restart through Moonraker."
fi

log "Waiting for Klipper to become ready..."

KLIPPER_READY=0
for attempt in $(seq 1 60); do
    INFO="$(curl -fsS --max-time 2 \
        http://127.0.0.1:7125/printer/info 2>/dev/null || true)"

    if printf '%s' "$INFO" | grep -Eq '"state"[[:space:]]*:[[:space:]]*"ready"'; then
        KLIPPER_READY=1
        break
    fi

    sleep 2
done

if [[ "$KLIPPER_READY" -ne 1 ]]; then
    fail "Klipper did not return to ready state within 120 seconds."
fi

log "Klipper restarted successfully and is ready."

log "Installation completed successfully."
echo
echo "Service status:"
sudo systemctl status "$SERVICE_NAME" --no-pager
echo
echo "Configuration: $DEST_DIR/config.json"
echo "Logs: sudo journalctl -u $SERVICE_NAME -f"
