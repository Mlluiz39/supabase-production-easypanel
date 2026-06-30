#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# install.sh — Bootstrap script for Supabase Production
#
# Performs a full deployment in one command:
#   1. Verify prerequisites
#   2. Generate secrets (if needed)
#   3. Validate compose config
#   4. Start all services
#   5. Wait for healthy state
#   6. Print connection summary
#
# Usage:
#   ./scripts/install.sh                     # full bootstrap
#   ./scripts/install.sh --skip-healthcheck   # skip health wait
#   ./scripts/install.sh --no-cloudflare      # skip tunnel
#   ./scripts/install.sh --backup-dir /mnt/bk # custom backup path
#   ./scripts/install.sh --help               # show options
# ─────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"

# ─── Defaults ───────────────────────────────────────────────
SKIP_HEALTHCHECK=false
NO_CLOUDFLARE=false
HEALTHCHECK_TIMEOUT=300  # 5 minutes
BACKUP_DIR="$PROJECT_DIR/backups"

# Core services that must be healthy (cloudflared is optional)
CORE_SERVICES=(
  "supabase-db"
  "supabase-supavisor"
  "supabase-auth"
  "supabase-rest"
  "supabase-realtime"
  "supabase-storage"
  "supabase-imgproxy"
  "supabase-meta"
  "supabase-functions"
  "supabase-kong"
  "supabase-studio"
  "supabase-vector"
)

# ─── Helpers ────────────────────────────────────────────────
timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

log()    { echo "[$(timestamp)] $*"; }
log_ok() { echo "[$(timestamp)] ✅ $*"; }
log_warn(){ echo "[$(timestamp)] ⚠️  $*"; }
log_err() { echo "[$(timestamp)] ❌ $*" >&2; }

usage() {
  cat <<EOF
Usage: install.sh [OPTIONS]

Bootstrap the Supabase production environment.

Options:
  --skip-healthcheck   Skip waiting for services to become healthy
  --no-cloudflare      Skip the Cloudflare Tunnel service
  --monitoring         Include Prometheus + Grafana + Admin Panel
  --backup-dir <path>  Set custom backup directory (default: ./backups)
  --help               Show this help message

After install:
  Studio:  https://studio.mlluizdevtech.com.br
  API:     https://supabase.mlluizdevtech.com.br
EOF
}

# ─── Parse arguments ────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-healthcheck) SKIP_HEALTHCHECK=true; shift ;;
    --no-cloudflare)    NO_CLOUDFLARE=true; shift ;;
    --monitoring)       include_monitoring=true; shift ;;
    --backup-dir)       BACKUP_DIR="$2"; shift 2 ;;
    --help)             usage; exit 0 ;;
    *)                  echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# ─── Prerequisite checks ────────────────────────────────────
check_prerequisites() {
  log "Checking prerequisites..."

  local missing=()
  for cmd in docker openssl jq curl; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done

  # Docker Compose (plugin or standalone)
  local compose_ok=false
  if docker compose version &>/dev/null; then
    compose_ok=true
  elif command -v docker-compose &>/dev/null; then
    compose_ok=true
  fi

  if ! $compose_ok; then
    missing+=("docker-compose")
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    log_err "Missing prerequisites: ${missing[*]}"
    echo ""
    echo "  Install instructions:"
    for m in "${missing[@]}"; do
      case "$m" in
        docker)          echo "    docker:        https://docs.docker.com/engine/install/" ;;
        docker-compose)  echo "    docker-compose: docker compose plugin (included in Docker Desktop)" ;;
        openssl)         echo "    openssl:       apt-get install openssl" ;;
        jq)              echo "    jq:            apt-get install jq" ;;
        curl)            echo "    curl:          apt-get install curl" ;;
      esac
    done
    exit 1
  fi

  # Docker daemon running?
  if ! docker info &>/dev/null; then
    log_err "Docker daemon is not running."
    echo "  Start it with: sudo systemctl start docker"
    exit 1
  fi

  log_ok "All prerequisites satisfied"
}

