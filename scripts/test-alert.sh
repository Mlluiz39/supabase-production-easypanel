#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# test-alert.sh — Dispara alerta de teste no Alertmanager
#
# Usage:
#   ./scripts/test-alert.sh                          # alerta genérico
#   ./scripts/test-alert.sh --fire "disco cheio"      # alerta customizado
#   ./scripts/test-alert.sh --resolve                 # resolve alerta anterior
#   ./scripts/test-alert.sh --help
# ─────────────────────────────────────────────────────────────
set -euo pipefail

ALERTMANAGER_URL="${ALERTMANAGER_URL:-http://localhost:9093}"
ALERT_NAME="test-alert"
ALERT_STATUS="firing"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fire)    ALERT_NAME="${2:-test-alert}"; shift 2 ;;
    --resolve) ALERT_STATUS="resolved"; shift ;;
    --help)    echo "Usage: test-alert.sh [--fire <name>] [--resolve]"; exit 0 ;;
    *)         echo "Unknown: $1"; exit 1 ;;
  esac
done

PAYLOAD=$(cat <<EOF
[{
  "status": "${ALERT_STATUS}",
  "labels": {
    "alertname": "${ALERT_NAME}",
    "severity": "critical",
    "instance": "test",
    "job": "test"
  },
  "annotations": {
    "summary": "Alerta de teste do Supabase",
    "description": "Este é um alerta de teste disparado manualmente em $(date '+%Y-%m-%d %H:%M:%S')"
  },
  "startsAt": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "endsAt": "$(date -u -d '+5 minutes' +'%Y-%m-%dT%H:%M:%SZ')"
}]
EOF
)

echo "Enviando alerta '${ALERT_NAME}' (${ALERT_STATUS}) para ${ALERTMANAGER_URL}..."
if curl -sf -XPOST -H "Content-Type: application/json" -d "$PAYLOAD" "${ALERTMANAGER_URL}/api/v1/alerts" > /dev/null 2>&1; then
  echo "✅ Alerta enviado com sucesso"
else
  echo "❌ Falha ao enviar alerta. Alertmanager está rodando?"
  echo "   curl ${ALERTMANAGER_URL}/api/v1/alerts"
  exit 1
fi
