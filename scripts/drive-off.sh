#!/usr/bin/env bash
# Unmount and power off the backup drive after the backup window closes.
# Runs as jdn user via systemd; uses udisksctl (no root required).
set -euo pipefail

source /etc/homebackup/machine.conf

[[ -z "${BACKUP_DRIVE_LABEL:-}" ]] && exit 0

DEVICE=$(readlink -f "/dev/disk/by-label/${BACKUP_DRIVE_LABEL}" 2>/dev/null) || {
    echo "Drive with label '${BACKUP_DRIVE_LABEL}' not found — may already be powered off."
    exit 0
}

if mountpoint -q "${BACKUP_BASE}" 2>/dev/null; then
    echo "Unmounting ${BACKUP_BASE}..."
    udisksctl unmount --block-device "${DEVICE}" --no-user-interaction
fi

echo "Powering off drive..."
udisksctl power-off --block-device "${DEVICE}" --no-user-interaction
echo "Drive powered off."
