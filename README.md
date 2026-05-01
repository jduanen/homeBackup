# HomeBackups

Push-based rsync backup system for home machines. Each source machine pushes nightly to an external USB drive on `jdnLinux2.local`.

## Design

### Architecture

Each source machine runs a systemd timer that fires at 2 AM and calls `homebackup` (a bash script wrapping rsync). The script pushes over SSH to a dedicated `backup` user on `jdnLinux2.local`. SSH keys are restricted using `rrsync` so each machine can only write to its own subtree on the drive.

```
gpuServer1.local  ─────────────────────┐
jdnLinux2.local   ──── rsync over SSH ──▶  /media/jdn/Elements/  (USB drive on jdnLinux2)
spark-8d0d.local  ─────────────────────┘
```

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

- Dedicated `backup` system user on `jdnLinux2.local` — no password login, no sudo
- Each source machine has its own `ed25519` key
- `authorized_keys` uses `command=rrsync <path>` forced command — a key can only rsync into its own machine's subtree

### Scheduling

Systemd timer fires at 02:00 daily with `Persistent=true` (catches up on missed runs) and `RandomizedDelaySec=900` (staggers the three machines randomly within a 15-minute window to avoid simultaneous rsync).

---

## Repository Structure

```
HomeBackups/
├── configs/
│   ├── gpuServer1.conf    # per-machine: source dirs, excludes, SSH key path
│   ├── jdnLinux2.conf
│   └── spark-8d0d.conf
├── scripts/
│   ├── backup.sh          # main backup runner — installed to /usr/local/bin/homebackup
│   ├── setup_target.sh    # run once on jdnLinux2 to prepare the drive
│   └── install.sh         # run on each source machine
├── systemd/
│   ├── homebackup.service
│   └── homebackup.timer
└── docs/
    ├── adding-a-machine.md
    └── recovery.md
```

---

## Initial Setup

### Step 1 — Prepare the target (jdnLinux2.local)

```bash
cd ~/Code/HomeBackups
sudo bash scripts/setup_target.sh
```

This creates the `backup` user, installs `rrsync`, and sets up the drive mount and directory structure. Follow the on-screen prompts for the USB drive UUID and `/etc/fstab` entry.

### Step 2 — Install on each source machine

On each machine (`gpuServer1.local`, `jdnLinux2.local`, `spark-8d0d.local`):

```bash
cd ~/Code/HomeBackups
bash scripts/install.sh
```

This:
1. Generates `/home/jdn/.ssh/id_ed25519_backup_<hostname>` (no passphrase)
2. Installs `/usr/local/bin/homebackup` and `/etc/homebackup/machine.conf`
3. Enables the `homebackup.timer` systemd unit
4. Prints the public key to add to the target

### Step 3 — Authorize the key on the target

On `jdnLinux2.local`, for each source machine:

```bash
sudo bash ~/Code/HomeBackups/scripts/setup_target.sh --add-key <machine> "<pubkey>"
```

### Step 4 — Test

```bash
homebackup --dry-run
```

---

## Config File Format

Each `configs/<hostname>.conf` is a bash-sourceable file:

```bash
BACKUP_USER="backup"
BACKUP_HOST="jdnLinux2.local"
BACKUP_BASE="/media/jdn/Elements"
BACKUP_SSH_KEY="/home/jdn/.ssh/id_ed25519_backup_<hostname>"
BACKUP_PORT=22
SNAPSHOT_KEEP_DAYS=30

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

Edit the `BACKUP_SOURCES` and `BACKUP_EXCLUDES` arrays to control what gets backed up. Changes take effect on the next run (the config is copied to `/etc/homebackup/machine.conf` by `install.sh` — re-run install or copy manually to update a deployed machine).

---

## Monitoring

```bash
# Check timer schedule
systemctl list-timers homebackup.timer

# Watch a live backup run
journalctl -u homebackup -f

# View last run log
ls -lt /var/log/homebackup/
cat /var/log/homebackup/<machine>-<date>.log

# Check last run status
systemctl status homebackup
```

---

## Adding a New Machine

See [docs/adding-a-machine.md](docs/adding-a-machine.md).

## Recovery

See [docs/recovery.md](docs/recovery.md).
