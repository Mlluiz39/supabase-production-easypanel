# Architecture — Supabase Production for EasyPanel

> Versão 1.0 — 2026-06-29

---

## 1. Visão Geral

Implantação **single-node** de Supabase self-hosted sobre Docker Compose, orquestrada pelo EasyPanel, rodando em Oracle Cloud ARM Ampere (Always Free) e exposta via Cloudflare Tunnel com HTTPS gerenciado.

```
Internet → Cloudflare DNS → Cloudflare Tunnel → EasyPanel → Docker Compose (18 serviços)
```

---

## 2. Stack

| Camada | Tecnologia | Versão Alvo | Por quê |
|--------|------------|-------------|---------|
| **Orquestração** | EasyPanel | latest | Interface visual, backup integrado, deploy em 1 clique, suporte a templates customizados |
| **Runtime** | Docker Compose | v2.24+ | Nativo do EasyPanel, simples, sem complexidade do Kubernetes |
| **API Gateway** | Kong | 3.9.1 | Já integrado ao Supabase, gerencia rotas, rate limiting e JWT validation |
| **Banco** | PostgreSQL (Supabase) | 17.6.1 | Imagem oficial Supabase com extensões pré-compiladas (pgvector, pg_net, pgsodium, etc.) |
| **Pooling** | Supavisor | 2.9.5 | Transaction pooling nativo, substitui PgBouncer, multi-tenant |
| **Auth** | GoTrue | v2.189.0 | Auth completa (email, OAuth, SAML, MFA, passwordless) |
| **API REST** | PostgREST | v14.12 | API REST auto-gerada a partir do schema Postgres |
| **Realtime** | Supabase Realtime | v2.102.3 | WebSockets para mudanças no banco, presença, broadcast |
| **Storage** | Supabase Storage | v1.60.4 | S3-compatible, file storage com políticas RLS |
| **Image Proxy** | ImgProxy | v3.30.1 | Resize/transformação de imagens on-the-fly |
| **Metadata** | Postgres Meta | v0.96.6 | API de gestão de schema/tabelas |
| **Edge Functions** | Deno Edge Runtime | v1.74.0 | Funções serverless no edge |
| **Dashboard** | Supabase Studio | 2026.06.03 | Interface administrativa (Table Editor, SQL Editor, Auth, Storage) |
| **Tunnel** | Cloudflare Tunnel (cloudflared) | latest | Zero Trust, sem portas abertas, HTTPS incluso, gratuito |
| **Logs** | Vector | latest | Coleta e centralização de logs de todos os containers |
| **Host** | Oracle Cloud ARM Ampere | A1.Flex | 4 OCPU / 24 GB RAM / 200 GB — Always Free Tier |
| **Monitoring** | Prometheus + Grafana | v3.2.1 / v11.5.2 | Métricas, dashboards, alertas (profile: `monitoring`) |
| **Admin Panel** | Go service | custom | Dashboard de status dos serviços (profile: `admin`) |

---

## 3. Topologia de Rede

