#!/usr/bin/env bash
# Main backup runner. Install to /usr/local/bin/homebackup via install.sh.
# Sources /etc/homebackup/machine.conf for all configuration.
set -euo pipefail

CONF_FILE="/etc/homebackup/machine.conf"
DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=1
fi

# --- Config ---
if [[ ! -f "$CONF_FILE" ]]; then
    echo "ERROR: $CONF_FILE not found. Run install.sh first." >&2
    exit 1
fi
source "$CONF_FILE"

MACHINE=$(hostname -s)
TIMESTAMP=$(date +%Y-%m-%d_%H-%M)
LOG_DIR="/var/log/homebackup"
LOG_FILE="${LOG_DIR}/${MACHINE}-${TIMESTAMP}.log"
START_TIME=$(date +%s)
ERRORS=0
SOURCES_OK=0

mkdir -p "$LOG_DIR"

# --- Logging ---
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

exec > >(tee -a "$LOG_FILE") 2>&1

log "=== homebackup starting on ${MACHINE} ==="
[[ "$DRY_RUN" -eq 1 ]] && log "DRY RUN MODE — no changes will be written"

# --- Lock file ---
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/homebackup.pid"
if [[ -f "$LOCK_FILE" ]]; then
    OLD_PID=$(cat "$LOCK_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        log "Already running (pid $OLD_PID). Exiting."
        exit 0
    fi
    log "Stale lock file (pid $OLD_PID). Removing."
    rm -f "$LOCK_FILE"
fi
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

# --- SSH reachability check (TCP only — authorized_keys uses forced command so SSH exit won't work) ---
log "Checking connectivity to ${BACKUP_HOST}:${BACKUP_PORT}..."
if ! nc -z -w 10 "$BACKUP_HOST" "$BACKUP_PORT" 2>/dev/null; then
    log "WARNING: Cannot reach ${BACKUP_HOST}:${BACKUP_PORT}. Skipping backup run."
    exit 0
fi
log "${BACKUP_HOST} is reachable."

# --- Build rsync exclude args ---
EXCLUDE_ARGS=()
for excl in "${BACKUP_EXCLUDES[@]}"; do
    EXCLUDE_ARGS+=("--exclude=${excl}")
done

DRY_RUN_ARG=()
[[ "$DRY_RUN" -eq 1 ]] && DRY_RUN_ARG=("--dry-run")

SSH_CMD="ssh -i ${BACKUP_SSH_KEY} -p ${BACKUP_PORT} -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o IdentitiesOnly=yes -o ClearAllForwardings=yes"

# --- rsync each source ---
for src in "${BACKUP_SOURCES[@]}"; do
    # Strip leading slash to form relative dest path (e.g. /home/jdn -> home/jdn)
    rel_dst="${src#/}"
    # Remove trailing slash from rel_dst for clean path construction
    rel_dst="${rel_dst%/}"

    log "--- Syncing: ${src} ---"
    rsync_exit=0
    rsync -aHAXvz \
            --numeric-ids \
            --delete \
            --delete-excluded \
            --mkpath \
            --partial \
            --partial-dir=".rsync-partial" \
            --timeout=120 \
            --stats \
            -e "$SSH_CMD" \
            "${EXCLUDE_ARGS[@]}" \
            "${DRY_RUN_ARG[@]}" \
            "${src}" \
            "${BACKUP_USER}@${BACKUP_HOST}:./${rel_dst}/" || rsync_exit=$?
    if [[ $rsync_exit -eq 0 ]]; then
        log "OK: ${src}"
        SOURCES_OK=$((SOURCES_OK + 1))
    elif [[ $rsync_exit -eq 23 || $rsync_exit -eq 24 ]]; then
        log "WARNING: ${src} completed with partial transfer (exit ${rsync_exit}) — some files skipped"
        SOURCES_OK=$((SOURCES_OK + 1))
    else
        log "ERROR: rsync failed for ${src} (exit ${rsync_exit})"
        ERRORS=$((ERRORS + 1))
    fi
done

# --- Summary ---
ELAPSED=$(( $(date +%s) - START_TIME ))
log "=== homebackup complete: ${SOURCES_OK} sources ok, ${ERRORS} errors, ${ELAPSED}s elapsed ==="

[[ "$ERRORS" -gt 0 ]] && exit 1
exit 0
