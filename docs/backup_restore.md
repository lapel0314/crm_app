# CRM Database Backup and Restore

This project backs up the Supabase database only. Supabase Storage image files are intentionally excluded.

## Current policy

- Daily full database backup.
- Keep daily backups for 90 days.
- Keep the first day of each month permanently.
- Never overwrite a single `latest.sql` file.
- Store backups in Google Drive through `rclone`.

Default Google Drive path:

```text
gdrive:CRM_Backups/crm_app/db/
  daily/
  monthly/YYYY-MM/
```

## Required local tools

```bash
brew install libpq
```

The scripts use:

- `supabase`
- `rclone`
- `/usr/local/opt/libpq/bin/pg_dump`
- `/usr/local/opt/libpq/bin/pg_dumpall`
- `/usr/local/opt/libpq/bin/psql`

## Manual backup

```bash
cd /Users/lapel/crm_app
chmod +x scripts/backup_supabase_db_to_gdrive.sh
scripts/backup_supabase_db_to_gdrive.sh
```

The script creates a local archive under:

```text
~/CRM_Backups/crm_app/db/archives/
```

Then it uploads the archive and `.sha256` file to:

```text
gdrive:CRM_Backups/crm_app/db/daily/
```

On the first day of the month it also copies the archive to:

```text
gdrive:CRM_Backups/crm_app/db/monthly/YYYY-MM/
```

## Automatic daily backup

Install the macOS LaunchAgent:

```bash
cd /Users/lapel/crm_app
chmod +x scripts/install_daily_db_backup_launchd.sh
scripts/install_daily_db_backup_launchd.sh
```

Default schedule: every day at 04:00.

Change schedule:

```bash
CRM_BACKUP_HOUR=3 CRM_BACKUP_MINUTE=30 scripts/install_daily_db_backup_launchd.sh
```

Check job:

```bash
launchctl print gui/$(id -u)/com.pinkphone.crm.db-backup
```

Run once manually:

```bash
scripts/backup_supabase_db_to_gdrive.sh
```

## Restore strategy

Do not restore directly over production for ordinary mistakes.

Recommended recovery flow:

1. Download/extract the backup.
2. Restore into a new temporary Supabase project.
3. Find the missing or incorrect records.
4. Export only the needed rows.
5. Insert/update those rows in production after review.

This avoids overwriting valid production data.

## Inspect a backup

```bash
scripts/restore_supabase_db_backup.sh \
  --source gdrive:CRM_Backups/crm_app/db/daily/crm_app_db_YYYY-MM-DD_HHMMSS.tar.gz
```

Default mode only extracts and prints the restore plan.

## Restore into a temporary project

Create a new Supabase project, get its Postgres connection string, then run:

```bash
CRM_RESTORE_DB_URL='postgresql://postgres.xxx:password@aws-...pooler.supabase.com:5432/postgres?sslmode=require' \
  scripts/restore_supabase_db_backup.sh \
  --source gdrive:CRM_Backups/crm_app/db/daily/crm_app_db_YYYY-MM-DD_HHMMSS.tar.gz \
  --execute
```

The script restores in this order:

1. `roles.sql`
2. `schema.sql`
3. `data.sql`

## Capacity estimate for Google Drive 100GB

Current DB size is about 24MB.

Expected capacity without images:

- Current scale: more than 10 years of daily backups.
- Around 10,000 customers: roughly 65-100 daily backups.
- Around 50,000 customers: roughly 13-20 daily backups.
- Around 100,000 customers: roughly 6-10 daily backups.

The daily retention should be reduced as the database grows. Monthly backups remain permanent.

## Important notes

- Backup archives may contain customer personal data.
- Do not commit backup archives to Git.
- Keep Google account two-factor authentication enabled.
- Test restore at least once after changing schema or backup scripts.
