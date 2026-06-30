#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# update.sh — Atualização segura do Supabase com rollback
#
# Fluxo: backup → pull → restart → healthcheck → (sucesso | rollback)
#
# Usage:
#   ./scripts/update.sh                        # update completo
#   ./scripts/update.sh --skip-backup           # sem backup prévio
#   ./scripts/update.sh --dry-run               # só mostrar mudanças
#   ./scripts/update.sh --rollback-only <tag>   # rollback para versão específica
#   ./scripts/update.sh --help
# ─────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"

# ─── Defaults ───────────────────────────────────────────────
SKIP_BACKUP=false
DRY_RUN=false
ROLLBACK_TAG=""
HEALTHCHECK_TIMEOUT=300
BACKUP_DIR="$PROJECT_DIR/backups"

CORE_SERVICES=(
  "supabase-db" "supabase-supavisor" "supabase-auth" "supabase-rest"
  "supabase-realtime" "supabase-storage" "supabase-imgproxy" "supabase-meta"
  "supabase-functions" "supabase-kong" "supabase-studio" "supabase-vector"
)

# ─── Helpers ────────────────────────────────────────────────
timestamp() { date '+%Y-%m-%d %H:%M:%S'; }
log()    { echo "[$(timestamp)] $*"; }
log_ok() { echo "[$(timestamp)] ✅ $*"; }
log_warn(){ echo "[$(timestamp)] ⚠️  $*"; }
log_err() { echo "[$(timestamp)] ❌ $*" >&2; }

usage() {
  cat <<EOF
Usage: update.sh [OPTIONS]

Atualizar o Supabase com rollback automático em caso de falha.

Options:
  --skip-backup      Pular backup automático antes do update
  --dry-run          Mostrar diferenças sem alterar nada
  --rollback-only <t> Restaurar versão específica (git tag)
  --help             Exibir ajuda

Fluxo: backup → pull → restart → healthcheck → sucesso
                       ↓ falha →
                  rollback automático
EOF
}

# ─── Parse args ─────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-backup)    SKIP_BACKUP=true; shift ;;
    --dry-run)        DRY_RUN=true; shift ;;
    --rollback-only)  ROLLBACK_TAG="$2"; shift 2 ;;
    --help)           usage; exit 0 ;;
    *)                echo "Opção desconhecida: $1"; usage; exit 1 ;;
  esac
done

# ─── Check prerequisites ────────────────────────────────────
check_prereqs() {
  for cmd in git docker; do
    if ! command -v "$cmd" &>/dev/null; then
      log_err "$cmd não encontrado"
      exit 1
    fi
  done

  if ! docker info &>/dev/null; then
    log_err "Docker daemon não está rodando"
    exit 1
  fi
}

# ─── Get current image digests ──────────────────────────────
get_image_digests() {
  local profile="${1:-}"
  # Extract image references from compose (with optional profile)
  if [[ -n "$profile" ]]; then
    docker compose --profile "$profile" config 2>/dev/null | grep 'image:' | awk '{print $2}' | sort
  else
    docker compose config 2>/dev/null | grep 'image:' | awk '{print $2}' | sort
  fi
}

# ─── Tag current deploy state ───────────────────────────────
tag_deploy() {
  local tag
  tag="deploy-$(date '+%Y-%m-%d-%H%M%S')"

  if ! git rev-parse --git-dir &>/dev/null; then
    log_warn "Não é um repositório git — pulando tagging"
    return 0
  fi

  if ! git diff --quiet; then
    log_warn "Há mudanças não commitadas — commitando antes de taggear..."
    git add -A
    git commit -m "auto: snapshot pre-update $(date '+%Y-%m-%d %H:%M:%S')" || true
  fi

  git tag -f "$tag" HEAD
  log_ok "Git tag criada: $tag"
  echo "$tag"
}

# ─── Rollback ───────────────────────────────────────────────
do_rollback() {
  local tag="${1:-}"
  if [[ -z "$tag" ]]; then
    tag=$(git tag -l 'deploy-*' | sort | tail -1)
  fi

  if [[ -z "$tag" ]]; then
    log_err "Nenhum deploy tag encontrado para rollback"
    exit 1
  fi

  log_warn "Iniciando rollback para: $tag"

  if ! git rev-parse --git-dir &>/dev/null; then
    log_err "Rollback requer git"
    exit 1
  fi

  git stash --include-untracked || true
  git checkout "$tag" -- docker-compose.yml .env.example 2>/dev/null || true

  log "Restartando containers da versão anterior..."
  docker compose up -d

  log "Aguardando healthchecks..."
  sleep 30
  docker compose ps

  log_ok "Rollback concluído para $tag"
  exit 0
}

