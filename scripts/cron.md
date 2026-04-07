# Automating Backups with Cron

To automate the execution of local backups and cloud syncing, you can set up a cron job on your host machine. This ensures that your local services (Postgres, RabbitMQ, Meilisearch) are regularly backed up and securely synchronized to Backblaze B2 storage without manual intervention.

## 1. Locate the Scripts
You will need the absolute paths to the backup and sync scripts. For this repository (adjust if you cloned elsewhere):

- **Local Backup Script:** `/root/Desktop/Experiments-infra/nestlancer-infrastructure-prod/scripts/backup-all.sh`
- **Cloud Sync Script:** `/root/Desktop/Experiments-infra/nestlancer-infrastructure-prod/scripts/cloud-sync.sh`

*(Note: Adjust the paths accordingly if your repository is located elsewhere.)*

## 2. Edit the Crontab
Open the cron table editor. Depending on your environment and which user owns the backup folders, you may want to do this as `root`:
```bash
sudo crontab -e
```

## 3. Configure the Cron Schedule
You can schedule the local backup and the cloud sync to run consecutively. 

Add the following lines to your crontab. This example runs the local backup daily at 2:00 AM, and the cloud sync at 3:00 AM:

```cron
# Run local backups daily at 2:00 AM
0 2 * * * /root/Desktop/Experiments-infra/nestlancer-infrastructure-prod/scripts/backup-all.sh prod >/dev/null 2>&1

# Sync backups to Backblaze B2 daily at 3:00 AM
0 3 * * * /root/Desktop/Experiments-infra/nestlancer-infrastructure-prod/scripts/cloud-sync.sh --quiet >/dev/null 2>&1
```

Alternatively, you can chain them together so that `cloud-sync.sh` only executes if the local `backup-all.sh` succeeds:
```cron
# Run local backups at 2:00 AM and, if successful, immediately run cloud sync
0 2 * * * /root/Desktop/Experiments-infra/nestlancer-infrastructure-prod/scripts/backup-all.sh prod >/dev/null 2>&1 && /root/Desktop/Experiments-infra/nestlancer-infrastructure-prod/scripts/cloud-sync.sh --quiet >/dev/null 2>&1
```

### Breakdown of Cron Fields
A cron expression has 5 fields (`* * * * *`):
- **Minute:** `0`
- **Hour:** `2` (2 AM)
- **Day of month:** `*` (every day)
- **Month:** `*` (every month)
- **Day of week:** `*` (every day)

## 4. Recommended Flags for Cron
When automating `cloud-sync.sh` via cron, it is recommended to pass specific flags designed for headless environments:
- `--quiet` (or `-q`): Suppresses console output. The script will still write to its log file.
- `--cleanup`: *(Optional)* Add this flag if you want the cron job to automatically delete remote files that are older than the defined retention period (defaults to 90 days).

Example with complete automated cleanup:
```cron
0 3 * * * /root/Desktop/Experiments-infra/nestlancer-infrastructure-prod/scripts/cloud-sync.sh --quiet --cleanup >/dev/null 2>&1
```

## 5. Monitoring & Logs
Because we route standard output to `/dev/null` in the crontab entries, you can rely entirely on the scripts' built-in logging and alerting mechanisms.

- **Alerts:** Both scripts have a webhook alerting system configured (e.g., Discord/Slack) securely sending immediate feedback on `SUCCESS` or `FAILURE`.
- **Local Logs:** Check these files if backups are failing:
  - Backups Log: `/root/Desktop/Experiments-infra/nestlancer-infrastructure-prod/logs/backups.log`
  - Cloud Sync Log: `/root/Desktop/Experiments-infra/nestlancer-infrastructure-prod/logs/cloud-sync.log`
  - Rclone Transfers Log: `/root/Desktop/Experiments-infra/nestlancer-infrastructure-prod/logs/rclone-detail.log`

## 6. Possible Cron Jobs

Here are a few common and useful cron job configurations you can choose from based on your needs:

### A. Daily Backups (Recommended)
Run local backups at midnight and sync to the cloud at 1:00 AM.
```cron
# Run local backups at 00:00 (Midnight)
0 0 * * * /root/Desktop/Experiments-infra/nestlancer-infrastructure-prod/scripts/backup-all.sh prod >/dev/null 2>&1

# Run cloud sync at 01:00 AM
0 1 * * * /root/Desktop/Experiments-infra/nestlancer-infrastructure-prod/scripts/cloud-sync.sh --quiet --cleanup >/dev/null 2>&1
```

### B. Twice-Daily Backups (High Availability)
Run backups every 12 hours (e.g., at 2:00 AM and 2:00 PM) for more frequent data points.
```cron
# Every 12 hours at minute 0
0 2,14 * * * /root/Desktop/Experiments-infra/nestlancer-infrastructure-prod/scripts/backup-all.sh prod >/dev/null 2>&1

# Wait 30 minutes, then sync
30 2,14 * * * /root/Desktop/Experiments-infra/nestlancer-infrastructure-prod/scripts/cloud-sync.sh --quiet --cleanup >/dev/null 2>&1
```

### C. Weekly Backups (Low Traffic)
Run local backups and cloud sync once a week, for example on Sunday at 3:00 AM. (0 = Sunday).
```cron
# Every Sunday at 3:00 AM, backup and sync
0 3 * * 0 /root/Desktop/Experiments-infra/nestlancer-infrastructure-prod/scripts/backup-all.sh prod >/dev/null 2>&1 && /root/Desktop/Experiments-infra/nestlancer-infrastructure-prod/scripts/cloud-sync.sh --quiet --cleanup >/dev/null 2>&1
```

### D. Hourly Local Backups, Daily Cloud Sync
Take local backups every hour, but only sync to the cloud once a day at midnight to save bandwidth.
```cron
# Hourly local backups at the top of the hour
0 * * * * /root/Desktop/Experiments-infra/nestlancer-infrastructure-prod/scripts/backup-all.sh prod >/dev/null 2>&1

# Daily cloud sync at Midnight
0 0 * * * /root/Desktop/Experiments-infra/nestlancer-infrastructure-prod/scripts/cloud-sync.sh --quiet --cleanup >/dev/null 2>&1
```
