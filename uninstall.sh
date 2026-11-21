#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="klipper-mode-monitor"
SERVICE_NAME="${APP_NAME}.service"
APP_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
USER_MARKER="$APP_DIR/.installed-user"
SUDOERS_MARKER="$APP_DIR/.sudoers-managed"

echo "This will stop and remove the systemd service."
echo "Application files and Klipper data will be preserved."
read -r -p "Type REMOVE to continue: " CONFIRM

[[ "$CONFIRM" == "REMOVE" ]] || {
    echo "Cancelled."
    exit 0
}

[[ "$(id -u)" -ne 0 ]] || {
    echo "Run this script as the regular installation user, not root."
    exit 1
}

sudo -v

INSTALLED_USER=""
if [[ -f "$USER_MARKER" ]]; then
    INSTALLED_USER="$(cat "$USER_MARKER")"
fi

sudo systemctl disable --now "$SERVICE_NAME" 2>/dev/null || true
sudo rm -f "/etc/systemd/system/$SERVICE_NAME"
sudo systemctl daemon-reload
sudo systemctl reset-failed "$SERVICE_NAME" 2>/dev/null || true

if [[ -n "$INSTALLED_USER" ]] && getent passwd "$INSTALLED_USER" >/dev/null; then
    EXPECTED_SUDOERS="/etc/sudoers.d/${APP_NAME}-${INSTALLED_USER}"

    if [[ -f "$SUDOERS_MARKER" ]]; then
        MARKED_FILE="$(cat "$SUDOERS_MARKER")"

        if [[ "$MARKED_FILE" == "$EXPECTED_SUDOERS" ]]; then
            sudo rm -f -- "$EXPECTED_SUDOERS"
            rm -f "$SUDOERS_MARKER"
            echo "Installer-managed sudoers rule removed."
        else
            echo "WARNING: Sudoers marker mismatch. No sudoers file was removed."
        fi
    fi
else
    echo "No valid installation-user marker. Sudoers file was left untouched."
fi

echo "Service removed. Application files and Klipper data were preserved."
