#!/usr/bin/env bash
# Run as root/sudo on jdnLinux2.local to prepare the USB backup drive.
# Usage:
#   sudo bash setup_target.sh                         # full initial setup
#   sudo bash setup_target.sh --add-machine <name>    # create dirs for a new machine
#   sudo bash setup_target.sh --add-key <machine> "<pubkey>"  # add SSH key for a machine
set -euo pipefail

BACKUP_USER="backup"
BACKUP_HOME="/home/backup"
BACKUP_MOUNT="/media/jdn/Elements"
RRSYNC_DEST="/usr/local/bin/rrsync"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "[setup_target] $*"; }

require_root() {
    [[ $EUID -eq 0 ]] || die "This script must be run as root (use sudo)."
}

# -----------------------------------------------------------------------
# Subcommand: --add-machine <name>
# -----------------------------------------------------------------------
cmd_add_machine() {
    local machine="$1"
    require_root
    info "Creating backup directories for: ${machine}"
    mkdir -p "${BACKUP_MOUNT}/${machine}/current"
    mkdir -p "${BACKUP_MOUNT}/${machine}/snapshots"
    chown -R "${BACKUP_USER}:${BACKUP_USER}" "${BACKUP_MOUNT}/${machine}"
    info "Done. Directories created at ${BACKUP_MOUNT}/${machine}/"
}

# -----------------------------------------------------------------------
# Subcommand: --add-key <machine> <pubkey>
# -----------------------------------------------------------------------
cmd_add_key() {
    local machine="$1"
    local pubkey="$2"
    require_root
    local auth_keys="${BACKUP_HOME}/.ssh/authorized_keys"

    # Ensure backup user and SSH directory exist
    if ! id "$BACKUP_USER" &>/dev/null; then
        useradd -r -s /bin/bash -m -d "$BACKUP_HOME" "$BACKUP_USER"
        info "Created user '${BACKUP_USER}'."
    fi
    if [[ ! -d "${BACKUP_HOME}/.ssh" ]]; then
        mkdir -p "${BACKUP_HOME}/.ssh"
        touch "$auth_keys"
        chmod 700 "${BACKUP_HOME}/.ssh"
        chmod 600 "$auth_keys"
        chown -R "${BACKUP_USER}:${BACKUP_USER}" "${BACKUP_HOME}/.ssh"
    fi

    # Check for duplicate
    if grep -qF "$pubkey" "$auth_keys" 2>/dev/null; then
        info "Public key for ${machine} already in authorized_keys. Skipping."
        return 0
    fi

    local entry="command=\"${RRSYNC_DEST} ${BACKUP_MOUNT}/${machine}/current\","
    entry+="no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty "
    entry+="${pubkey}"

    echo "$entry" >> "$auth_keys"
    chmod 600 "$auth_keys"
    chown "${BACKUP_USER}:${BACKUP_USER}" "$auth_keys"
    info "Added key for ${machine} to ${auth_keys}"
}