```
                         ┌──────────────────────────────┐
                         │     Cloudflare Tunnel          │
                         │  cloudflared (container extra) │
                         │                                │
                         │  supabase.mlluizdevtech.com.br │
                         │  → kong:8000                   │
                         │  studio.mlluizdevtech.com.br   │
                         │  → studio:3000                 │
                         └──────────┬───────────────────┘
                                    │
              ┌─────────────────────┼─────────────────────┐
              │          Docker Network: supabase          │
              │                     │                      │
              │    ┌────────────────┼───────────────┐      │
              │    │       Kong :8000 (gateway)      │      │
              │    │   Rotas internas para serviços  │      │
              │    └────┬───┬───┬───┬───┬───┬──────┘      │
              │         │   │   │   │   │   │              │
              │    ┌────┼───┼───┼───┼───┼───┼───────┐     │
              │    │ Studio :3000                     │     │
              │    └────┼─────────────────────────────┘     │
              │         │                                   │
              │    ┌────▼──┐ ┌────▼──┐ ┌──▼─────┐         │
              │    │ Auth   │ │ REST  │ │Storage │         │
              │    │ :9999  │ │ :3001 │ │ :5000  │         │
              │    └────┬───┘ └───┬───┘ └───┬────┘         │
              │         │         │         │               │
              │    ┌────▼──┐ ┌───▼────┐     │              │
              │    │ Meta   │ │Realtime│     │              │
              │    │ :8080  │ │ :4000  │     │              │
              │    └───┬────┘ └───┬────┘     │              │
              │        │          │          │              │
              │    ┌───▼──────────▼──────────▼──────┐      │
              │    │     Supavisor :5432 / :6543     │      │
              │    │   Transaction pooling           │      │
              │    └──────────────┬──────────────────┘      │
              │                   │                         │
              │    ┌──────────────▼──────────────────┐      │
              │    │   PostgreSQL 17 :5432            │      │
              │    │   /var/lib/postgresql/data       │      │
              │    └──────────────┬──────────────────┘      │
              │                   │                         │
              │    ┌──────────────▼──────────────────┐      │
              │    │   ImgProxy :5001                 │      │
              │    │   Transformação de imagens       │      │
              │    └──────────────────────────────────┘      │
              │                                              │
              │    ┌──────────────────────────────────┐      │
              │    │   Edge Functions :9000            │      │
              │    │   Deno runtime                    │      │
              │    └──────────────────────────────────┘      │
              │                                              │
              │    ┌──────────────────────────────────┐      │
              │    │   Vector (logs → stdout/stderr)   │      │
              │    └──────────────────────────────────┘      │
              └──────────────────────────────────────────────┘
```

**Regra de tráfego:** Nenhum serviço expõe porta no host. O Cloudflare Tunnel é a única entrada. Toda comunicação interna é via rede Docker `supabase`.

---

## 4. Decisões de Arquitetura (ADRs)

### ADR-001 — Docker Compose, não Kubernetes

**Decisão:** Usar Docker Compose como orquestrador único.

**Motivo:**
- EasyPanel tem suporte nativo a Docker Compose (templates, backups, healthchecks)
- O projeto roda em **um único nó** (Oracle ARM 4/24). Kubernetes traria complexidade sem benefício de escala horizontal.
- Supabase oficial fornece docker-compose.yml de referência — podemos partir dele.

**Trade-offs:** Sem auto-healing nativo do K8s. Mitigamos com `restart: unless-stopped` e healthchecks no EasyPanel.

---

### ADR-002 — Supavisor como Pool de Conexões (Externo)

**Decisão:** Manter Supavisor disponível, mas serviços internos conectam direto no PostgreSQL.

**Motivo:**
- Supavisor exige `external_id` ou `sni_hostname` para roteamento multi-tenant — overhead desnecessário para single-tenant na mesma rede Docker.
- Serviços internos (GoTrue, PostgREST, Storage, Meta, Functions, Realtime) usam `db:5432` diretamente.
- Supavisor permanece disponível para conexões externas via Cloudflare Tunnel (com pooling de conexão quando necessário).
- Supabase migrou oficialmente para Supavisor, mas ele é projetado para cenários multi-tenant com roteamento SNI.

**Trade-offs:** Sem pooling entre serviços internos e PostgreSQL. Cada serviço gerencia seu próprio pool (configurável via variáveis de ambiente). Com 24 GB de RAM disponíveis e single-node, conexões diretas não são gargalo.

---

### ADR-003 — Cloudflare Tunnel, sem portas expostas

**Decisão:** Toda exposição é via Cloudflare Tunnel. Nenhuma porta bindada no host.

**Motivo:**
- Oracle Cloud free tier tem limitações de firewall e apenas 1 IP reservado.
- Cloudflare Tunnel é gratuito, provê HTTPS automático, não requer abrir portas.
- Protege contra DDoS e scan de portas.
- Dois domínios mapeados: `supabase.mlluizdevtech.com.br` → Kong e `studio.mlluizdevtech.com.br` → Studio.

**Trade-offs:** Dependência do Cloudflare. Se o túnel cair, o serviço fica offline mesmo com o servidor OK. Mitigamos com healthcheck + restart automático do `cloudflared`.

---

### ADR-004 — PostgreSQL 17, não 15

**Decisão:** Usar PostgreSQL 17 (imagem `supabase/postgres:17.6.1.136`).

**Motivo:**
- O PRD original especificava PG15, mas a imagem oficial do Supabase já está na versão 17.
- PG17 traz melhorias de performance (melhor paralelismo, melhor vacuum) e é a versão suportada ativamente.
- Usar a imagem oficial Supabase garante todas as extensões pré-compiladas.

