#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="klipper-mode-monitor"
SERVICE_NAME="${APP_NAME}.service"
APP_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
USER_MARKER="$APP_DIR/.installed-user"
SUDOERS_MARKER="$APP_DIR/.sudoers-managed"

echo "This will remove the project systemd service."
echo "Application files, configuration and Klipper data will be preserved."
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

if [[ -n "$INSTALLED_USER" && "$INSTALLED_USER" != "$(id -un)" ]]; then
    echo "Installation user mismatch. No changes made."
    exit 1
fi

echo "Removing systemd service..."
sudo systemctl disable --now "$SERVICE_NAME" 2>/dev/null || true
sudo rm -f "/etc/systemd/system/$SERVICE_NAME"
sudo systemctl daemon-reload
sudo systemctl reset-failed "$SERVICE_NAME" 2>/dev/null || true

if [[ -f "$SUDOERS_MARKER" ]]; then
    MARKED_FILE="$(cat "$SUDOERS_MARKER")"
    EXPECTED_FILE="/etc/sudoers.d/${APP_NAME}-${INSTALLED_USER}"

    if [[ -n "$INSTALLED_USER" && "$MARKED_FILE" == "$EXPECTED_FILE" ]] &&
       sudo test -f "$EXPECTED_FILE"; then

        EXPECTED_RULE="${INSTALLED_USER} ALL=(root) NOPASSWD: /usr/bin/systemctl restart klipper.service"

        if sudo grep -Fxq "$EXPECTED_RULE" "$EXPECTED_FILE"; then
            sudo rm -f -- "$EXPECTED_FILE"
            rm -f "$SUDOERS_MARKER"
            echo "Installer-managed sudoers rule removed."
        else
            echo "WARNING: Sudoers file was modified. It was preserved."
        fi
    else
        echo "WARNING: Sudoers marker mismatch. File preserved."
    fi
fi

rm -f "$USER_MARKER"

echo
echo "Service removed."
echo "Application files and Klipper data were preserved."
