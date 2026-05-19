# homeBackup

Push-based rsync backup system for home machines. Each source machine pushes nightly to an external USB drive on `jdnLinux2.local`.

## Design

### Architecture

Each source machine runs a systemd timer that fires at 2 AM and calls `homebackup` (a bash script wrapping rsync). The script pushes over SSH to the `jdn` user on `jdnLinux2.local`. SSH keys are restricted using `rrsync` so each machine can only write to its own subtree on the drive. Snapshots are created locally on `jdnLinux2` by a separate timer at 3 AM — no SSH required for that step.

```
gpuServer1.local  ─────────────────────┐
jdnLinux2.local   ──── rsync over SSH ──▶  /media/jdn/Elements/  (USB drive on jdnLinux2)
spark-8d0d.local  ─────────────────────┘
```

### Drive Lifecycle (HDD longevity)

The backup drive is kept **unmounted and powered off** at all times except during the nightly backup window. Nothing touches the drive outside this window — no desktop automount, no OS journal writes, no atime updates.

```
01:55 AM  homebackup-drive-on.timer    →  mounts the drive
02:00 AM  homebackup.timer fires       →  all machines begin backing up
          (up to 15 min random stagger to avoid simultaneous rsync)
03:00 AM  homebackup-snapshot.timer    →  creates hardlink snapshots, prunes old ones
04:00 AM  homebackup-drive-off.timer   →  unmounts the drive (spins down via idle timeout)
```

A udev rule (`/etc/udev/rules.d/99-homebackup-drive.rules`) prevents the desktop from automounting the drive when it's detected. The drive-on, drive-off, and snapshot timers are only installed on `jdnLinux2` (the machine with the drive), detected automatically by `install.sh` via `BACKUP_DRIVE_LABEL` in the config.

### Backup Layout on Drive

```
/media/jdn/Elements/
├── gpuServer1/
│   ├── current/           # live mirror, updated each nightly run
│   │   └── home/jdn/...   # mirrors source filesystem (leading / stripped)
│   └── snapshots/
│       ├── 2026-04-30/    # hardlink copy — near-zero extra disk cost
│       └── ...
├── jdnLinux2/
│   ├── current/
│   └── snapshots/
└── spark-8d0d/
    ├── current/
    └── snapshots/
```

`current/` is a true rsync mirror. Snapshots are created via `cp -al` (hardlinks) so they take no extra space for unchanged files. Snapshots older than `SNAPSHOT_KEEP_DAYS` (default 30) are pruned automatically.

### SSH Security

- Each source machine has its own `ed25519` key
- `authorized_keys` on `jdnLinux2` uses `command=rrsync <path>` forced command — a key can only rsync into its own machine's subtree
- `no-pty,no-port-forwarding,no-X11-forwarding,no-agent-forwarding` on every key entry
- Snapshots run locally on `jdnLinux2` (not over SSH) so they are not affected by the rrsync restriction

### Scheduling

Backup timer fires at 02:00 daily with `Persistent=true` (catches up on missed runs) and `RandomizedDelaySec=900` (staggers machines randomly within 15 minutes). Drive mount/unmount and snapshot timers fire at fixed times and do not use a random delay.

---

## Repository Structure

```
homeBackup/
├── configs/
│   ├── gpuServer1.conf    # per-machine: source dirs, excludes, SSH key path
│   ├── jdnLinux2.conf     # also sets BACKUP_DRIVE_LABEL to enable drive lifecycle mgmt
│   └── spark-8d0d.conf
├── scripts/
│   ├── backup.sh          # main backup runner → /usr/local/bin/homebackup
│   ├── snapshot.sh        # creates hardlink snapshots, prunes old ones → /usr/local/bin/homebackup-snapshot
│   ├── drive-on.sh        # mount the backup drive → /usr/local/bin/homebackup-drive-on
│   ├── drive-off.sh       # unmount + power off → /usr/local/bin/homebackup-drive-off
│   ├── setup_target.sh    # run once on jdnLinux2 to prepare the drive and backup user
│   └── install.sh         # run on each source machine
├── systemd/
│   ├── homebackup.service
│   ├── homebackup.timer
│   ├── homebackup-snapshot.service   # installed on jdnLinux2 only
│   ├── homebackup-snapshot.timer
│   ├── homebackup-drive-on.service   # installed on jdnLinux2 only
│   ├── homebackup-drive-on.timer
│   ├── homebackup-drive-off.service
│   └── homebackup-drive-off.timer
└── docs/
    ├── adding-a-machine.md
    ├── drive-health.md
    └── recovery.md
```

