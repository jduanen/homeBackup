#!/usr/bin/env bash
# Mount the backup drive before the backup window opens.
# Runs as jdn user via systemd; mount allowed via /etc/fstab (users option).
set -euo pipefail

source /etc/homebackup/machine.conf

[[ -z "${BACKUP_DRIVE_LABEL:-}" ]] && exit 0

readlink -f "/dev/disk/by-label/${BACKUP_DRIVE_LABEL}" > /dev/null 2>&1 || {
    echo "Drive with label '${BACKUP_DRIVE_LABEL}' not found — is it plugged in?" >&2
    exit 1
}

if mountpoint -q "${BACKUP_BASE}" 2>/dev/null; then
    echo "Drive already mounted at ${BACKUP_BASE}."
    exit 0
fi

echo "Mounting ${BACKUP_BASE}..."
sudo mount "${BACKUP_BASE}"
echo "Drive mounted."