# ─── Backup ─────────────────────────────────────────────────
do_backup() {
  if $SKIP_BACKUP; then
    log "Backup pulado (--skip-backup)"
    return
  fi
  if [[ -f "$SCRIPT_DIR/backup.sh" ]]; then
    bash "$SCRIPT_DIR/backup.sh" --output-dir "$BACKUP_DIR"
  else
    log_warn "backup.sh não encontrado — pulando backup"
  fi
}

# ─── Pull images ────────────────────────────────────────────
do_pull() {
  log "Puxando novas imagens..."

  if $DRY_RUN; then
    log "   [dry-run] docker compose pull"
    return
  fi

  if ! docker compose pull --quiet 2>&1; then
    log_err "Falha ao puxar imagens. Verifique conexão com internet."
    return 1
  fi

  log_ok "Imagens atualizadas"
}

# ─── Compare images ─────────────────────────────────────────
show_diff() {
  log "Imagens antes do update:"
  local before after
  before=$(get_image_digests)
  echo "$before"
  echo ""
  log "Puxando novas versões para comparação..."
  docker compose pull --quiet 2>/dev/null || true
  after=$(get_image_digests)

  log "Diferenças:"
  diff <(echo "$before") <(echo "$after") || true
}

# ─── Restart services ───────────────────────────────────────
do_restart() {
  if $DRY_RUN; then
    log "   [dry-run] docker compose up -d"
    return 0
  fi

  log "Reiniciando serviços..."
  if ! docker compose up -d 2>&1; then
    log_err "Falha ao reiniciar serviços"
    return 1
  fi
  log_ok "Serviços reiniciados"
}

# ─── Wait for healthchecks ──────────────────────────────────
wait_healthy() {
  if $DRY_RUN; then
    log "   [dry-run] Aguardar healthchecks..."
    return 0
  fi

  log "Aguardando serviços ficarem saudáveis (timeout: ${HEALTHCHECK_TIMEOUT}s)..."
  local start_time
  start_time=$(date +%s)

  while true; do
    local elapsed=$(($(date +%s) - start_time))
    if [[ $elapsed -ge $HEALTHCHECK_TIMEOUT ]]; then
      break
    fi

    local healthy=0
    local total=0
    local failing=()

    for container in "${CORE_SERVICES[@]}"; do
      local status
      status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "missing")
      if [[ "$status" == "healthy" ]]; then
        healthy=$((healthy + 1))
      else
        failing+=("$container ($status)")
      fi
      total=$((total + 1))
    done

    if [[ $healthy -eq $total ]]; then
      local total_time=$(($(date +%s) - start_time))
      log_ok "Todos os serviços saudáveis (${total_time}s)"
      return 0
    fi

    if (( elapsed % 15 == 0 )); then
      log "  ${healthy}/${total} saudáveis (${elapsed}s)"
    fi
    sleep 5
  done

  # Timeout
  log_err "Timeout! Serviços não saudáveis após ${HEALTHCHECK_TIMEOUT}s:"
  for container in "${CORE_SERVICES[@]}"; do
    local status
    status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "missing")
    if [[ "$status" != "healthy" ]]; then
      log_err "  $container → $status"
      docker logs --tail 3 "$container" 2>/dev/null || true
    fi
  done
  return 1
}

# ─── Main ───────────────────────────────────────────────────
main() {
  echo ""
  log "═══════════════════════════════════════════════════"
  log "  Supabase Production — Update Manager"
  log "═══════════════════════════════════════════════════"
  echo ""

  check_prereqs

  # ─── Modo rollback ────────────────────────────────────
  if [[ -n "$ROLLBACK_TAG" ]]; then
    do_rollback "$ROLLBACK_TAG"
    return
  fi

  # ─── Dry-run ──────────────────────────────────────────
  if $DRY_RUN; then
    show_diff
    return
  fi

  local deploy_tag
  deploy_tag=$(tag_deploy || echo "")

  # 1. Backup
  do_backup

  # 2. Pull images
  do_pull

  # 3. Restart
  do_restart

  # 4. Healthcheck
  if wait_healthy; then
    log_ok "Update concluído com sucesso!"
    log "Tag: $deploy_tag"
    exit 0
  fi

  # 5. Rollback on failure
  log_warn "Update falhou! Iniciando rollback..."
  if [[ -n "$deploy_tag" ]]; then
    do_rollback "$deploy_tag"
  else
    log_err "Rollback não disponível (sem git)"
    exit 1
  fi
}

main
