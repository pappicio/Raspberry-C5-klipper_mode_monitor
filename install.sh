#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="klipper-mode-monitor"
SERVICE_NAME="${APP_NAME}.service"
APP_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
CURRENT_USER="$(id -un)"
CURRENT_GROUP="$(id -gn)"
USER_HOME="$(getent passwd "$CURRENT_USER" | cut -d: -f6)"

log() { printf '\n[%s] %s\n' "$APP_NAME" "$1"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

[[ "$(id -u)" -ne 0 ]] || fail "Run as the regular installation user."
[[ -n "$USER_HOME" && -d "$USER_HOME" ]] || fail "Invalid user home."
[[ -x /usr/bin/python3 ]] || fail "Python 3 is required."
command -v sudo >/dev/null 2>&1 || fail "sudo is required."

for file in \
    klipper_mode_monitor.py \
    config.json \
    backend/dashboard_server.py \
    backend/custom_projects.py \
    frontend/index.html \
    frontend/dashboard.js \
    frontend/dashboard.css \
    integration/opencreator-inject.js
do
    [[ -f "$APP_DIR/$file" ]] || fail "Missing project file: $file"
done

log "Validating existing configuration..."
/usr/bin/python3 - "$APP_DIR/config.json" <<'PY'
import json
import ipaddress
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    config = json.load(f)

ipaddress.IPv4Address(config["creator_ip"])
print("Configuration valid. Existing settings preserved.")
PY

log "Checking Python syntax..."
/usr/bin/python3 -m py_compile \
    "$APP_DIR/klipper_mode_monitor.py" \
    "$APP_DIR/backend/dashboard_server.py" \
    "$APP_DIR/backend/custom_projects.py"

log "Requesting administrative permissions..."
sudo -v

SERVICE_DEST="/etc/systemd/system/$SERVICE_NAME"
SUDOERS_FILE="/etc/sudoers.d/${APP_NAME}-${CURRENT_USER}"
SUDOERS_MARKER="$APP_DIR/.sudoers-managed"
USER_MARKER="$APP_DIR/.installed-user"

log "Configuring Klipper restart permission..."

SUDO_LIST="$(sudo -n -l 2>/dev/null || true)"

if grep -Eq 'NOPASSWD:.*(ALL|/usr/bin/systemctl restart klipper\.service)' <<< "$SUDO_LIST"; then
    log "Existing passwordless permission is sufficient."
else
    if sudo test -e "$SUDOERS_FILE"; then
        [[ -f "$SUDOERS_MARKER" ]] || fail "Unmanaged sudoers file exists: $SUDOERS_FILE"
        [[ "$(cat "$SUDOERS_MARKER")" == "$SUDOERS_FILE" ]] || fail "Sudoers marker mismatch."
    else
        SUDOERS_TMP="$(mktemp)"
        printf '%s ALL=(root) NOPASSWD: /usr/bin/systemctl restart klipper.service\n' \
            "$CURRENT_USER" > "$SUDOERS_TMP"

        if ! sudo visudo -cf "$SUDOERS_TMP"; then
            rm -f "$SUDOERS_TMP"
            fail "Invalid sudoers rule."
        fi

        sudo install -o root -g root -m 0440 "$SUDOERS_TMP" "$SUDOERS_FILE"
        rm -f "$SUDOERS_TMP"
        printf '%s\n' "$SUDOERS_FILE" > "$SUDOERS_MARKER"
        log "Restricted Klipper restart permission installed."
    fi
fi

log "Preparing systemd service..."

UNIT_TMP="$(mktemp)"
cat > "$UNIT_TMP" <<EOF
[Unit]
Description=OpenCreator Unified Monitor and Dashboard
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$CURRENT_USER
Group=$CURRENT_GROUP
Environment=HOME=$USER_HOME
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/python3 -u $APP_DIR/klipper_mode_monitor.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo install -o root -g root -m 0644 "$UNIT_TMP" "$SERVICE_DEST"
rm -f "$UNIT_TMP"

printf '%s\n' "$CURRENT_USER" > "$USER_MARKER"

log "Reloading systemd and starting the unified service..."
sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl restart "$SERVICE_NAME"

sleep 2

if ! sudo systemctl is-active --quiet "$SERVICE_NAME"; then
    sudo systemctl status "$SERVICE_NAME" --no-pager || true
    sudo journalctl -u "$SERVICE_NAME" -n 60 --no-pager || true
    fail "Service failed to start."
fi

log "Installation completed successfully."

echo
echo "Project: $APP_DIR"
echo "User: $CURRENT_USER"
echo "Service: $SERVICE_NAME"
echo "Port: 8765"
echo "Configuration preserved: $APP_DIR/config.json"
echo
sudo systemctl status "$SERVICE_NAME" --no-pager
