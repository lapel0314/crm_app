#!/usr/bin/env bash
set -euo pipefail

umask 077
export LC_ALL=C
export LANG=C

PG_BIN_DIR="${CRM_PG_BIN_DIR:-/usr/local/opt/libpq/bin}"
export PATH="$PG_BIN_DIR:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
RESTORE_ROOT="${CRM_RESTORE_WORK_ROOT:-$HOME/CRM_Backups/crm_app/restore-work}"
SOURCE=""
TARGET_DB_URL="${CRM_RESTORE_DB_URL:-}"
EXECUTE=0

usage() {
  cat <<'EOF'
Usage:
  scripts/restore_supabase_db_backup.sh --source <archive-or-rclone-path> [--target-db-url <url>] [--execute]

Examples:
  scripts/restore_supabase_db_backup.sh --source ~/CRM_Backups/crm_app/db/archives/crm_app_db_2026-06-18_040000.tar.gz
  scripts/restore_supabase_db_backup.sh --source gdrive:CRM_Backups/crm_app/db/daily/crm_app_db_2026-06-18_040000.tar.gz
  CRM_RESTORE_DB_URL='postgresql://...' scripts/restore_supabase_db_backup.sh --source ./backup.tar.gz --execute

Default mode only downloads/extracts and prints the restore plan.
Use --execute only for a new empty Supabase project or a verified restore target.
Do not execute against production unless you intentionally want a destructive recovery.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --source)
      SOURCE="${2:-}"
      shift 2
      ;;
    --target-db-url)
      TARGET_DB_URL="${2:-}"
      shift 2
      ;;
    --execute)
      EXECUTE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

[ -n "$SOURCE" ] || {
  usage
  exit 1
}

PSQL="$PG_BIN_DIR/psql"
if [ ! -x "$PSQL" ]; then
  PSQL="$(command -v psql 2>/dev/null || true)"
fi
[ -n "$PSQL" ] || {
  echo "psql not found. Install with: brew install libpq" >&2
  exit 1
}

mkdir -p "$RESTORE_ROOT"
RUN_DIR="$RESTORE_ROOT/$(date +%Y-%m-%d_%H%M%S)"
mkdir -p "$RUN_DIR"

ARCHIVE_PATH="$SOURCE"
if [[ "$SOURCE" == *:* && "$SOURCE" != /* ]]; then
  command -v rclone >/dev/null 2>&1 || {
    echo "rclone is required for remote restore source: $SOURCE" >&2
    exit 1
  }
  ARCHIVE_PATH="$RUN_DIR/$(basename "$SOURCE")"
  rclone copyto "$SOURCE" "$ARCHIVE_PATH"
  if rclone lsf "$(dirname "$SOURCE")" --files-only | grep -qx "$(basename "$SOURCE").sha256"; then
    rclone copyto "$SOURCE.sha256" "$ARCHIVE_PATH.sha256"
  fi
fi

[ -f "$ARCHIVE_PATH" ] || {
  echo "Archive not found: $ARCHIVE_PATH" >&2
  exit 1
}

if [ -f "$ARCHIVE_PATH.sha256" ]; then
  (cd "$(dirname "$ARCHIVE_PATH")" && shasum -a 256 -c "$(basename "$ARCHIVE_PATH").sha256")
fi

tar -xzf "$ARCHIVE_PATH" -C "$RUN_DIR"
EXTRACTED_DIR="$(find "$RUN_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)"

for required in roles.sql schema.sql data.sql MANIFEST.txt; do
  [ -f "$EXTRACTED_DIR/$required" ] || {
    echo "Missing $required in archive" >&2
    exit 1
  }
done

echo "Extracted backup:"
echo "  $EXTRACTED_DIR"
echo
cat "$EXTRACTED_DIR/MANIFEST.txt"
echo

if [ "$EXECUTE" -ne 1 ]; then
  cat <<EOF
Dry run only. Restore order:
  1. roles.sql
  2. schema.sql
  3. data.sql

To restore into a new empty Supabase database:
  CRM_RESTORE_DB_URL='postgresql://...' $0 --source '$SOURCE' --execute

Recommended recovery flow:
  1. Restore into a separate temporary Supabase project.
  2. Inspect the missing/bad records there.
  3. Export only the needed rows.
  4. Insert/update those rows in production after review.
EOF
  exit 0
fi

[ -n "$TARGET_DB_URL" ] || {
  echo "Missing target DB URL. Set CRM_RESTORE_DB_URL or pass --target-db-url." >&2
  exit 1
}

echo "Executing restore against target DB."
echo "This should be a new empty restore target, not production."
read -r -p "Type RESTORE to continue: " CONFIRM
[ "$CONFIRM" = "RESTORE" ] || {
  echo "Restore cancelled."
  exit 1
}

"$PSQL" "$TARGET_DB_URL" -v ON_ERROR_STOP=1 -f "$EXTRACTED_DIR/roles.sql"
"$PSQL" "$TARGET_DB_URL" -v ON_ERROR_STOP=1 -f "$EXTRACTED_DIR/schema.sql"
"$PSQL" "$TARGET_DB_URL" -v ON_ERROR_STOP=1 -f "$EXTRACTED_DIR/data.sql"

echo "Restore complete."