# -----------------------------------------------------------------------
# Full initial setup
# -----------------------------------------------------------------------
cmd_full_setup() {
    require_root

    # --- Mount point ---
    info "Setting up mount point at ${BACKUP_MOUNT}..."
    mkdir -p "$BACKUP_MOUNT"

    if mountpoint -q "$BACKUP_MOUNT"; then
        info "  ${BACKUP_MOUNT} is already mounted."
    else
        info ""
        info "  The backup drive is NOT mounted at ${BACKUP_MOUNT}."
        info "  To find your USB drive's UUID, run:"
        info "    lsblk -o NAME,UUID,SIZE,LABEL,MOUNTPOINT"
        info ""
        info "  Then add a line like this to /etc/fstab:"
        info "    UUID=<your-uuid>  /media/jdn/Elements  ext4  defaults,nofail  0  2"
        info ""
        info "  If the drive needs formatting (WARNING: destroys data):"
        info "    sudo mkfs.ext4 -L HomeBackup /dev/<device>"
        info ""
        read -rp "Press Enter once the drive is mounted at ${BACKUP_MOUNT}, or Ctrl-C to abort..."
        mountpoint -q "$BACKUP_MOUNT" || die "${BACKUP_MOUNT} still not mounted. Aborting."
    fi

    # --- Backup user ---
    info "Creating backup user..."
    if id "$BACKUP_USER" &>/dev/null; then
        info "  User '${BACKUP_USER}' already exists."
    else
        useradd -r -s /bin/bash -m -d "$BACKUP_HOME" "$BACKUP_USER"
        info "  Created user '${BACKUP_USER}'."
    fi

    # Drive is normally unmounted (managed by drive lifecycle timers).
    # Mount it temporarily here so we can set ownership, then unmount.
    DRIVE_WAS_MOUNTED=0
    if mountpoint -q "$BACKUP_MOUNT"; then
        DRIVE_WAS_MOUNTED=1
    else
        info "  Mounting drive temporarily to set ownership..."
        DEVICE=$(readlink -f /dev/disk/by-label/Elements 2>/dev/null) || \
            die "Could not find drive by label 'Elements'. Is it plugged in?"
        mount "$DEVICE" "$BACKUP_MOUNT"
    fi

    chown "${BACKUP_USER}:${BACKUP_USER}" "$BACKUP_MOUNT"
    chmod 750 "$BACKUP_MOUNT"

    # --- rrsync ---
    info "Installing rrsync..."
    if [[ -f "$RRSYNC_DEST" ]]; then
        info "  rrsync already at ${RRSYNC_DEST}."
    else
        # Try common locations
        RRSYNC_SRC=""
        for candidate in \
            /usr/share/doc/rsync/scripts/rrsync \
            /usr/lib/rsync/scripts/rrsync \
            /usr/share/rsync/scripts/rrsync; do
            if [[ -f "$candidate" ]]; then
                RRSYNC_SRC="$candidate"
                break
            fi
        done

        if [[ -z "$RRSYNC_SRC" ]]; then
            # Try to extract from doc gzip
            for gz in /usr/share/doc/rsync/scripts/rrsync.gz; do
                if [[ -f "$gz" ]]; then
                    gunzip -c "$gz" > "$RRSYNC_DEST"
                    chmod +x "$RRSYNC_DEST"
                    RRSYNC_SRC="$gz (extracted)"
                    break
                fi
            done
        fi

        if [[ -z "$RRSYNC_SRC" ]]; then
            die "Could not find rrsync. Install rsync package or place rrsync manually at ${RRSYNC_DEST}."
        fi

        [[ "$RRSYNC_SRC" != *"extracted"* ]] && cp "$RRSYNC_SRC" "$RRSYNC_DEST"
        chmod +x "$RRSYNC_DEST"
        info "  Installed rrsync from ${RRSYNC_SRC}."
    fi

    # --- SSH directory ---
    info "Setting up backup user SSH directory..."
    mkdir -p "${BACKUP_HOME}/.ssh"
    touch "${BACKUP_HOME}/.ssh/authorized_keys"
    chmod 700 "${BACKUP_HOME}/.ssh"
    chmod 600 "${BACKUP_HOME}/.ssh/authorized_keys"
    chown -R "${BACKUP_USER}:${BACKUP_USER}" "${BACKUP_HOME}/.ssh"

    # --- Backup directories for known machines ---
    info "Creating backup directories for configured machines..."
    for conf in "${REPO_DIR}/configs/"*.conf; do
        machine=$(basename "$conf" .conf)
        cmd_add_machine "$machine"
    done

    # Unmount again — normal state is unmounted; drive lifecycle timers manage it
    if [[ "$DRIVE_WAS_MOUNTED" -eq 0 ]] && mountpoint -q "$BACKUP_MOUNT"; then
        info "Unmounting drive (will be managed by lifecycle timers after install)..."
        umount "$BACKUP_MOUNT"
    fi

    info ""
    info "=== Setup complete ==="
    info ""
    info "Next steps:"
    info "  1. On jdnLinux2, run:  bash install.sh  (installs drive lifecycle timers + udev rule)"
    info "  2. On each other source machine, run:  bash install.sh"
    info "  3. Copy each machine's printed public key, then run:"
    info "     sudo bash setup_target.sh --add-key <machine> \"<pubkey>\""
    info "  4. Test from the source machine:  homebackup --dry-run"
}

# -----------------------------------------------------------------------
# Dispatch
# -----------------------------------------------------------------------
case "${1:-}" in
    --add-machine)
        [[ -n "${2:-}" ]] || die "Usage: $0 --add-machine <machine-name>"
        cmd_add_machine "$2"
        ;;
    --add-key)
        [[ -n "${2:-}" && -n "${3:-}" ]] || die "Usage: $0 --add-key <machine> \"<pubkey>\""
        cmd_add_key "$2" "$3"
        ;;
    "")
        cmd_full_setup
        ;;
    *)
        die "Unknown option: $1"
        ;;
esac
