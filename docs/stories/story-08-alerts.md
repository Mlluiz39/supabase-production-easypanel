# Story 08 — Alertas e Notificações

**Como** DevOps,
**quero** alertas automáticos quando algo crítico acontecer (serviço offline, disco cheio, backup falhou),
**para** responder antes que os usuários sejam impactados.

## Critérios de Aceitação

### Alertas no Prometheus (Alertmanager)
- [ ] `alertmanager` (imagem `prom/alertmanager:latest`) adicionado ao compose com perfil `monitoring`
- [ ] `monitoring/alertmanager.yml` configurado com rota para email e/ou webhook
- [ ] Regras de alerta em `monitoring/prometheus-rules.yml`:

| Alerta | Condição | Severidade |
|--------|----------|------------|
| Serviço offline | `up == 0` por > 60s | critical |
| Disco quase cheio | `disk_usage > 85%` | warning |
| Disco crítico | `disk_usage > 95%` | critical |
| Backup não executado | Último backup > 26h | warning |
| PostgreSQL connections alto | `pg_stat_activity_count > 80% max_connections` | warning |
| Cache hit ratio baixo | `pg_cache_hit_ratio < 0.95` | warning |
| API latência alta | `kong_latency_p99 > 2s` | warning |
| Kong errors | `kong_http_errors > 5%` em 5min | warning |

### Canais de Notificação
- [ ] **Email:** SMTP para email configurável via `.env` (reusa config SMTP existente)
- [ ] **Webhook:** Suporte a webhook Slack/Discord via variável de ambiente
- [ ] **Teste:** Script `scripts/test-alert.sh` que dispara alerta de teste

### Healthcheck Endpoint Público
- [ ] Healthcheck HTTP exposto via Kong: `GET /api/health`
- [ ] Responde JSON: `{"status":"ok","services":[...],"uptime":...,"last_backup":"..."}`
- [ ] Pode ser usado por UptimeRobot, BetterUptime, ou Cloudflare Healthchecks
- [ ] Endpoint não requer autenticação (apenas para healthcheck externo)

### Dashboard de Incidentes
- [ ] README atualizado com seção de alertas (canais, como configurar)
- [ ] Documentação de como adicionar novos alertas

## Contexto Técnico

- **Arquivos criados:** `monitoring/alertmanager.yml`, `monitoring/prometheus-rules.yml`, `scripts/test-alert.sh`
- **Arquivos modificados:** `docker-compose.yml` (alertmanager), `kong/kong.yml` (rota healthcheck)
- **Depende das stories:** Story 07 (Prometheus + Grafana), Story 04 (backup.sh)
- **Estimativa:** M (2-4h)

## Definition of Done

- [ ] Alertmanager configurado + rodando no profile monitoring
- [ ] Pelo menos 5 regras de alerta ativas no Prometheus
- [ ] Notificação por email funcionando
- [ ] Notificação por webhook (Slack/Discord) funcionando
- [ ] Healthcheck público `GET /api/health` respondendo JSON
- [ ] Teste de alerta bem-sucedido
