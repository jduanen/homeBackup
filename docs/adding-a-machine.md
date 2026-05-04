# Adding a New Machine to the Backup Group

## Steps

### 1. Create a config file

On any machine with the repo cloned:

```bash
cd ~/Code/homeBackup
cp configs/gpuServer1.conf configs/<newhostname>.conf
```

Edit `configs/<newhostname>.conf` — adjust `BACKUP_SOURCES`, `BACKUP_EXCLUDES`, and `BACKUP_SSH_KEY` (the key path should end in `_backup_<newhostname>`). The `BACKUP_HOST`, `BACKUP_USER`, `BACKUP_BASE`, and `SNAPSHOT_KEEP_DAYS` stay the same.

Commit and push:

```bash
git add configs/<newhostname>.conf
git commit -m "Add backup config for <newhostname>"
git push
```

### 2. Prepare the target drive

On `jdnLinux2.local`, pull the repo and create the backup directory structure:

```bash
cd ~/Code/homeBackup && git pull
sudo bash scripts/setup_target.sh --add-machine <newhostname>
```

This creates `current/` and `snapshots/` directories on the drive for the new machine. The snapshot timer on jdnLinux2 will automatically pick up the new machine directory without any further configuration.

### 3. Install on the new machine

On the new machine, clone or pull the repo, then run:

```bash
cd ~/Code/homeBackup
bash scripts/install.sh
```

This generates the backup SSH key, installs the backup script and systemd timer, and prints the public key.

### 4. Authorize the key on the target

On `jdnLinux2.local`:

```bash
sudo bash ~/Code/homeBackup/scripts/setup_target.sh --add-key <newhostname> "<pubkey>"
```

### 5. Test

On the new machine:

```bash
homebackup --dry-run
```

Verify no SSH errors and the expected rsync output appears. Then check:

```bash
systemctl list-timers homebackup.timer
```

The next nightly run should appear in the list. After the first real backup completes, the 3:00 AM snapshot timer on jdnLinux2 will include the new machine automatically.