**Trade-offs:** Se houver necessidade futura de downgrade, não há caminho simples. Como o projeto é novo, partimos da versão mais recente.

---

### ADR-005 — Storage com File Backend Local

**Decisão:** Usar filesystem local para storage (não S3 externo).

**Motivo:**
- Oracle Cloud oferece 200 GB de block storage gratuito — suficiente para o estágio atual.
- Elimina dependência externa (AWS S3, Cloudflare R2).
- Simplifica backup: um volume para fazer snapshot.

**Trade-offs:** Sem redundância geográfica. Se o disco falhar, os arquivos são perdidos. Backup resolve isso. Futuro: migrar para S3-compatible se escalar.

---

### ADR-006 — Sem Analytics / Logflare

**Decisão:** Não incluir Analytics (Logflare + BigQuery).

**Motivo:**
- Já definido no PRD como fora de escopo.
- Logflare depende de BigQuery (pago) ou requer manutenção de um ClickHouse.
- Para um ambiente single-node, logs via Vector para stdout/stderr e visualização no EasyPanel são suficientes.

**Trade-offs:** Sem métricas de uso do Supabase (queries lentas, erros de API, uso de banda). Pode ser adicionado na Fase 2 com monitoring.

---

### ADR-007 — Kong como API Gateway (não Traefik/Nginx)

**Decisão:** Manter Kong como API gateway, já que é o padrão Supabase.

**Motivo:**
- Kong já vem configurado com todas as rotas internas do Supabase.
- JWT validation integrada com GoTrue.
- Rate limiting por chave anônima/service_role.
- Substituir por outro gateway seria retrabalho desnecessário.

**Trade-offs:** Kong é mais pesado que Nginx/Caddy (~200 MB RAM). Com 24 GB, irrelevante.

---

## 5. Estrutura de Pastas

```
supabase-production-easypanel/
├── docker-compose.yml          # Serviços Supabase + cloudflared + vector
├── docker-compose.prod.yml     # Overrides de produção (resource limits, restart policies)
├── .env.example                # Template de variáveis com placeholders
├── template.json               # Metadados do template EasyPanel (Fase 3)
│
├── scripts/
│   ├── install.sh              # Bootstrap completo: .env → secrets → compose up
│   ├── generate-secrets.sh     # Gera JWT_SECRET, POSTGRES_PASSWORD, etc.
│   ├── backup.sh               # pg_dump + compressão + retenção
│   ├── restore.sh              # Restore a partir de arquivo de backup
│   └── update.sh               # Pull novas images + restart com verificação
│
├── kong/
│   ├── kong.yml                # Configuração declarativa do Kong (rotas, serviços, plugins)
│   └── custom-plugins/         # Plugins Kong customizados (se necessário)
│
├── postgres/
│   └── init/                   # Scripts SQL de inicialização (roles, schemas customizados)
│
├── monitoring/
│   └── vector.toml             # Configuração do Vector: coleta de logs → stdout
│
├── backups/                    # Diretório de destino dos backups (bind mount)
│
├── volumes/                    # Dados persistentes (no .gitignore)
│   ├── db/
│   ├── storage/
│   ├── functions/
│   └── snippets/
│
├── docs/
│   ├── architecture.md         # Este documento
│   ├── deployment.md           # Guia de deploy (a ser criado)
│   └── stories/                # User stories do Scrum Master
│
└── README.md                   # Documentação principal do projeto
```

---

## 6. Volumes e Persistência

| Volume | Caminho no Host | Container Path | Backup? |
|--------|-----------------|----------------|---------|
| `db-data` | `./volumes/db/data` | `/var/lib/postgresql/data` | Sim (pg_dump) |
| `storage` | `./volumes/storage` | `/var/lib/storage` | Sim (snapshot volume) |
| `functions` | `./volumes/functions` | `/home/deno/functions` | Opcional |
| `db-config` | named volume (Docker) | `/etc/postgresql` | Não (gerado) |
| `deno-cache` | named volume (Docker) | `/root/.cache` | Não (cache) |
| `backups` | `./backups` | `/backups` (mount no script) | N/A |

---

## 7. Variáveis de Ambiente (Agrupadas)

