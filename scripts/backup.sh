#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# backup.sh — PostgreSQL backup for Supabase Production
#
# Performs pg_dump in custom format, compresses with gzip,
# verifies integrity, and rotates old backups.
#
# Usage:
#   ./scripts/backup.sh                         # default settings
#   ./scripts/backup.sh --output-dir /mnt/bk    # custom destination
#   ./scripts/backup.sh --retain-days 14         # keep 14 days
#   ./scripts/backup.sh --help                   # show options
#
# Cron (daily at 3:00 AM):
#   0 3 * * * cd /path/to/project && ./scripts/backup.sh >> backups/backup.log 2>&1
# ─────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"

# ─── Defaults ───────────────────────────────────────────────
OUTPUT_DIR="$PROJECT_DIR/backups"
RETAIN_DAYS=7
DB_CONTAINER="supabase-db"
PG_USER="supabase_admin"
PG_HOST="localhost"
PG_PORT="5432"

# ─── Helpers ────────────────────────────────────────────────
timestamp() { date '+%Y-%m-%d %H:%M:%S'; }
log()    { echo "[$(timestamp)] $*" >&2; }
log_ok() { echo "[$(timestamp)] ✅ $*" >&2; }
log_err(){ echo "[$(timestamp)] ❌ $*" >&2; }

usage() {
  cat <<EOF
Usage: backup.sh [OPTIONS]

Create a compressed pg_dump backup of the Supabase PostgreSQL database.

Options:
  --output-dir <path>   Destination directory (default: ./backups)
  --retain-days <N>     Days to keep backups (default: 7)
  --help                Show this help message

Output: supabase_YYYY-MM-DD_HHMMSS.dump.gz
EOF
}

# ─── Parse arguments ────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)  OUTPUT_DIR="$2"; shift 2 ;;
    --retain-days) RETAIN_DAYS="$2"; shift 2 ;;
    --help)        usage; exit 0 ;;
    *)             echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# ─── Load env ───────────────────────────────────────────────
load_env() {
  if [[ ! -f "$ENV_FILE" ]]; then
    log_err ".env not found at $ENV_FILE"
    echo "  Run ./scripts/generate-secrets.sh first, or create .env manually."
    exit 1
  fi

  # Extract only the vars we need (safe: no spaces in these values)
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

# ─── Ensure output directory ────────────────────────────────
ensure_dir() {
  if [[ ! -d "$OUTPUT_DIR" ]]; then
    mkdir -p "$OUTPUT_DIR"
    log "Created output directory: $OUTPUT_DIR"
  fi
}

# ─── Run backup ─────────────────────────────────────────────
run_backup() {
  local timestamp_str
  timestamp_str=$(date '+%Y-%m-%d_%H%M%S')
  local filename="supabase_${timestamp_str}.dump"
  local filepath="$OUTPUT_DIR/$filename"
  local filepath_gz="${filepath}.gz"

  log "Starting backup → $filename"

  # pg_dump via docker exec (custom format, compressed)
  # Custom format enables selective restore with pg_restore --list/--use-list
  local start_time
  start_time=$(date +%s)

  if docker exec -e PGPASSWORD="$PG_PASSWORD" "$DB_CONTAINER" \
    pg_dump \
      --host="$PG_HOST" \
      --port="$PG_PORT" \
      --username="$PG_USER" \
      --dbname="$PG_DB" \
      --format=custom \
      --compress=0 \
      --no-owner \
      --no-acl \
    > "$filepath"; then
    local dump_time=$(($(date +%s) - start_time))
    local dump_size
    dump_size=$(stat --format=%s "$filepath" 2>/dev/null || stat -f%z "$filepath" 2>/dev/null || echo "unknown")
    log_ok "pg_dump complete (${dump_time}s, ${dump_size} bytes raw)"
  else
    log_err "pg_dump failed"
    rm -f "$filepath"
    exit 1
  fi

  # ─── Verify integrity ─────────────────────────────────
  log "Verifying backup integrity..."
  if cat "$filepath" | docker exec -i -e PGPASSWORD="$PG_PASSWORD" "$DB_CONTAINER" \
    pg_restore --list > /dev/null 2>&1; then
    log_ok "Backup integrity verified"
  else
    log_err "Backup integrity check failed (pg_restore could not read dump)"
    rm -f "$filepath"
    exit 1
  fi

  # ─── Compress ─────────────────────────────────────────
  log "Compressing with gzip --best..."
  local gz_start
  gz_start=$(date +%s)
  if gzip --best --force "$filepath"; then
    local gz_time=$(($(date +%s) - gz_start))
    local gz_size
    gz_size=$(stat --format=%s "$filepath_gz" 2>/dev/null || stat -f%z "$filepath_gz" 2>/dev/null || echo "unknown")
    log_ok "Compressed (${gz_time}s, ${gz_size} bytes)"
  else
    log_err "gzip compression failed"
    rm -f "$filepath" "$filepath_gz"
    exit 1
  fi

  # ─── Verify compressed file is non-empty ──────────────
  if [[ ! -s "$filepath_gz" ]]; then
    log_err "Compressed backup is empty"
    rm -f "$filepath_gz"
    exit 1
  fi

  local total_time=$(($(date +%s) - start_time))
  log_ok "Backup complete: $filepath_gz (total: ${total_time}s)"
  echo "$filepath_gz"
}

# ─── Rotate old backups ─────────────────────────────────────
rotate_backups() {
  log "Rotating backups older than ${RETAIN_DAYS} days..."

  local deleted=0
  while IFS= read -r -d '' old_file; do
    log "  Removing: $(basename "$old_file")"
    rm -f "$old_file"
    deleted=$((deleted + 1))
  done < <(find "$OUTPUT_DIR" -name 'supabase_*.dump.gz' -mtime "+${RETAIN_DAYS}" -print0 2>/dev/null || true)

  if [[ $deleted -gt 0 ]]; then
    log_ok "Removed $deleted old backup(s)"
  else
    log "  No old backups to remove"
  fi
}

# ─── Show current storage usage ─────────────────────────────
show_storage() {
  local count size
  count=$(find "$OUTPUT_DIR" -name 'supabase_*.dump.gz' -type f 2>/dev/null | wc -l)
  size=$(du -sh "$OUTPUT_DIR" 2>/dev/null | cut -f1 || echo "unknown")
  log "Storage: $count backup(s) using $size in $OUTPUT_DIR"
}

# ─── Main ───────────────────────────────────────────────────
main() {
  echo ""
  log "═══════════════════════════════════════════════════"
  log "  Supabase Production — Database Backup"
  log "═══════════════════════════════════════════════════"
  echo ""

  load_env
  check_container
  ensure_dir

  local backup_file
  backup_file=$(run_backup)

  rotate_backups
  show_storage

  echo ""
  log "Backup saved: $backup_file"
  log "To restore: ./scripts/restore.sh $backup_file"
}

main
