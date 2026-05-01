#!/usr/bin/env bash
# Mount the backup drive before the backup window opens.
# Runs as jdn user via systemd; uses udisksctl (no root required).
set -euo pipefail

source /etc/homebackup/machine.conf

[[ -z "${BACKUP_DRIVE_LABEL:-}" ]] && exit 0

DEVICE=$(readlink -f "/dev/disk/by-label/${BACKUP_DRIVE_LABEL}" 2>/dev/null) || {
    echo "Drive with label '${BACKUP_DRIVE_LABEL}' not found — is it plugged in?" >&2
    exit 1
}

if mountpoint -q "${BACKUP_BASE}" 2>/dev/null; then
    echo "Drive already mounted at ${BACKUP_BASE}."
    exit 0
fi

echo "Mounting ${DEVICE} at ${BACKUP_BASE}..."
udisksctl mount --block-device "${DEVICE}" --no-user-interaction
echo "Drive mounted."