### Secrets (geradas automaticamente)
| Variável | Descrição | Tamanho Mínimo |
|----------|-----------|-----------------|
| `POSTGRES_PASSWORD` | Senha do banco | 32 chars |
| `JWT_SECRET` | Chave de assinatura JWT | 32 chars |
| `SECRET_KEY_BASE` | Session/CSRF tokens | 64 chars |
| `VAULT_ENC_KEY` | Criptografia de secrets | 32 chars |
| `PG_META_CRYPTO_KEY` | Criptografia de metadata | 32 chars |
| `ANON_KEY` | Chave pública (cliente) | JWT signed |
| `SERVICE_ROLE_KEY` | Chave admin (servidor) | JWT signed |

### Configuração
| Variável | Exemplo |
|----------|---------|
| `SUPABASE_PUBLIC_URL` | `https://supabase.mlluizdevtech.com.br` |
| `API_EXTERNAL_URL` | `https://supabase.mlluizdevtech.com.br` |
| `STUDIO_URL` | `https://studio.mlluizdevtech.com.br` |
| `SITE_URL` | `https://studio.mlluizdevtech.com.br` |
| `POSTGRES_PORT` | `5432` |
| `POOLER_PROXY_PORT_TRANSACTION` | `6543` |
| `POSTGRES_DB` | `postgres` |

### SMTP (para emails de Auth)
| Variável | Descrição |
|----------|-----------|
| `SMTP_HOST` | Servidor SMTP |
| `SMTP_PORT` | Porta (587 recomendado) |
| `SMTP_USER` | Usuário |
| `SMTP_PASS` | Senha |
| `SMTP_SENDER_NAME` | Nome do remetente |

---

## 8. Estratégia de Backup

```
Cron Diário (3:00 AM UTC) → backup.sh
  ├── pg_dump --format=custom → backups/supabase_YYYY-MM-DD.dump
  ├── gzip --best → backups/supabase_YYYY-MM-DD.dump.gz
  ├── Verifica integridade (pg_restore --list)
  └── Remove backups > N dias (RETAIN_DAYS configurável, default 7)
```

**Restore:**
```bash
./scripts/restore.sh backups/supabase_2026-06-29.dump.gz
# → gunzip → pg_restore → verificação
```

**Volume de storage** (arquivos): backup via EasyPanel (snapshot automático de volumes).

---

## 9. Healthchecks

| Serviço | Tipo | Endpoint | Intervalo |
|---------|------|----------|-----------|
| PostgreSQL | `pg_isready` | — | 5s |
| Supavisor | TCP | porta 5432 | 5s |
| Kong | HTTP | `/status` | 5s |
| Auth | HTTP | `/auth/v1/health` | 5s |
| REST | HTTP | `/rest/v1/` | 5s |
| Realtime | HTTP | `/realtime/v1/health` | 5s |
| Storage | HTTP | `/storage/v1/health` | 5s |
| Meta | HTTP | `/health` | 5s |
| Studio | HTTP | `/api/health` | 5s |
| Edge Functions | HTTP | `/functions/v1/health` | 5s |
| ImgProxy | HTTP | `/health` | 5s |
| Cloudflared | Process | `cloudflared tunnel info` | 30s |

Todos os serviços têm `restart: unless-stopped` e healthchecks com `retries: 5`.

---

## 10. Resource Limits (Oracle ARM — 4 vCPU / 24 GB RAM)

