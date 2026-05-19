#!/usr/bin/env bash
# Unmount the backup drive after the backup window closes.
# Runs as jdn user via systemd; umount allowed via /etc/fstab (users option).
# The drive's own firmware will spin it down after its idle timeout.
set -euo pipefail

source /etc/homebackup/machine.conf

[[ -z "${BACKUP_DRIVE_LABEL:-}" ]] && exit 0

if mountpoint -q "${BACKUP_BASE}" 2>/dev/null; then
    echo "Unmounting ${BACKUP_BASE}..."
    sudo umount "${BACKUP_BASE}"
    echo "Drive unmounted."
else
    echo "Drive already unmounted."
fi
