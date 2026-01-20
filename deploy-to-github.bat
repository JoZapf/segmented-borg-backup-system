@echo off
REM Deploy dev-data.env.example fix to GitHub
REM Generated: 2026-01-20

echo ========================================
echo Deploying dev-data.env.example to GitHub
echo ========================================
echo.

cd /d E:\Projects\linux-backup-system

echo Checking Git status...
git status
echo.

echo Staging changes...
git add config/profiles/dev-data.env.example
echo.

echo Committing changes...
git commit -m "fix: Update dev-data.env.example to match v1.2.0 structure

- Changed: Updated @changed date to 2026-01-20
- Changed: Simplified POST_BACKUP comment (removed redundant text)
- Changed: Updated BACKUP_MNT default from /mnt/extern_backup to /mnt/system_backup
  * Added comment explaining internal vs external HDD mount points
- Changed: Updated HDD_DEVICE example from /dev/sdX to /dev/sda
  * Added comment explaining internal HDD vs external USB device paths

This brings the example file in sync with the actual dev-data.env structure
where recovery key export was moved to POST_BACKUP phase for proper
repository accessibility."
echo.

echo Pushing to GitHub...
git push origin main
echo.

echo ========================================
echo Deployment complete!
echo ========================================
echo.
echo Next steps:
echo 1. Manually copy E:\Projects\linux-backup-system\config\profiles\dev-data.env
echo    to Ubuntu server at /opt/backup-system/config/profiles/dev-data.env
echo 2. Test backup: sudo /opt/backup-system/run-backup.sh dev-data
echo 3. Verify recovery key export works
echo.

pause