# ─── .env handling ──────────────────────────────────────────
handle_env() {
  local secret_generator="$SCRIPT_DIR/generate-secrets.sh"

  if [[ ! -f "$secret_generator" ]]; then
    log_err "generate-secrets.sh not found at $secret_generator"
    exit 1
  fi

  if [[ ! -f "$ENV_FILE" ]]; then
    log ".env not found — generating secrets automatically..."
    bash "$secret_generator" --force
    log_ok "Secrets generated"
    return
  fi

  # Check for dummy/placeholder secrets
  local dummy_patterns=(
    "your-super-secret-and-long-postgres-password"
    "your-super-secret-jwt-token-with-at-least-32-characters-long"
    "your-32-character-encryption-key"
    "your-encryption-key-32-chars-min"
    "changeme"
    "UpNVntn3cDxHJpq99YMc1T1AQgQpc8kfYTuRgBiYa15BLrx8etQoXz3gZv1/u2oq"
  )

  local has_dummy=false
  while IFS= read -r line; do
    for pattern in "${dummy_patterns[@]}"; do
      if [[ "$line" == *"$pattern"* ]]; then
        has_dummy=true
        log_warn "Found default/placeholder secret: ${line%%=*}"
        break
      fi
    done
  done < "$ENV_FILE"

  if $has_dummy; then
    echo ""
    log_warn "Your .env contains placeholder secrets from .env.example."
    echo "  These are NOT secure for production use."
    echo ""
    read -rp "  Regenerate secrets now? [Y/n] " answer
    if [[ -z "$answer" || "$answer" =~ ^[Yy]$ ]]; then
      bash "$secret_generator" --force
      log_ok "Secrets regenerated"
    else
      log_warn "Proceeding with existing .env (insecure secrets)"
    fi
  else
    log_ok "Existing .env looks valid (no placeholder secrets detected)"
  fi
}

# ─── Validate compose ───────────────────────────────────────
validate_compose() {
  log "Validating docker compose configuration..."

  if ! docker compose --env-file "$ENV_FILE" config --quiet 2>&1; then
    log_err "docker compose config validation failed."
    echo ""
    echo "  Debug: docker compose --env-file $ENV_FILE config"
    exit 1
  fi

  log_ok "Compose configuration valid"
}

