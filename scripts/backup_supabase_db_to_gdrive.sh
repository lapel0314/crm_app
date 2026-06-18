#!/usr/bin/env bash
set -euo pipefail

umask 077
export LC_ALL=C
export LANG=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PROJECT_REF="${CRM_SUPABASE_PROJECT_REF:-ysafjyubntkeorriywmu}"
LOCAL_BACKUP_ROOT="${CRM_BACKUP_LOCAL_ROOT:-$HOME/CRM_Backups/crm_app/db}"
GDRIVE_REMOTE="${CRM_BACKUP_GDRIVE_REMOTE:-gdrive:CRM_Backups/crm_app/db}"
KEEP_DAILY_DAYS="${CRM_BACKUP_KEEP_DAILY_DAYS:-90}"
PG_BIN_DIR="${CRM_PG_BIN_DIR:-/usr/local/opt/libpq/bin}"
export PATH="$PG_BIN_DIR:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
STAMP="$(date +%Y-%m-%d_%H%M%S)"
DAY="$(date +%d)"
MONTH="$(date +%Y-%m)"
HOSTNAME_VALUE="$(hostname)"
GIT_COMMIT="$(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"

WORK_DIR="$LOCAL_BACKUP_ROOT/work/$STAMP"
ARCHIVE_DIR="$LOCAL_BACKUP_ROOT/archives"
LOG_DIR="$LOCAL_BACKUP_ROOT/logs"
ARCHIVE_NAME="crm_app_db_${STAMP}.tar.gz"
ARCHIVE_PATH="$ARCHIVE_DIR/$ARCHIVE_NAME"
SHA_PATH="$ARCHIVE_PATH.sha256"
LOG_PATH="$LOG_DIR/${STAMP}.log"

mkdir -p "$WORK_DIR" "$ARCHIVE_DIR" "$LOG_DIR"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_PATH"
}

fail() {
  log "ERROR: $*"
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

find_pg_tool() {
  local tool="$1"
  if [ -x "$PG_BIN_DIR/$tool" ]; then
    printf '%s\n' "$PG_BIN_DIR/$tool"
    return 0
  fi
  command -v "$tool" 2>/dev/null || return 1
}

run_supabase_dry_dump() {
  local label="$1"
  local output_file="$2"
  shift 2

  local dry_script
  dry_script="$(mktemp "${TMPDIR:-/tmp}/crm_supabase_${label}.XXXXXX")"
  chmod 600 "$dry_script"

  log "Preparing ${label} dump"
  if ! supabase db dump --linked --dry-run "$@" >"$dry_script" 2>>"$LOG_PATH"; then
    rm -f "$dry_script"
    fail "Failed to prepare ${label} dump"
  fi

  log "Writing ${label} dump"
  if ! PATH="$PG_BIN_DIR:$PATH" bash "$dry_script" >"$output_file" 2>>"$LOG_PATH"; then
    rm -f "$dry_script"
    fail "Failed to write ${label} dump"
  fi

  rm -f "$dry_script"
}

need_cmd supabase
need_cmd rclone
need_cmd gzip
need_cmd tar
need_cmd shasum

PG_DUMP="$(find_pg_tool pg_dump || true)"
PG_DUMPALL="$(find_pg_tool pg_dumpall || true)"
[ -n "$PG_DUMP" ] || fail "pg_dump not found. Install with: brew install libpq"
[ -n "$PG_DUMPALL" ] || fail "pg_dumpall not found. Install with: brew install libpq"

log "Starting CRM DB backup"
log "Project root: $PROJECT_ROOT"
log "Project ref: $PROJECT_REF"
log "Git commit: $GIT_COMMIT"
log "Local archive: $ARCHIVE_PATH"
log "Google Drive remote: $GDRIVE_REMOTE"

cat >"$WORK_DIR/MANIFEST.txt" <<EOF
CRM app database backup
created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
hostname=$HOSTNAME_VALUE
project_ref=$PROJECT_REF
project_root=$PROJECT_ROOT
git_commit=$GIT_COMMIT
supabase_cli=$(supabase --version 2>/dev/null | head -n 1)
pg_dump=$("$PG_DUMP" --version 2>/dev/null | head -n 1)
backup_kind=roles_schema_data
storage_included=false
restore_order=roles.sql,schema.sql,data.sql
EOF

run_supabase_dry_dump "roles" "$WORK_DIR/roles.sql" --role-only
run_supabase_dry_dump "schema" "$WORK_DIR/schema.sql"
run_supabase_dry_dump "data" "$WORK_DIR/data.sql" --data-only

log "Creating archive"
tar -czf "$ARCHIVE_PATH" -C "$LOCAL_BACKUP_ROOT/work" "$STAMP"
shasum -a 256 "$ARCHIVE_PATH" >"$SHA_PATH"

log "Archive size: $(du -h "$ARCHIVE_PATH" | awk '{print $1}')"
log "Uploading daily backup to Google Drive"
rclone mkdir "$GDRIVE_REMOTE/daily" >>"$LOG_PATH" 2>&1 || true
rclone copyto "$ARCHIVE_PATH" "$GDRIVE_REMOTE/daily/$ARCHIVE_NAME" --checksum >>"$LOG_PATH" 2>&1
rclone copyto "$SHA_PATH" "$GDRIVE_REMOTE/daily/$ARCHIVE_NAME.sha256" --checksum >>"$LOG_PATH" 2>&1

if [ "$DAY" = "01" ] || [ "${CRM_BACKUP_FORCE_MONTHLY:-0}" = "1" ]; then
  log "Uploading monthly permanent backup to Google Drive"
  rclone mkdir "$GDRIVE_REMOTE/monthly/$MONTH" >>"$LOG_PATH" 2>&1 || true
  rclone copyto "$ARCHIVE_PATH" "$GDRIVE_REMOTE/monthly/$MONTH/$ARCHIVE_NAME" --checksum >>"$LOG_PATH" 2>&1
  rclone copyto "$SHA_PATH" "$GDRIVE_REMOTE/monthly/$MONTH/$ARCHIVE_NAME.sha256" --checksum >>"$LOG_PATH" 2>&1
fi

if [ "$KEEP_DAILY_DAYS" -gt 0 ]; then
  log "Applying daily retention: ${KEEP_DAILY_DAYS} days"
  rclone delete "$GDRIVE_REMOTE/daily" \
    --min-age "${KEEP_DAILY_DAYS}d" \
    --include "*.tar.gz" \
    --include "*.tar.gz.sha256" \
    --exclude "*" >>"$LOG_PATH" 2>&1 || true
fi

log "Cleaning local work directory"
rm -rf "$WORK_DIR"

log "Backup complete: $ARCHIVE_NAME"
printf '%s\n' "$ARCHIVE_PATH"
