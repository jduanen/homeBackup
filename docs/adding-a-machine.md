# Adding a New Machine to the Backup Group

## Steps

### 1. Create a config file

On any machine with the repo cloned:

```bash
cd ~/Code/HomeBackups
cp configs/gpuServer1.conf configs/<newhostname>.conf
```

Edit `configs/<newhostname>.conf` — adjust `BACKUP_SOURCES`, `BACKUP_EXCLUDES`, and `BACKUP_SSH_KEY` (the key path should end in `_backup_<newhostname>`). The `BACKUP_HOST`, `BACKUP_USER`, and `BACKUP_BASE` stay the same.

Commit and push:

```bash
git add configs/<newhostname>.conf
git commit -m "Add backup config for <newhostname>"
git push
```

### 2. Prepare the target drive

On `jdnLinux2.local`, pull the repo and create the backup directory:

```bash
cd ~/Code/HomeBackups && git pull
sudo bash scripts/setup_target.sh --add-machine <newhostname>
```

### 3. Install on the new machine

On the new machine, clone or pull the repo, then run:

```bash
cd ~/Code/HomeBackups
bash scripts/install.sh
```

Copy the public key printed at the end.

### 4. Authorize the key on the target

On `jdnLinux2.local`:

```bash
sudo bash ~/Code/HomeBackups/scripts/setup_target.sh --add-key <newhostname> "<pubkey>"
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

The next nightly run should appear in the list.