# ─── Wait for services ──────────────────────────────────────
wait_for_healthy() {
  log "Waiting for services to become healthy (timeout: ${HEALTHCHECK_TIMEOUT}s)..."

  local start_time
  start_time=$(date +%s)
  local all_healthy=false

  while true; do
    local elapsed=$(($(date +%s) - start_time))
    if [[ $elapsed -ge $HEALTHCHECK_TIMEOUT ]]; then
      break
    fi

    local healthy_count=0
    local total=${#CORE_SERVICES[@]}
    local failing_services=()

    for container in "${CORE_SERVICES[@]}"; do
      local status
      status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "missing")
      if [[ "$status" == "healthy" ]]; then
        ((healthy_count++))
      else
        failing_services+=("$container ($status)")
      fi
    done

    if [[ $healthy_count -eq $total ]]; then
      all_healthy=true
      break
    fi

    # Show progress every 15 seconds
    if (( elapsed % 15 == 0 )); then
      log "  ${healthy_count}/${total} healthy (${elapsed}s elapsed)"
      for fs in "${failing_services[@]:0:3}"; do
        log "    waiting: $fs"
      done
      if [[ ${#failing_services[@]} -gt 3 ]]; then
        log "    ... and $((${#failing_services[@]} - 3)) more"
      fi
    fi

    sleep 5
  done

  if $all_healthy; then
    local total_time=$(($(date +%s) - start_time))
    log_ok "All ${#CORE_SERVICES[@]} services healthy (${total_time}s)"
    return 0
  fi

  # Timeout reached — show what's failing
  log_err "Healthcheck timeout after ${HEALTHCHECK_TIMEOUT}s"
  echo ""
  echo "  Services not healthy:"
  for container in "${CORE_SERVICES[@]}"; do
    local status
    status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "missing")
    if [[ "$status" != "healthy" ]]; then
      echo "    $container → $status"
      # Show last log lines for failing service
      docker logs --tail 5 "$container" 2>/dev/null | sed 's/^/      /' || true
    fi
  done
  echo ""
  log_err "Troubleshooting:"
  echo "  docker compose ps"
  echo "  docker compose logs <service>"
  echo "  docker compose restart"
  exit 1
}

# ─── Start services ─────────────────────────────────────────
start_services() {
  local extra_profiles="${1:-}"
  # Determine compose profile
  local profile_args=()
  local use_cloudflare=false

  if $NO_CLOUDFLARE; then
    log "Cloudflare Tunnel: disabled (--no-cloudflare flag)"
  else
    # Check if token is set
    local token
    token=$(grep '^CLOUDFLARE_TUNNEL_TOKEN=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- || echo "")
    if [[ -n "$token" && "$token" != '""' ]]; then
      profile_args=(--profile cloudflare)
      use_cloudflare=true
      log "Cloudflare Tunnel: enabled (token found)"
    else
      log_warn "CLOUDFLARE_TUNNEL_TOKEN not set — Cloudflare Tunnel will NOT start"
      log_warn "Without the tunnel, the environment has no external access."
      echo ""
      echo "  To enable external access:"
      echo "  1. Go to https://one.dash.cloudflare.com/"
      echo "  2. Access → Tunnels → Create a tunnel"
      echo "  3. Choose 'Docker' as the environment"
      echo "  4. Copy the token and set it in .env:"
      echo "     CLOUDFLARE_TUNNEL_TOKEN=<your-token>"
      echo "  5. Re-run: docker compose --profile cloudflare up -d cloudflared"
      echo ""
    fi
  fi

  # Include extra profiles (e.g., monitoring, admin)
  if [[ -n "$extra_profiles" ]]; then
    profile_args+=($extra_profiles)
  fi

  # Pull images first (helps detect registry issues early)
  log "Pulling Docker images..."
  docker compose --env-file "$ENV_FILE" "${profile_args[@]}" pull --quiet 2>&1 | while IFS= read -r line; do
    # Summarize: only show errors
    if [[ "$line" == *"error"* || "$line" == *"Error"* || "$line" == *"failed"* ]]; then
      log_err "$line"
    fi
  done

  local pull_exit=${PIPESTATUS[0]}
  if [[ $pull_exit -ne 0 ]]; then
    log_err "Failed to pull one or more images. Check your internet connection."
    exit $pull_exit
  fi
  log_ok "Images pulled"

  # Start services
  log "Starting Supabase services..."
  docker compose --env-file "$ENV_FILE" "${profile_args[@]}" up -d 2>&1 | while IFS= read -r line; do
    if [[ "$line" == *"error"* || "$line" == *"Error"* ]]; then
      log_err "$line"
    else
      log "  $line"
    fi
  done

  local up_exit=${PIPESTATUS[0]}
  if [[ $up_exit -ne 0 ]]; then
    log_err "docker compose up failed (exit code: $up_exit)"
    echo ""
    echo "  Common issues:"
    echo "  1. Port conflict — check: sudo ss -tlnp | grep -E '5432|8000|3000'"
    echo "  2. Volume permission — check: ls -la volumes/"
    echo "  3. Out of disk space — check: df -h ."
    exit $up_exit
  fi
  log_ok "Services started"

  # Return cloudflare status for summary
  echo "$use_cloudflare"
}

# ─── Print summary ──────────────────────────────────────────
print_summary() {
  local use_cloudflare="$1"

  # Read URLs and keys from .env
  local studio_url api_url anon_key
  studio_url=$(grep '^STUDIO_URL=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- || echo "http://localhost:3000")
  api_url=$(grep '^SUPABASE_PUBLIC_URL=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- || echo "http://localhost:8000")
  anon_key=$(grep '^ANON_KEY=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- || echo "N/A")
  postgres_pass=$(grep '^POSTGRES_PASSWORD=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- || echo "N/A")

  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  ✅ Supabase is running!"
  echo ""
  echo "     Studio:  $studio_url"
  echo "     API:     $api_url"
  echo "     Anon Key: $anon_key"
  echo ""

  if ! $use_cloudflare; then
    echo "  ⚠️  Cloudflare Tunnel is NOT active."
    echo "     The URLs above are for reference only."
    echo "     Access is internal-only (localhost/Docker network)."
    echo "     To enable external access, set CLOUDFLARE_TUNNEL_TOKEN"
    echo "     and re-run: docker compose --profile cloudflare up -d"
    echo ""
  fi

  echo "  Local admin access:"
  echo "     PostgreSQL:  psql postgres://postgres:$postgres_pass@localhost:5432/postgres"
  echo "     Kong Admin:  http://localhost:8001"
  echo ""
  echo "  Manage:"
  echo "     docker compose ps"
  echo "     docker compose logs -f <service>"
  echo "     docker compose restart"
  echo ""
  echo "  Backup:"
  echo "     ./scripts/backup.sh"
  echo "═══════════════════════════════════════════════════════"
}

# ─── Create backup dir ──────────────────────────────────────
ensure_backup_dir() {
  if [[ ! -d "$BACKUP_DIR" ]]; then
    mkdir -p "$BACKUP_DIR"
    log "Backup directory created: $BACKUP_DIR"
  fi
}

# ─── Main ───────────────────────────────────────────────────
# ─── Generate kong.yml from template ──────────────────────────
generate_kong_yml() {
  local template="$PROJECT_DIR/kong/kong.template.yml"
  local kong_file="$PROJECT_DIR/kong/kong.yml"

  if [[ ! -f "$template" ]]; then
    log_warn "kong/kong.template.yml not found — skipping Kong config generation"
    return
  fi

  local anon_key service_role_key
  anon_key=$(grep '^ANON_KEY=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- || echo "")
  service_role_key=$(grep '^SERVICE_ROLE_KEY=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- || echo "")

  if [[ -z "$anon_key" ]]; then
    log_warn "ANON_KEY not found in .env — skipping Kong config generation"
    return
  fi

  cp "$template" "$kong_file"
  sed -i "s|__ANON_KEY__|${anon_key}|g" "$kong_file"
  sed -i "s|__SERVICE_ROLE_KEY__|${service_role_key}|g" "$kong_file"
  log_ok "Kong config generated: $kong_file"
}

main() {
  echo ""
  log "═══════════════════════════════════════════════════"
  log "  Supabase Production — Bootstrap Installer"
  log "═══════════════════════════════════════════════════"
  echo ""

  # 1. Check prerequisites
  check_prerequisites

  # 2. Handle .env / secrets
  handle_env

  # 3. Generate kong.yml from template
  generate_kong_yml

  # 4. Ensure backup directory
  ensure_backup_dir

  # 5. Validate compose config
  validate_compose

  # 5. Start services
  local use_cloudflare
  local extra_profiles=""
  if [[ "${include_monitoring:-false}" == "true" ]]; then
    extra_profiles="--profile monitoring --profile admin"
    log "Monitoring stack: enabled (Prometheus + Grafana + Admin Panel)"
  fi
  use_cloudflare=$(start_services "$extra_profiles")

  # 6. Wait for healthchecks (unless skipped)
  if $SKIP_HEALTHCHECK; then
    log "Healthcheck skipped (--skip-healthcheck)"
  else
    wait_for_healthy
  fi

  # 7. Print summary
  print_summary "$use_cloudflare"
}

main
