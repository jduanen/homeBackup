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

## Restore a single file or directory

```bash
# From the target machine, copy directly:
cp /media/jdn/Elements/<machine>/current/home/jdn/Documents/important.pdf ~/Documents/

# Or rsync from a remote machine:
rsync -av backup@jdnLinux2.local:./home/jdn/Documents/important.pdf ~/Documents/
```

Note: the `backup` SSH key allows rsync access restricted to the machine's own subtree.

## Restore from a snapshot

Snapshots are hardlink copies of `current/` at the time they were made:

```bash
ls /media/jdn/Elements/<machine>/snapshots/    # list available dates
rsync -av /media/jdn/Elements/<machine>/snapshots/2026-04-29/home/jdn/ ~/
```

## Full machine restore

To restore an entire machine's home directory from the live backup:

```bash
rsync -aHAX --numeric-ids \
    backup@jdnLinux2.local:./home/jdn/ \
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
```
