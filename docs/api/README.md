# Segment API Reference

This directory contains auto-generated documentation for all backup system segments.

## Core Segments

- [01 - Validates all required configuration variables and dependencies
](01_validate_config.md)
- [02 - Initializes logging metadata and backup log location](02_init_logging.md)
- [03 - Powers on external HDD via Shelly Plug Plus with auto-off timer](03_shelly_power_on.md)
- [04 - Waits for backup device to become available with timeout](04_wait_device.md)
- [05 - Mounts backup device with robust error recovery
](05_mount_backup.md)
- [06 - Validates that correct UUID is mounted at backup location](06_validate_mount.md)
- [07 - Initializes Borg repository if it doesn't exist
](07_init_borg_repo.md)
- [08 - Creates Borg backup archive from configured sources](08_borg_backup.md)
- [09 - Verifies integrity of latest Borg backup archive](09_borg_verify.md)
- [10 - Prunes old archives according to retention policy and compacts repo](10_borg_prune.md)
- [11 - Parks HDD read/write heads and spins down drive before power-off](11_hdd_spindown.md)
- [12 - Safely unmounts backup device with robust error recovery (cleanup-safe)
](12_unmount_backup.md)
- [13 - Powers off external HDD via Shelly Plug Plus](13_shelly_power_off.md)
- [00 - Restarts Docker containers that were running before backup (runs in POST_BACKUP phase)](post_01_docker_start.md)
- [00 - Export Borg repository keys and recovery information to encrypted ZIP archive](post_01_export_recovery_keys.md)
- [00 - Export Borg repository keys and recovery information to encrypted ZIP archive](post_02_export_recovery_keys.md)
- [00 - Dumps Nextcloud database using Docker exec (container-based approach)](pre_01_nextcloud_db_dump.md)
- [00 - Stops Docker containers and saves running container IDs](pre_02_docker_stop.md)

## Generation

Documentation is automatically generated from segment source files using:

```bash
./generate-segment-docs.sh
```

Last generated: 2026-02-06 14:23:41

## Guidelines

- This documentation is **auto-generated** - do not edit manually
- Update segment source code comments to improve documentation
- Run `generate-segment-docs.sh` after changes


