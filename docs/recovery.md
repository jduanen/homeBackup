# Recovery Guide

The backup layout mirrors the source filesystem under `current/`, so recovery is a direct rsync back — no special tools required.

## Browse the backup

On `jdnLinux2.local`, the USB drive is at `/media/jdn/Elements/`. Each machine has a `current/` tree:

```
/media/jdn/Elements/
├── gpuServer1/
│   ├── current/home/jdn/...
│   └── snapshots/2026-04-30/home/jdn/...
├── jdnLinux2/
│   └── current/...
└── spark-8d0d/
    └── current/...
```

Mount the drive first if it isn't already:

```bash
homebackup-drive-on
```

## Restore a single file or directory

**On jdnLinux2 (direct copy from mounted drive):**

```bash
cp /media/jdn/Elements/<machine>/current/home/jdn/Documents/important.pdf ~/Documents/
```

**From a remote source machine (rsync over SSH using the backup key):**

```bash
rsync -av \
    -e "ssh -i ~/.ssh/id_ed25519_backup_<machine>" \
    jdn@jdnLinux2.local:./home/jdn/Documents/important.pdf \
    ~/Documents/
```

The backup SSH key uses `rrsync` on the server side, so the path is relative to `current/` — use `./home/jdn/...` not `/media/jdn/Elements/...`.

## Restore from a snapshot

Snapshots are hardlink copies of `current/` taken nightly at 3:00 AM by `homebackup-snapshot`. They are created after all machines finish backing up, so the newest snapshot may be from yesterday.

```bash
# List available snapshots
ls /media/jdn/Elements/<machine>/snapshots/

# Restore from a specific date (on jdnLinux2)
rsync -aHAX /media/jdn/Elements/<machine>/snapshots/2026-04-29/home/jdn/ ~/

# Or from a remote machine via SSH:
rsync -aHAX \
    -e "ssh -i ~/.ssh/id_ed25519_backup_<machine>" \
    jdn@jdnLinux2.local:./  \
    ~/
```

Note: when using the backup SSH key, you are restricted to the `current/` subtree for that machine. To restore from a snapshot remotely, copy from the snapshot to `current/` on jdnLinux2 first, then rsync back.

## Full machine restore

To restore an entire machine's home directory from the live backup (run on jdnLinux2 or copy files directly):

```bash
rsync -aHAX --numeric-ids \
    /media/jdn/Elements/<machine>/current/home/jdn/ \
    /home/jdn/
```

## Check last backup status

```bash
# On the source machine:
journalctl -u homebackup -n 50
systemctl status homebackup

# View the log file directly:
ls -lt /var/log/homebackup/
cat /var/log/homebackup/<machine>-<date>.log

# Check snapshot log (on jdnLinux2):
cat /var/log/homebackup/snapshots-<date>.log
```
