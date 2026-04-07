# Rclone Cloud Backup Documentation

This document explains how `rclone` is used to sync local backups to Backblaze B2 storage.

## Prerequisites

- **rclone**: Must be installed on the host machine.
- **B2 Buckets**: A bucket named `nl-infra-services-prod-backup` should exist in your Backblaze account.

## Configuration

### Robust Configuration (Used in Scripts)
To avoid configuration conflicts, the `cloud-sync.sh` script uses the **global B2 backend** (`:b2`) combined with standard environment variables. This method is the most reliable for automation:

```bash
export RCLONE_B2_ACCOUNT="0035be8662d09360000000003"
export RCLONE_B2_KEY="K003ESHiGWlnThr/Mux1vU93XkXFqPg"
rclone sync /local/path :b2:bucket/path
```

### Manual Configuration (rclone config)
If you prefer to use a named remote (like `s3-backup`), run `rclone config` and follow these steps:

1.  **n) New remote**: Type `n`
2.  **name**: Type `s3-backup`
3.  **Storage**: Type `b2` (or select the number for Backblaze B2)
4.  **account**: `0035be8662d09360000000003`
5.  **key**: `K003ESHiGWlnThr/Mux1vU93XkXFqPg`
6.  **hard_delete**: Press `Enter` (defaults to `false` - safer for versioning)
7.  **Edit advanced config?**: Type `n`
8.  **Keep this "s3-backup" remote?**: Type `y`
9.  **Quit config**: Type `q`

## Sync Workflow

The `cloud-sync.sh` script automates the synchronization of backups for the following services:

| Service | Local Path | Remote Path |
| :--- | :--- | :--- |
| **Postgres** | `/root/Desktop/docker-infra-data/prod/postgres/pg_backups` | `s3-backup:nl-infra-services-prod-backup/postgres` |
| **RabbitMQ** | `/root/Desktop/docker-infra-data/prod/rabbitmq/backups` | `s3-backup:nl-infra-services-prod-backup/rabbitmq` |
| **Meilisearch** | `/root/Desktop/docker-infra-data/prod/meilisearch/meili_data/dumps` | `s3-backup:nl-infra-services-prod-backup/meilisearch` |

## Usage

### 1. Trigger All Backups
First, ensure all local backups are up to date:
```bash
/root/Desktop/Experiments-infra/nestlancer-infrastructure-prod/scripts/backup-all.sh prod
```

### 2. Sync to Cloud
Run the cloud sync script to upload backups to Backblaze B2:
```bash
/root/Desktop/Experiments-infra/nestlancer-infrastructure-prod/scripts/cloud-sync.sh
```

### 3. Monitoring
Check the logs for any errors:
- **Local Backups**: `/root/Desktop/Experiments-infra/nestlancer-infrastructure-prod/logs/backups.log`
- **Cloud Sync**: `/root/Desktop/Experiments-infra/nestlancer-infrastructure-prod/logs/cloud-sync.log`

## Troubleshooting

### 1. "remote not found"
Ensure the remote name `s3-backup` is correctly initialized via `rclone config` as shown above.

### 2. "401 unauthorized"
This error indicates that the **Account ID / Key ID** or **Application Key** is invalid.
- Go to the **Backblaze B2 Console** > **App Keys**.
- Verify that your `keyID` matches the `account` field in `rclone.md` and `scripts/cloud-sync.sh`.
- If you lost your `applicationKey`, you will need to generate a new one and update the scripts.

### 3. "404 not found"
Ensure the bucket `nl-infra-services-prod-backup` exists in your Backblaze account.
