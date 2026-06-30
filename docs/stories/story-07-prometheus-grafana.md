# Story 07 — Prometheus + Grafana

**Como** DevOps,
**quero** métricas detalhadas de todos os serviços (CPU, RAM, disco, conexões, latência),
**para** monitorar a saúde do Supabase e identificar problemas antes dos usuários.

## Critérios de Aceitação

### docker-compose — Novos Serviços
- [ ] `prometheus` (imagem `prom/prometheus:latest`) adicionado ao compose com perfil `monitoring`
- [ ] `grafana` (imagem `grafana/grafana:latest`) adicionado ao compose com perfil `monitoring`
- [ ] `node-exporter` (imagem `prom/node-exporter:latest`) adicionado ao compose com perfil `monitoring`
- [ ] `postgres-exporter` (imagem `prometheuscommunity/postgres-exporter:latest`) adicionado ao compose com perfil `monitoring`
- [ ] Serviços `monitoring` usam `profiles: ["monitoring"]` para não subir por padrão
- [ ] Volumes nomeados para `prometheus-data` e `grafana-data`

### Configuração Prometheus
- [ ] `monitoring/prometheus.yml` com targets para:
  - node-exporter (sistema host — CPU, RAM, disco, rede)
  - postgres-exporter (conexões, tamanho do banco, cache hit ratio, deadlocks)
  - Kong (requests, latência, erros HTTP 4xx/5xx)
  - Supavisor (pool utilization, client connections)
- [ ] Scrape interval: 15s para sistema, 30s para aplicação
- [ ] Retenção de dados: 15 dias

### Configuração Grafana
- [ ] Provisionamento automático:
  - `monitoring/grafana/datasources/prometheus.yml`
  - `monitoring/grafana/dashboards/supabase.json` (dashboard pré-configurado)
- [ ] Dashboard do Supabase com painéis:
  - **Overview:** CPU/RAM total, serviços online/offline, conexões ativas
  - **PostgreSQL:** Tamanho do banco, conexões, cache hit ratio, transações/s
  - **API Gateway:** Requests/s, latência P50/P95/P99, erros por rota
  - **Storage:** Uploads/downloads/s, espaço usado, bandwidth
  - **Auth:** Signups/s, logins/s, erros de autenticação
- [ ] Credenciais admin: `admin` / `admin` (solicita troca no primeiro login)
- [ ] `install.sh` atualizado para aceitar `--monitoring` e ativar o profile

### Conexão com Serviços Existentes
- [ ] Prometheus consegue scrape:
  - Kong metrics (`http://kong:8001/metrics`)
  - Node exporter via rede Docker
  - Postgres via postgres-exporter

## Contexto Técnico

- **Arquivos criados:** `monitoring/prometheus.yml`, `monitoring/grafana/datasources/prometheus.yml`, `monitoring/grafana/dashboards/supabase.json`
- **Arquivos modificados:** `docker-compose.yml` (adicionar serviços monitoring com profile)
- **Depende das stories:** Story 01 (docker-compose.yml)
- **Estimativa:** G (4-6h)

## Definition of Done

- [ ] `docker compose --profile monitoring up -d` sobe Prometheus + Grafana + exporters
- [ ] Prometheus scraping todos os targets (targets UP no /targets)
- [ ] Grafana acessível e dashboard do Supabase carregando dados reais
- [ ] `install.sh` integrado com flag `--monitoring`
- [ ] Alertas configurados no Prometheus (disco > 80%, serviços offline > 1min)
