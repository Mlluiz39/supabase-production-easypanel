#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# restore.sh — PostgreSQL restore for Supabase Production
#
# Restores a pg_dump custom-format backup (optionally gzipped).
# Shows what will be restored and asks for confirmation.
#
# Usage:
#   ./scripts/restore.sh backups/supabase_2026-06-29_030000.dump.gz
#   ./scripts/restore.sh --dry-run backups/supabase_2026-06-29_030000.dump
#   ./scripts/restore.sh --force backups/supabase_2026-06-29_030000.dump.gz
#   ./scripts/restore.sh --help
#
# IMPORTANT: This overwrites data. Always backup before restoring.
# ─────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"

# ─── Defaults ───────────────────────────────────────────────
FORCE=false
DRY_RUN=false
DB_CONTAINER="supabase-db"
PG_USER="supabase_admin"
PG_HOST="localhost"
PG_PORT="5432"
USE_GZIP=false

# ─── Helpers ────────────────────────────────────────────────
timestamp() { date '+%Y-%m-%d %H:%M:%S'; }
log()    { echo "[$(timestamp)] $*"; }
log_ok() { echo "[$(timestamp)] ✅ $*"; }
log_warn(){ echo "[$(timestamp)] ⚠️  $*"; }
log_err() { echo "[$(timestamp)] ❌ $*" >&2; }

usage() {
  cat <<EOF
Usage: restore.sh [OPTIONS] <backup-file>

Restore a Supabase PostgreSQL database from a pg_dump backup.

Arguments:
  <backup-file>  Path to .dump or .dump.gz backup file

Options:
  --dry-run      List contents without restoring
  --force        Skip confirmation prompt (for scripts/automation)
  --help         Show this help message

Examples:
  restore.sh backups/supabase_2026-06-29_030000.dump.gz
  restore.sh --dry-run backups/supabase_2026-06-29_030000.dump
  restore.sh --force backups/supabase_2026-06-29_030000.dump.gz
EOF
}

# ─── Parse arguments ────────────────────────────────────────
BACKUP_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)  DRY_RUN=true; shift ;;
    --force)    FORCE=true; shift ;;
    --help)     usage; exit 0 ;;
    --*)        echo "Unknown option: $1"; usage; exit 1 ;;
    *)          BACKUP_FILE="$1"; shift ;;
  esac
done

# ─── Read backup file (handles gzip transparently) ──────────
# Outputs decompressed dump data to stdout
cat_backup() {
  if $USE_GZIP; then
    gunzip --stdout "$BACKUP_FILE"
  else
    cat "$BACKUP_FILE"
  fi
}

# ─── Run pg_restore in container reading from stdin ─────────
pg_restore_list() {
  cat_backup | docker exec -i -e PGPASSWORD="$PG_PASSWORD" "$DB_CONTAINER" \
    pg_restore --list 2>&1
}

pg_restore_data() {
  cat_backup | docker exec -i -e PGPASSWORD="$PG_PASSWORD" "$DB_CONTAINER" \
    pg_restore \
      --host="$PG_HOST" \
      --port="$PG_PORT" \
      --username="$PG_USER" \
      --dbname="$PG_DB" \
      --clean \
      --if-exists \
      --no-owner \
      --no-acl \
      --verbose \
      --single-transaction \
      2>&1
}

# ─── Validate backup file ───────────────────────────────────
validate_file() {
  if [[ -z "$BACKUP_FILE" ]]; then
    log_err "No backup file specified."
    usage
    exit 1
  fi

  if [[ ! -f "$BACKUP_FILE" ]]; then
    log_err "Backup file not found: $BACKUP_FILE"
    exit 1
  fi

  if [[ ! -s "$BACKUP_FILE" ]]; then
    log_err "Backup file is empty: $BACKUP_FILE"
    exit 1
  fi

  # Determine if gzipped by magic bytes
  local magic
  magic=$(xxd -l 2 -p "$BACKUP_FILE" 2>/dev/null || od -A n -t x1 -N 2 "$BACKUP_FILE" | tr -d ' ')

  if [[ "$magic" == "1f8b" ]]; then
    log "Backup format: gzip-compressed custom dump"
    USE_GZIP=true
  elif [[ "$magic" == "5047" ]]; then
    log "Backup format: pg_dump custom format (PGDMP magic)"
    USE_GZIP=false
  else
    log_warn "Unexpected file header (magic: $magic). Attempting as raw custom dump."
    USE_GZIP=false
  fi
}

