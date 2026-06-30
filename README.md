# Supabase Production for EasyPanel

> Self-hosted Supabase em produção — deploy em 1 clique no EasyPanel com Cloudflare Tunnel e Oracle Cloud ARM (Always Free).

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Supabase](https://img.shields.io/badge/Supabase-17-green)](https://supabase.com)

Uma stack completa de Supabase self-hosted otimizada para EasyPanel, rodando no Oracle Cloud ARM Ampere (4 vCPU/24 GB RAM, sempre grátis) e exposta via Cloudflare Tunnel (sem abrir portas no firewall).

**Inclui:** PostgreSQL 17, API REST, Auth (GoTrue), Realtime (WebSockets), Storage, Image Proxy, Edge Functions, Dashboard (Studio), Observabilidade (Vector).

---

## Arquitetura

```
Cloudflare DNS ──→ Cloudflare Tunnel ──→ EasyPanel ──→ Docker Compose (13 serviços)
                                                              │
                    ┌─── PostgreSQL 17 ←── Supavisor (pooling) │
                    │         │                                │
                    │    ┌────┴──────┐                        │
                    │    │           │                        │
                    │  GoTrue    PostgREST                    │
                    │  (Auth)     (REST API)                  │
                    │    │           │                        │
                    │    └─────┬─────┘                        │
                    │          │                              │
                    │   Kong (API Gateway) ──→ Studio         │
                    │          │                              │
                    │   Storage + ImgProxy                    │
                    │   Realtime (WebSocket)                  │
                    │   Edge Functions (Deno)                 │
                    │   Vector (logs)                         │
                    └──────────────────────────────────────────
```

---

## Pré-requisitos

| Recurso | Mínimo | Recomendado |
|---------|--------|-------------|
| **RAM** | 8 GB | 24 GB (Oracle ARM) |
| **vCPU** | 2 | 4 (Oracle ARM) |
| **Disco** | 20 GB | 200 GB (Oracle ARM) |
| **Docker** | 24.0+ | 25.0+ |
| **Docker Compose** | v2.24+ | v2.29+ |
| **Sistema** | Linux (x86_64 / arm64) | Ubuntu 22.04+ / Debian 12 |
| **Domínio** | Cloudflare proxied | Cloudflare Tunnel configurado |

**Ferramentas:** `openssl`, `jq`, `curl`, `xxd` — instaladas em qualquer distro.

---

## Quick Start

### 1. Clone

```bash
git clone https://github.com/mlluiz/supabase-production-easypanel.git
cd supabase-production-easypanel
```

### 2. Configure o Cloudflare Tunnel

1. Acesse [one.dash.cloudflare.com](https://one.dash.cloudflare.com/)
2. **Access → Tunnels → Create a tunnel**
3. Escolha **Docker** como ambiente
4. Copie o token (começa com `eyJ...`)
5. Adicione os ingress:

| Domínio | URL de destino |
|---------|---------------|
| `supabase.seudominio.com` | `http://localhost:8000` |
| `studio.seudominio.com` | `http://localhost:3000` |

### 3. Instale

```bash
./scripts/install.sh
```

O script faz tudo automaticamente:
- Gera secrets criptográficos (se não existirem)
- Pull das imagens Docker
- Sobe todos os containers
- Aguarda healthchecks (5 minutos timeout)

### 4. Acesse o Studio

```
https://studio.seudominio.com
```

### 5. Crie seu primeiro projeto

No Dashboard do Supabase Studio, clique em **New Project** — tudo roda no mesmo banco PostgreSQL, com separação por schema.

---

## Configuração Manual

### Variáveis Essenciais

Edite `.env` após gerar os secrets:

```bash
# Domínios — substitua pelos seus
SUPABASE_PUBLIC_URL=https://supabase.seudominio.com
STUDIO_URL=https://studio.seudominio.com

# SMTP — necessário para emails de verificação, password reset
SMTP_HOST=smtp.resend.com
SMTP_PORT=587
SMTP_USER=seu-email@dominio.com
SMTP_PASS=sk_xxxxx
```

### Regenerar Secrets

```bash
# Interativamente (pergunta antes de sobrescrever)
./scripts/generate-secrets.sh

# Forçar sobrescrita
./scripts/generate-secrets.sh --force

# Apenas revisar (não escreve arquivo)
./scripts/generate-secrets.sh --stdout
```

---

## Serviços

| Serviço | Porta Interna | Descrição | Healthcheck |
|---------|:------------:|-----------|:-----------:|
| PostgreSQL 17 | 5432 | Banco principal com extensões Supabase | `pg_isready` |
| Supavisor | 5432/6543 | Connection pooling (session + transaction) | `pg_isready` |
| Kong | 8000/8001 | API Gateway com rate limiting e JWT | `kong health` |
| GoTrue (Auth) | 9999 | Autenticação (email, OAuth, MFA, passwordless) | `/health` |
| PostgREST | 3000 | REST API automática do schema | `/rest/v1/` |
| Realtime | 4000 | WebSockets para mudanças no banco | `/health` |
| Storage API | 5000 | Upload/download de arquivos com RLS | `/health` |
| ImgProxy | 5001 | Transformação de imagens on-the-fly | `/health` |
| Postgres Meta | 8080 | API de gerenciamento de schema | `/health` |
| Edge Runtime | 9000 | Edge Functions (Deno) | `/health` |
| Studio | 3000 | Dashboard administrativo | `/api/health` |
| Vector | — | Coleta e roteamento de logs | `/health` |
| Cloudflared | — | Túnel Cloudflare (opcional) | `tunnel info` |

**Nenhuma porta é exposta no host.** O Cloudflare Tunnel é a única entrada externa. Comunicação entre serviços via rede Docker interna `supabase`.

---

## Comandos

### Gerenciamento

```bash
# Ver status
docker compose ps

# Logs de um serviço
docker compose logs -f kong

# Parar tudo
docker compose down

# Atualizar imagens e reiniciar
docker compose pull
docker compose up -d

# Atualizar tudo incluindo cloudflare
docker compose --profile cloudflare pull
docker compose --profile cloudflare up -d
```

### Backup

```bash
# Backup manual (salva em ./backups/ por padrão)
./scripts/backup.sh

# Backup com destino customizado e retenção de 30 dias
./scripts/backup.sh --output-dir /mnt/backups --retain-days 30

# Cron (diário 3:00 AM)
# crontab -e — adicione:
0 3 * * * cd /caminho/projeto && ./scripts/backup.sh >> backups/backup.log 2>&1
```

### Restore

```bash
# Visualizar conteúdo do backup (sem restaurar)
./scripts/restore.sh --dry-run backups/supabase_2026-06-29_030000.dump.gz

# Restaurar (interativo — confirme com YES)
./scripts/restore.sh backups/supabase_2026-06-29_030000.dump.gz

# Restaurar sem confirmação (scripts automatizados)
./scripts/restore.sh --force backups/supabase_2026-06-29_030000.dump.gz
```

---

## Troubleshooting

| Problema | Causa provável | Solução |
|----------|---------------|---------|
| `docker compose config` falha | `.env` com sintaxe inválida | Verifique aspas e espaços: `grep '=' .env \| grep ' '` |
| Container reinicia em loop | Porta já em uso | `sudo ss -tlnp \| grep -E '5432\|8000\|3000'` |
| "role postgres does not exist" | Script aponta para usuário errado | Use `supabase_admin` (não `postgres`) |
| Studio não carrega | Kong não healthy | `docker compose logs kong` |
| Cloudflare Tunnel falha | Token inválido ou expirado | Regenere o token em [one.dash.cloudflare.com](https://one.dash.cloudflare.com/) |
| Backup falha | Container db offline | `docker compose ps db` |
| Autenticação por email não funciona | SMTP não configurado | Preencha `SMTP_HOST/USER/PASS` no `.env` |

### Verificação Rápida

```bash
# Todos os containers estão rodando?
docker compose ps

# Healthchecks individuais
for s in supabase-db supabase-kong supabase-auth supabase-studio; do
  echo "$s: $(docker inspect --format='{{.State.Health.Status}}' "$s" 2>/dev/null || echo 'missing')"
done
```

---

## Atualização

Ainda não há script de update automatizado (previsto para Fase 2). Por enquanto:

```bash
# 1. Backup antes de atualizar
./scripts/backup.sh

# 2. Pull das novas imagens
docker compose pull

# 3. Recreate containers
docker compose up -d
```

---

## Segurança

- **Zero portas expostas** — Todo tráfego via Cloudflare Tunnel
- **Secrets criptográficos** — Gerados com `openssl rand` (entropia do kernel)
- **Arquivo .env com permissão 600** — Só o owner lê
- **JWTs com role separation** — Chave `anon` para client-side, `service_role` para admin
- **Cloudflare WAF** — Rate limiting, bot fight mode, proteção DDoS
- **RLS (Row Level Security)** — Postgres enforcement por usuário autenticado

---

## Documentação

| Documento | Conteúdo |
|-----------|----------|
| [docs/architecture.md](docs/architecture.md) | 7 ADRs, topologia de rede, volumes, resource limits, matriz de dependências |
| [docs/stories/](docs/stories/) | Stories da Fase 1 com critérios de aceitação |
| [PRD original](Supabase-Production-EasyPanel-PRD-v1.md) | Documento de requisitos inicial |

---

## Roadmap

### Fase 1 ✅ (Atual)
- [x] Docker Compose com 13 serviços
- [x] Geração de secrets criptográficos
- [x] Script de bootstrap (install.sh)
- [x] Backup e restore automatizados
- [x] README com Quick Start

### Fase 2 ⬜
- Script de update com rollback
- Interface administrativa em Go
- Prometheus + Grafana
- Alertas (disco, backup, serviços)

### Fase 3 ⬜
- Template oficial EasyPanel
- Publicação GitHub com releases versionadas
- CI/CD com GitHub Actions

---

## Contribuindo

1. Fork o repositório
2. Crie uma branch: `git checkout -b feature/minha-feature`
3. Commit: `git commit -m 'feat: adiciona minha feature'`
4. Push: `git push origin feature/minha-feature`
5. Abra um Pull Request

---

## Licença

MIT — veja [LICENSE](LICENSE) para detalhes.
