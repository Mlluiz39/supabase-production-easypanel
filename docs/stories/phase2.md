# Phase 2 — Stories

| # | Story | Estimativa | Depende de | Status |
|---|-------|-----------|------------|--------|
| # | Story | Estimativa | Depende de | Status |
|---|-------|-----------|------------|--------|
| [06](story-06-update-script.md) | Script de Update com Rollback | G (4-6h) | 01, 04 | ✅ Concluída |
| [07](story-07-prometheus-grafana.md) | Prometheus + Grafana | G (4-6h) | 01 | ✅ Concluída |
| [08](story-08-alerts.md) | Alertas e Notificações | M (2-4h) | 07, 04 | ✅ Concluída |
| [09](story-09-admin-panel.md) | Painel Admin em Go | G (4-6h) | 01, 04 | ✅ Concluída |

## Gráfico de Dependências

```
Story 01 (docker-compose) ─ Fundação
  ├── Story 06 (update.sh)        ← independe das outras
  ├── Story 07 (Prometheus)       ← base para 08
  │     └── Story 08 (alertas)    ← depende de 07
  └── Story 09 (painel Go)        ← independe das outras
```

## Ordem Recomendada

1. **Story 06** — Update com rollback (maior impacto em segurança operacional)
2. **Story 07** — Prometheus + Grafana (base para monitoramento)
3. **Story 09** — Painel admin Go (paralelo com 07)
4. **Story 08** — Alertas (depende de 07)

## Estimativa Total: 12-22 horas (Fase 2)