# ─── Load env ───────────────────────────────────────────────
load_env() {
  if [[ ! -f "$ENV_FILE" ]]; then
    log_err ".env not found at $ENV_FILE"
    exit 1
  fi

  PG_PASSWORD=$(grep '^POSTGRES_PASSWORD=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- || echo "")
  PG_DB=$(grep '^POSTGRES_DB=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- || echo "postgres")

  if [[ -z "$PG_PASSWORD" ]]; then
    log_err "POSTGRES_PASSWORD not found in .env"
    exit 1
  fi
}

# ─── Check container running ────────────────────────────────
check_container() {
  local state
  state=$(docker inspect --format='{{.State.Status}}' "$DB_CONTAINER" 2>/dev/null || echo "missing")
  if [[ "$state" != "running" ]]; then
    log_err "Database container '$DB_CONTAINER' is not running (state: $state)"
    echo "  Start the environment: docker compose up -d"
    exit 1
  fi
}

# ─── List dump contents ─────────────────────────────────────
list_contents() {
  log "Reading backup contents..."
  echo ""

  local list_output list_exit
  list_output=$(pg_restore_list 2>&1)
  list_exit=$?

  if [[ $list_exit -ne 0 ]]; then
    log_err "Failed to read backup file (exit code: $list_exit)"
    echo "$list_output" | tail -5
    exit 1
  fi

  echo "$list_output"

  # Show object summary
  echo ""
  log "Object summary:"
  echo "$list_output" | awk '{
    for(i=1;i<=NF;i++) {
      if ($i ~ /^[0-9]+;/ || $i ~ /^[0-9]+$/) continue
      type=$i
      break
    }
    if (type == "") type = "OTHER"
    counts[type]++
  } END {
    for (t in counts) printf "    %-25s %d\n", t, counts[t]
  }' | sort -t: -k2 -rn
  echo ""
}

# ─── Check version compatibility ────────────────────────────
check_version() {
  local db_version dump_version
  db_version=$(docker exec -e PGPASSWORD="$PG_PASSWORD" "$DB_CONTAINER" \
    psql --host="$PG_HOST" --port="$PG_PORT" --username="$PG_USER" --dbname="$PG_DB" \
    -t -c "SELECT current_setting('server_version_num')::int / 10000;" 2>/dev/null | grep -oP '[0-9]+' || echo "unknown")

  dump_version=$(pg_restore_list 2>/dev/null | grep -oP 'Dumped from database version: \K[0-9]+' || echo "unknown")

  log "PG major version: server=$db_version, dump=$dump_version"

  if [[ "$db_version" != "$dump_version" && "$dump_version" != "unknown" && "$db_version" != "unknown" ]]; then
    log_warn "Major version mismatch! Restore will likely fail."
  fi
}

# ─── Confirm with user ──────────────────────────────────────
confirm_restore() {
  if $FORCE; then
    log "Confirmation skipped (--force)"
    return 0
  fi

  if $DRY_RUN; then
    return 0
  fi

  echo ""
  log_warn "⚠️  WARNING: This will OVERWRITE existing database data!"
  echo ""
  echo "  Database: $PG_DB"
  echo "  Container: $DB_CONTAINER"
  echo "  From: $BACKUP_FILE"
  echo ""

  read -rp "  Type 'YES' to proceed, anything else to abort: " answer
  if [[ "$answer" != "YES" ]]; then
    echo ""
    log "Restore aborted by user."
    exit 0
  fi
  echo ""
  log "Proceeding with restore..."
}

# ─── Run restore ────────────────────────────────────────────
run_restore() {
  local start_time
  start_time=$(date +%s)

  log "Restoring database..."

  # Kill active connections before restore (needed for --clean)
  log "  Terminating active connections..."
  docker exec -e PGPASSWORD="$PG_PASSWORD" "$DB_CONTAINER" \
    psql --host="$PG_HOST" --port="$PG_PORT" --username="$PG_USER" --dbname="$PG_DB" \
    -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE pid <> pg_backend_pid() AND datname = '$PG_DB';" \
    > /dev/null 2>&1 || true

  local restore_output restore_exit
  restore_output=$(pg_restore_data 2>&1)
  restore_exit=$?

  if [[ $restore_exit -eq 0 ]]; then
    local total_time=$(($(date +%s) - start_time))
    log_ok "Restore complete (${total_time}s)"
  else
    local total_time=$(($(date +%s) - start_time))
    log_err "pg_restore failed after ${total_time}s (exit code: $restore_exit)"
    echo "$restore_output" | tail -20
    cat <<EOF

  ⚠️  Restore may be incomplete. Common causes:
    1. Schema conflicts — try dropping conflicting objects first
    2. Extension versions differ — pg_dump includes extension SQL
    3. Insufficient disk space — check: df -h volumes/db/

  Consider restoring from a fresh state:
    docker compose down -v db  # WARNING: destroys data
    docker compose up -d
EOF
    exit $restore_exit
  fi
}

# ─── Notify PostgREST ───────────────────────────────────────
notify_postgrest() {
  log "Notifying PostgREST to reload schema..."
  if docker exec -e PGPASSWORD="$PG_PASSWORD" "$DB_CONTAINER" \
    psql --host="$PG_HOST" --port="$PG_PORT" --username="$PG_USER" --dbname="$PG_DB" \
    -c "NOTIFY pgrst, 'reload schema';" > /dev/null 2>&1; then
    log_ok "PostgREST schema reload triggered"
  else
    log_warn "Could not notify PostgREST (it will auto-reload on next request)"
  fi
}

# ─── Main ───────────────────────────────────────────────────
main() {
  echo ""
  log "═══════════════════════════════════════════════════"
  log "  Supabase Production — Database Restore"
  log "═══════════════════════════════════════════════════"
  echo ""

  # 1. Validate input
  validate_file

  # 2. Load config
  load_env

  # 3. Check container
  check_container

  # 4. Check version
  check_version

  # 5. List contents
  list_contents

  # 6. If dry-run, stop here
  if $DRY_RUN; then
    log_ok "Dry-run complete. No data was modified."
    exit 0
  fi

  # 7. Confirm
  confirm_restore

  # 8. Restore
  run_restore

  # 9. Notify PostgREST
  notify_postgrest

  echo ""
  log "═══════════════════════════════════════════════════"
  log_ok "  Restore successful!"
  log "  Database: $PG_DB"
  log "  Source: $BACKUP_FILE"
  log "═══════════════════════════════════════════════════"
  echo ""
}

main
