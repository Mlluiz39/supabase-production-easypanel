#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# generate-secrets.sh — Generate cryptographically secure
# secrets for Supabase Production deployment.
#
# Usage:
#   ./scripts/generate-secrets.sh            # interactive
#   ./scripts/generate-secrets.sh --force    # overwrite without asking
#   ./scripts/generate-secrets.sh --stdout   # print only, no file
# ─────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"
ENV_EXAMPLE="$PROJECT_DIR/.env.example"

FORCE=false
STDOUT_ONLY=false

usage() {
  cat <<EOF
Usage: generate-secrets.sh [OPTIONS]

Generate secure random secrets for Supabase deployment.

Options:
  --force    Overwrite existing .env without asking
  --stdout   Print generated .env to stdout (don't write file)
  --help     Show this help message

The script generates:
  - POSTGRES_PASSWORD       (64 hex chars)
  - JWT_SECRET              (64 hex chars)
  - SECRET_KEY_BASE         (128 hex chars)
  - VAULT_ENC_KEY           (32 hex chars)
  - PG_META_CRYPTO_KEY      (32 hex chars)
  - ANON_KEY                (HS256 JWT — role: anon)
  - SERVICE_ROLE_KEY        (HS256 JWT — role: service_role)
  - IMGPROXY_KEY            (64 hex chars)
  - IMGPROXY_SALT           (64 hex chars)

Prerequisites: openssl, jq, base64
EOF
}

# ─── Parse arguments ────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)  FORCE=true; shift ;;
    --stdout) STDOUT_ONLY=true; shift ;;
    --help)   usage; exit 0 ;;
    *)        echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# ─── Check prerequisites ────────────────────────────────────
check_deps() {
  local missing=()
  for cmd in openssl jq base64; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "❌ Missing dependencies: ${missing[*]}"
    echo "   Install with: apt-get install openssl jq coreutils"
    exit 1
  fi
}

# ─── base64url encode ───────────────────────────────────────
base64url() {
  echo -n "$1" | base64 | tr -d '\n' | tr '/+' '_-' | tr -d '='
}