| Serviço | CPU Limit | Memory Limit | Por quê |
|---------|-----------|--------------|---------|
| PostgreSQL | 2.0 | 6 GB | Carga principal, shared_buffers ~1.5 GB |
| Supavisor | 0.5 | 512 MB | Pooling leve |
| Kong | 0.5 | 512 MB | API gateway |
| Auth | 0.3 | 256 MB | GoTrue é leve |
| REST | 0.3 | 256 MB | PostgREST é eficiente |
| Realtime | 0.5 | 512 MB | WebSocket connections |
| Storage | 0.3 | 256 MB | File upload/download |
| Meta | 0.2 | 128 MB | Metadata API, uso esporádico |
| Edge Functions | 0.5 | 512 MB | Deno runtime |
| Studio | 0.3 | 256 MB | Dashboard, uso esporádico |
| ImgProxy | 0.3 | 256 MB | Processamento de imagem |
| Vector | 0.2 | 128 MB | Coleta de logs |
| Cloudflared | 0.2 | 128 MB | Túnel Cloudflare |
| Prometheus | 0.3 | 512 MB | Métricas + regras de alerta (profile: monitoring) |
| Grafana | 0.3 | 256 MB | Dashboards visuais |
| Node Exporter | 0.2 | 128 MB | Métricas do host |
| Postgres Exporter | 0.2 | 128 MB | Métricas do PostgreSQL |
| Alertmanager | 0.2 | 128 MB | Alertas e notificações |
| Admin Panel | 0.2 | 64 MB | Dashboard Go de status dos serviços (profile: admin) |
| **Total (core)** | **~6.1** | **~9.5 GB** | Margem de ~14 GB |
| **Total (monitoring)** | **+1.4** | **+1.2 GB** | Profiles opcionais |

---

## 11. Matriz de Dependências (Ordem de Inicialização)

```
PostgreSQL (db)
  ├── Supavisor
  │     ├── Auth (GoTrue)
  │     ├── REST (PostgREST)
  │     ├── Realtime
  │     ├── Storage
  │     │     └── ImgProxy
  │     ├── Meta
  │     └── Edge Functions (via Kong)
  ├── Kong
  │     └── Studio
  └── Vector (coleta logs de todos)
```

Docker Compose resolve isso com `depends_on` + `condition: service_healthy`.

---

## 12. Observabilidade

| Ferramenta | Propósito | Destino |
|------------|-----------|---------|
| Vector | Coleta logs de todos os containers | stdout (visível no EasyPanel) |
| Kong logs | API requests, erros, latência | Vector → stdout |
| PostgreSQL logs | Slow queries, erros | Vector → stdout |
| EasyPanel | Dashboard de CPU/RAM/disco | Interface visual |

**Não incluso (Fase 2):** Prometheus + Grafana para métricas detalhadas, alertas por email/webhook.

---

## 13. Segurança

- **JWT + RLS:** Todo acesso a dados passa por Row Level Security no Postgres
- **Kong rate limiting:** 100 req/s para anon key, 1000 req/s para service_role
- **Secrets isolados:** `.env` nunca commitado (`.gitignore`), secrets gerados via script criptograficamente seguro (`openssl rand -hex`)
- **Sem portas expostas:** Apenas Cloudflare Tunnel tem acesso externo
- **Cloudflare WAF:** Configurável via dashboard Cloudflare (regras de bloqueio, rate limiting)
- **SMTP seguro:** Porta 587 com STARTTLS para emails de Auth
- **CORS:** Configurado apenas para os domínios do projeto

---

## 14. Roadmap Técnico

### Fase 1 ✅ — Infraestrutura Base
- [x] `docker-compose.yml` com todos os serviços
- [x] `.env.example` documentado
- [x] `generate-secrets.sh` funcional
- [x] `install.sh` (bootstrap completo)
- [x] `backup.sh` + `restore.sh` testados
- [x] Cloudflared integrado ao compose
- [x] Healthchecks em todos os serviços
- [x] `README.md` com instruções de deploy

### Fase 2 ✅ — Gestão e Monitoramento
- [x] Interface administrativa em Go (painel de status dos serviços + Kong route)
- [x] `update.sh` com rollback (pull → backup → restart → healthcheck → rollback se falhar)
- [x] Prometheus + Grafana (+ node-exporter + postgres-exporter, profile `monitoring`)
- [x] Alertmanager com 8 regras de alerta (disco, serviços, PG, Kong, backup)

### Fase 3 — Distribuição
- [ ] `template.json` para EasyPanel (deploy em 1 clique)
- [ ] Publicação no GitHub com releases versionadas
- [ ] CI/CD com GitHub Actions (validação de compose, lint de scripts)

---

## 15. Referências

- [Supabase Self-Hosting Docs](https://supabase.com/docs/guides/self-hosting/docker)
- [Supabase Docker Compose (oficial)](https://github.com/supabase/supabase/tree/master/docker)
- [EasyPanel Custom Templates](https://easypanel.io/docs/templates/custom-templates)
- [Cloudflare Tunnel Docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)
- [Oracle Cloud Always Free](https://www.oracle.com/cloud/free/)
