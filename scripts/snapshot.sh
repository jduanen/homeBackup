#!/usr/bin/env bash
# Run on jdnLinux2 at 3:00 AM by homebackup-snapshot.timer.
# Creates daily hardlink snapshots and prunes old ones for all machine directories on the drive.
# Install to /usr/local/bin/homebackup-snapshot via install.sh.
set -euo pipefail

CONF_FILE="/etc/homebackup/machine.conf"
if [[ ! -f "$CONF_FILE" ]]; then
    echo "ERROR: $CONF_FILE not found." >&2
    exit 1
fi
source "$CONF_FILE"

SNAP_DATE=$(date +%Y-%m-%d)
LOG_DIR="/var/log/homebackup"
LOG_FILE="${LOG_DIR}/snapshots-${SNAP_DATE}.log"
ERRORS=0

mkdir -p "$LOG_DIR"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
exec > >(tee -a "$LOG_FILE") 2>&1

log "=== homebackup-snapshot starting (keep ${SNAPSHOT_KEEP_DAYS} days) ==="

if ! mountpoint -q "$BACKUP_BASE"; then
    log "ERROR: ${BACKUP_BASE} is not mounted. Aborting."
    exit 1
fi

shopt -s nullglob
for machine_dir in "${BACKUP_BASE}"/*/; do
    machine=$(basename "$machine_dir")
    current="${machine_dir}current"
    snapshots_dir="${machine_dir}snapshots"
    snap_dest="${snapshots_dir}/${SNAP_DATE}"

    if [[ ! -d "$current" ]]; then
        log "SKIP ${machine}: no current/ directory"
        continue
    fi

    if [[ -z "$(ls -A "$current" 2>/dev/null)" ]]; then
        log "SKIP ${machine}: current/ is empty (backup may not have run yet)"
        continue
    fi

    log "--- ${machine} ---"
    mkdir -p "$snapshots_dir"

    if [[ -d "$snap_dest" ]]; then
        log "  Snapshot ${SNAP_DATE} already exists."
    else
        if cp -al "$current" "$snap_dest"; then
            log "  Snapshot created: ${snap_dest}"
        else
            log "  ERROR: cp -al failed for ${machine}"
            ERRORS=$((ERRORS + 1))
        fi
    fi

    find "$snapshots_dir" -maxdepth 1 -mindepth 1 -type d -mtime "+${SNAPSHOT_KEEP_DAYS}" \
        -exec echo "  Pruning: {}" \; -exec rm -rf '{}' \; || \
        log "  WARNING: pruning failed for ${machine} (non-fatal)"
done

log "=== homebackup-snapshot complete: ${ERRORS} errors ==="
[[ "$ERRORS" -gt 0 ]] && exit 1
exit 0