---

## Initial Setup

### Step 1 — Prepare the target (jdnLinux2.local)

```bash
cd ~/Code/homeBackup
sudo bash scripts/setup_target.sh
```

Creates the directory structure on the drive, installs `rrsync`, and sets ownership.

### Step 2 — Install on jdnLinux2 first

```bash
bash scripts/install.sh
```

Because `jdnLinux2.conf` sets `BACKUP_DRIVE_LABEL`, this also installs the drive lifecycle timers (drive-on, drive-off, snapshot), the udev automount-block rule, an `/etc/fstab` entry for the drive, and a sudoers rule (`/etc/sudoers.d/homebackup`) that lets the `jdn` user mount and unmount the drive from systemd services without a password.

> **NTFS note:** `ntfs-3g` is not installed setuid on this system, so `jdn` cannot open the block device directly. The sudoers rule allows `sudo mount` and `sudo umount` for exactly `/media/jdn/Elements` — nothing else. The fstab entry specifies `ntfs-3g` with `uid=1000,gid=1000` so files are owned by `jdn` after mounting.

### Step 3 — Install on each other source machine

On `gpuServer1.local` and `spark-8d0d.local`:

```bash
cd ~/Code/homeBackup
bash scripts/install.sh
```

This generates an SSH key, installs the backup script and timer, and prints the public key.

### Step 4 — Authorize each key on the target

On `jdnLinux2.local`, for each remote machine:

```bash
sudo bash ~/Code/homeBackup/scripts/setup_target.sh --add-key <machine> "<pubkey>"
```

### Step 5 — Test

```bash
# Mount the drive manually for testing (normally handled by the 1:55 AM timer)
homebackup-drive-on

# Dry run
homebackup --dry-run

# Run snapshot manually (reads BACKUP_BASE and SNAPSHOT_KEEP_DAYS from /etc/homebackup/machine.conf)
homebackup-snapshot

# Power off when done
homebackup-drive-off
```

---

## Config File Format

Each `configs/<hostname>.conf` is a bash-sourceable file:

```bash
BACKUP_USER="jdn"
BACKUP_HOST="jdnLinux2.local"
BACKUP_BASE="/media/jdn/Elements"
BACKUP_SSH_KEY="/home/jdn/.ssh/id_ed25519_backup_<hostname>"
BACKUP_PORT=22
SNAPSHOT_KEEP_DAYS=30

# Only set on the machine that physically holds the drive:
# BACKUP_DRIVE_LABEL="Elements"

BACKUP_SOURCES=(
    "/home/jdn/Code/"
    "/home/jdn/Documents/"
    "/home/jdn/.ssh/"
)

BACKUP_EXCLUDES=(
    ".git/"
    "venv/"
    "node_modules/"
    ".cache/"
    # ...
)
```

Edit `BACKUP_SOURCES` and `BACKUP_EXCLUDES` to control what's backed up. After editing, re-run `install.sh` or copy the conf manually to `/etc/homebackup/machine.conf` on the deployed machine.

`SNAPSHOT_KEEP_DAYS` in `jdnLinux2.conf` controls retention for **all** machines — the snapshot script runs locally on jdnLinux2 and uses its own machine.conf.

---

## Monitoring

```bash
# Check all timer schedules (on jdnLinux2, shows all homebackup timers)
systemctl list-timers 'homebackup*'

# Watch a live backup run
journalctl -u homebackup -f

# Watch snapshot creation
journalctl -u homebackup-snapshot -f

# Watch drive mount/unmount
journalctl -u homebackup-drive-on -u homebackup-drive-off -f

# View last run logs
ls -lt /var/log/homebackup/
cat /var/log/homebackup/<machine>-<date>.log   # per-machine rsync log
cat /var/log/homebackup/snapshots-<date>.log   # snapshot log (on jdnLinux2)

# Manually mount/unmount the drive (e.g. for testing or recovery)
homebackup-drive-on
homebackup-drive-off
```

---

## Adding a New Machine

See [docs/adding-a-machine.md](docs/adding-a-machine.md).

## Recovery

See [docs/recovery.md](docs/recovery.md).

## Drive Health & Automount Reference

See [docs/drive-health.md](docs/drive-health.md) for SMART monitoring commands and notes on the automount-block approach.
