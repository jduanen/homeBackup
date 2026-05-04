#!/usr/bin/env bash
# Run on each source machine to install the homebackup system.
# Does NOT require root for SSH key generation.
# Requires sudo for /etc/homebackup/, /usr/local/bin/, systemd units, and log dir.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
MACHINE=$(hostname -s)
CONF_SRC="${REPO_DIR}/configs/${MACHINE}.conf"
BACKUP_SCRIPT_DEST="/usr/local/bin/homebackup"
CONF_DEST="/etc/homebackup/machine.conf"
LOG_DIR="/var/log/homebackup"
SYSTEMD_DIR="/etc/systemd/system"
LOGROTATE_DEST="/etc/logrotate.d/homebackup"

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "[install] $*"; }

# --- Verify config exists ---
if [[ ! -f "$CONF_SRC" ]]; then
    echo ""
    echo "ERROR: No config found for this machine (hostname: ${MACHINE})."
    echo ""
    echo "Available configs:"
    for c in "${REPO_DIR}/configs/"*.conf; do
        echo "  $(basename "$c" .conf)"
    done
    echo ""
    echo "Create configs/${MACHINE}.conf based on an existing config, commit it, and re-run."
    exit 1
fi

info "Installing homebackup for: ${MACHINE}"

# --- Source config to get SSH key path ---
source "$CONF_SRC"

# --- Generate SSH key ---
KEY_PATH="${BACKUP_SSH_KEY}"
if [[ -f "$KEY_PATH" ]]; then
    info "SSH key already exists at ${KEY_PATH}."
else
    info "Generating SSH key at ${KEY_PATH}..."
    ssh-keygen -t ed25519 \
        -C "homebackup-${MACHINE}@$(date +%Y-%m-%d)" \
        -f "$KEY_PATH" \
        -N ""
    info "Key generated."
fi

# --- Install config ---
info "Installing config to ${CONF_DEST}..."
sudo mkdir -p "$(dirname "$CONF_DEST")"
sudo cp "$CONF_SRC" "$CONF_DEST"
sudo chmod 644 "$CONF_DEST"

# --- Install backup script ---
info "Installing backup script to ${BACKUP_SCRIPT_DEST}..."
sudo cp "${SCRIPT_DIR}/backup.sh" "$BACKUP_SCRIPT_DEST"
sudo chmod 755 "$BACKUP_SCRIPT_DEST"

# --- Create log directory ---
info "Creating log directory ${LOG_DIR}..."
sudo mkdir -p "$LOG_DIR"
sudo chown "$(whoami):$(whoami)" "$LOG_DIR"

# --- Install logrotate config ---
info "Installing logrotate config..."
sudo tee "$LOGROTATE_DEST" > /dev/null <<'EOF'
/var/log/homebackup/*.log {
    weekly
    rotate 8
    compress
    missingok
    notifempty
    create 644 jdn jdn
}
EOF

# --- Install systemd units ---
info "Installing systemd units..."
sudo cp "${REPO_DIR}/systemd/homebackup.service" "${SYSTEMD_DIR}/homebackup.service"
sudo cp "${REPO_DIR}/systemd/homebackup.timer"   "${SYSTEMD_DIR}/homebackup.timer"
sudo systemctl daemon-reload
sudo systemctl enable --now homebackup.timer
info "Timer enabled. Next run:"
systemctl list-timers homebackup.timer --no-pager 2>/dev/null || true

# --- Drive lifecycle management (target machine only) ---
if [[ -n "${BACKUP_DRIVE_LABEL:-}" ]]; then
    info "Installing drive lifecycle management (this machine holds the backup drive)..."

    # Scripts
    sudo cp "${SCRIPT_DIR}/drive-on.sh"  /usr/local/bin/homebackup-drive-on
    sudo cp "${SCRIPT_DIR}/drive-off.sh" /usr/local/bin/homebackup-drive-off
    sudo chmod 755 /usr/local/bin/homebackup-drive-on /usr/local/bin/homebackup-drive-off

    # Systemd units
    for unit in homebackup-drive-on.service homebackup-drive-on.timer \
                homebackup-drive-off.service homebackup-drive-off.timer; do
        sudo cp "${REPO_DIR}/systemd/${unit}" "${SYSTEMD_DIR}/${unit}"
    done
    sudo systemctl daemon-reload
    sudo systemctl enable --now homebackup-drive-on.timer homebackup-drive-off.timer
    info "Drive timers enabled (mount at 1:55 AM, power off at 4:00 AM)."

    # Snapshot service (runs at 3 AM, local, no SSH needed)
    sudo cp "${SCRIPT_DIR}/snapshot.sh" /usr/local/bin/homebackup-snapshot
    sudo chmod 755 /usr/local/bin/homebackup-snapshot
    sudo cp "${REPO_DIR}/systemd/homebackup-snapshot.service" "${SYSTEMD_DIR}/homebackup-snapshot.service"
    sudo cp "${REPO_DIR}/systemd/homebackup-snapshot.timer"   "${SYSTEMD_DIR}/homebackup-snapshot.timer"
    sudo systemctl daemon-reload
    sudo systemctl enable --now homebackup-snapshot.timer
    info "Snapshot timer enabled (fires at 3:00 AM)."

    # udev rule — prevents desktop automount of the backup drive
    UDEV_RULE="/etc/udev/rules.d/99-homebackup-drive.rules"
    sudo tee "$UDEV_RULE" > /dev/null <<EOF
# Prevent desktop automount of the backup drive; managed exclusively by homebackup timers.
SUBSYSTEM=="block", ENV{ID_FS_LABEL}=="${BACKUP_DRIVE_LABEL}", ENV{UDISKS_AUTO}="0"
EOF
    sudo udevadm control --reload-rules
    info "udev rule installed: desktop will no longer automount '${BACKUP_DRIVE_LABEL}'."

    # polkit rule — allows jdn to mount/unmount/power-off via udisksctl without an active session
    POLKIT_RULE="/etc/polkit-1/rules.d/99-homebackup.rules"
    sudo tee "$POLKIT_RULE" > /dev/null <<'EOF'
polkit.addRule(function(action, subject) {
    if ((action.id == "org.freedesktop.udisks2.filesystem-mount" ||
         action.id == "org.freedesktop.udisks2.filesystem-unmount-others" ||
         action.id == "org.freedesktop.udisks2.power-off-drive") &&
        subject.user == "jdn") {
        return polkit.Result.YES;
    }
});
EOF
    info "polkit rule installed: jdn can mount/unmount/power-off drives in systemd services."
fi

# --- Print public key and instructions ---
PUBKEY=$(cat "${KEY_PATH}.pub")
echo ""
echo "=========================================================="
echo "  NEXT STEP — add this key to jdnLinux2.local"
echo "=========================================================="
echo ""
echo "On jdnLinux2.local, run:"
echo ""
echo "  sudo bash ${REPO_DIR}/scripts/setup_target.sh --add-key ${MACHINE} \"${PUBKEY}\""
echo ""
echo "Or manually append to /home/rsyncbkp/.ssh/authorized_keys:"
echo ""
echo "  command=\"/usr/local/bin/rrsync /media/jdn/Elements/${MACHINE}/current\",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty ${PUBKEY}"
echo ""
echo "=========================================================="
echo ""

# --- Optional test run ---
read -rp "Run a dry-run backup test now? [y/N] " answer
if [[ "${answer,,}" == "y" ]]; then
    info "Running dry-run..."
    "$BACKUP_SCRIPT_DEST" --dry-run
fi

info "Installation complete."