# ─── Generate HS256 JWT ─────────────────────────────────────
# Args: $1 = role (anon | service_role), $2 = secret (hex string)
generate_jwt() {
  local role="$1"
  local secret="$2"
  local now
  now=$(date +%s)
  # 10-year expiry (Supabase convention for API keys)
  local exp=$((now + 315360000))

  # Header
  local header='{"alg":"HS256","typ":"JWT"}'
  local header_b64
  header_b64=$(base64url "$header")

  # Payload
  local payload
  payload=$(jq -nc \
    --arg role "$role" \
    --arg iss "supabase" \
    --argjson iat "$now" \
    --argjson exp "$exp" \
    '{role: $role, iss: $iss, iat: $iat, exp: $exp}')
  local payload_b64
  payload_b64=$(base64url "$payload")

  # Signing input
  local signing_input="${header_b64}.${payload_b64}"

  # HMAC-SHA256 signature (hex) → binary → base64url
  local sig_hex
  sig_hex=$(echo -n "$signing_input" | openssl dgst -sha256 -hmac "$secret" -hex | awk '{print $NF}')

  local sig_b64
  # Convert hex to binary using xxd or pure-shell fallback
  if command -v xxd &>/dev/null; then
    sig_b64=$(echo -n "$sig_hex" | xxd -r -p | base64 | tr -d '\n' | tr '/+' '_-' | tr -d '=')
  else
    # Pure-shell hex → binary → base64url
    local binary=""
    for ((i=0; i<${#sig_hex}; i+=2)); do
      binary+="\\x${sig_hex:$i:2}"
    done
    sig_b64=$(echo -ne "$binary" | base64 | tr -d '\n' | tr '/+' '_-' | tr -d '=')
  fi

  echo "${header_b64}.${payload_b64}.${sig_b64}"
}

# ─── Main ───────────────────────────────────────────────────
main() {
  check_deps

  # Check if .env.example exists
  if [[ ! -f "$ENV_EXAMPLE" ]]; then
    echo "❌ $ENV_EXAMPLE not found."
    echo "   Make sure you're running from the project root."
    exit 1
  fi

  # Check for existing .env (unless --force or --stdout)
  if [[ "$STDOUT_ONLY" != "true" && "$FORCE" != "true" && -f "$ENV_FILE" ]]; then
    echo "⚠️  $ENV_FILE already exists."
    echo ""
    read -rp "Overwrite? Secrets will be regenerated. [y/N] " answer
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
      echo "Aborted. Use --force to skip this prompt."
      exit 0
    fi
    # Backup existing
    cp "$ENV_FILE" "${ENV_FILE}.bak"
    echo "📦 Existing .env backed up to ${ENV_FILE}.bak"
  fi

  echo "🔐 Generating secrets..."

  # ─── Generate random secrets ──────────────────────────
  POSTGRES_PASSWORD=$(openssl rand -hex 32)
  JWT_SECRET=$(openssl rand -hex 32)
  SECRET_KEY_BASE=$(openssl rand -hex 64)
  VAULT_ENC_KEY=$(openssl rand -hex 16)
  PG_META_CRYPTO_KEY=$(openssl rand -hex 16)
  IMGPROXY_KEY=$(openssl rand -hex 32)
  IMGPROXY_SALT=$(openssl rand -hex 32)

  # ─── Generate JWT keys ────────────────────────────────
  echo "   Signing JWT tokens..."
  ANON_KEY=$(generate_jwt "anon" "$JWT_SECRET")
  SERVICE_ROLE_KEY=$(generate_jwt "service_role" "$JWT_SECRET")

  # ─── Verify JWT keys are valid ────────────────────────
  for key_name in ANON_KEY SERVICE_ROLE_KEY; do
    local jwt_val="${!key_name}"
    local parts
    IFS='.' read -ra parts <<< "$jwt_val"
    if [[ ${#parts[@]} -ne 3 ]]; then
      echo "❌ Failed to generate valid $key_name JWT"
      exit 1
    fi
  done

  echo "   ✅ POSTGRES_PASSWORD  ($(echo -n "$POSTGRES_PASSWORD" | wc -c) chars)"
  echo "   ✅ JWT_SECRET         ($(echo -n "$JWT_SECRET" | wc -c) chars)"
  echo "   ✅ SECRET_KEY_BASE    ($(echo -n "$SECRET_KEY_BASE" | wc -c) chars)"
  echo "   ✅ VAULT_ENC_KEY      ($(echo -n "$VAULT_ENC_KEY" | wc -c) chars)"
  echo "   ✅ PG_META_CRYPTO_KEY ($(echo -n "$PG_META_CRYPTO_KEY" | wc -c) chars)"
  echo "   ✅ ANON_KEY           (JWT — role: anon)"
  echo "   ✅ SERVICE_ROLE_KEY   (JWT — role: service_role)"
  echo "   ✅ IMGPROXY_KEY       ($(echo -n "$IMGPROXY_KEY" | wc -c) chars)"
  echo "   ✅ IMGPROXY_SALT      ($(echo -n "$IMGPROXY_SALT" | wc -c) chars)"

  # ─── Generate output ──────────────────────────────────
  local output
  output=$(cat "$ENV_EXAMPLE" \
    | sed "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=${POSTGRES_PASSWORD}/" \
    | sed "s/^JWT_SECRET=.*/JWT_SECRET=${JWT_SECRET}/" \
    | sed "s/^SECRET_KEY_BASE=.*/SECRET_KEY_BASE=${SECRET_KEY_BASE}/" \
    | sed "s/^VAULT_ENC_KEY=.*/VAULT_ENC_KEY=${VAULT_ENC_KEY}/" \
    | sed "s/^PG_META_CRYPTO_KEY=.*/PG_META_CRYPTO_KEY=${PG_META_CRYPTO_KEY}/" \
    | sed "s/^ANON_KEY=.*/ANON_KEY=${ANON_KEY}/" \
    | sed "s/^SERVICE_ROLE_KEY=.*/SERVICE_ROLE_KEY=${SERVICE_ROLE_KEY}/" \
    | sed "s/^IMGPROXY_KEY=.*/IMGPROXY_KEY=${IMGPROXY_KEY}/" \
    | sed "s/^IMGPROXY_SALT=.*/IMGPROXY_SALT=${IMGPROXY_SALT}/")

  if [[ "$STDOUT_ONLY" == "true" ]]; then
    echo ""
    echo "$output"
    return 0
  fi

  # ─── Write .env ───────────────────────────────────────
  echo "$output" > "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  echo ""
  echo "✅ Secrets written to $ENV_FILE (permissions: 600)"
  echo ""
  echo "──────────────────────────────────────────────"
  echo "Anon Key:    ${ANON_KEY}"
  echo "──────────────────────────────────────────────"
  echo ""
  echo "Next step: ./scripts/install.sh"
}

main
