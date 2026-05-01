# Drive Health & Automount Reference

## Checking SMART Health

The backup drive is `/dev/sdc` (verify with `lsblk`).

```bash
# Quick health status (PASSED / FAILED)
sudo smartctl -H /dev/sdc

# Full attribute dump
sudo smartctl -a /dev/sdc

# Extended output including error log
sudo smartctl -x /dev/sdc

# Run a short self-test (~2 min, non-destructive)
sudo smartctl -t short /dev/sdc

# Run a long self-test (~hours, thorough)
sudo smartctl -t long /dev/sdc
```

Key attributes to watch in `smartctl -a` output:

| Attribute | ID | What it means |
|---|---|---|
| Reallocated_Sector_Ct | 5 | Bad sectors remapped — any non-zero is a warning |
| Spin_Retry_Count | 10 | Motor spin-up failures |
| Current_Pending_Sector | 197 | Sectors awaiting reallocation |
| Offline_Uncorrectable | 198 | Sectors that couldn't be corrected |
| Power_On_Hours | 9 | Total drive runtime |

Install `smartmontools` if not present: `sudo apt install smartmontools`

---

## Preventing Automount

### Our approach — udev rule (recommended, drive-specific)

`install.sh` writes `/etc/udev/rules.d/99-homebackup-drive.rules`:

```
SUBSYSTEM=="block", ENV{ID_FS_LABEL}=="Elements", ENV{UDISKS_AUTO}="0"
```

This blocks only the Elements drive from being automounted by udisks2/GNOME. All other drives still automount normally.

### Alternative — GNOME-wide disable (nuclear option)

Disables automount for **all** removable media:

```bash
gsettings set org.gnome.desktop.media-handling automount false
gsettings set org.gnome.desktop.media-handling automount-open false
nautilus -q   # restart Nautilus to apply
```

To re-enable: set both back to `true`.

### Alternative — fstab `noauto`

If the drive has an `/etc/fstab` entry, add `noauto` to prevent mount-on-boot:

```
UUID=<uuid>  /media/jdn/Elements  ext4  defaults,nofail,noauto  0  2
```

Get the UUID with: `blkid /dev/sdc1`
