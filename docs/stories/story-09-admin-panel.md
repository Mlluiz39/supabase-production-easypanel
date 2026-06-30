# Story 09 — Painel Administrativo em Go (Status dos Serviços)

**Como** administrador do servidor,
**quero** um painel web leve que mostra o status de todos os serviços do Supabase,
**para** rapidamente visualizar a saúde do ambiente sem precisar usar CLI.

## Critérios de Aceitação

### Aplicação Go
- [ ] Aplicação Go standalone, compilada em binário estático (para deploy via container separado ou no host)
- [ ] `go-service/` na raiz do projeto com `main.go`, `go.mod`
- [ ] Endpoints:
  - `GET /` — Página HTML com dashboard de status
  - `GET /api/status` — JSON com status de todos os serviços
  - `GET /api/health` — Healthcheck agregado (ok/degraged/critical)
- [ ] Verifica serviços consultando:
  - Docker API (container status + health) via socket montado
  - HTTP healthchecks customizados por serviço
  - Último backup (timestamp do arquivo mais recente em `backups/`)
  - Espaço em disco via `df`
  - Uptime do sistema via `/proc/uptime`

### Dashboard Web
- [ ] Interface HTML sem frameworks (Go templates + CSS vanilla)
- [ ] **Cards coloridos por status:** verde (healthy), amarelo (degraded), vermelho (down)
- [ ] Para cada serviço: nome, status, uptime, últimas 3 linhas de log
- [ ] Seção de **healthcheck agregado**: OK se todos healthy, DEGRADED se algum falhou, CRITICAL se banco offline
- [ ] Seção de **backup**: status (OK / nunca feito / atrasado), data do último, próximo agendado
- [ ] Seção de **disco**: espaço usado/livre/total por volume
- [ ] Auto-refresh a cada 30s via JavaScript simples
- [ ] Suporte a `prefers-color-scheme: dark` (modo escuro nativo)

### Container Docker
- [ ] `Dockerfile` multi-stage para compilar binário (~10 MB final)
- [ ] Serviço `admin` no `docker-compose.yml` com profile `admin`
- [ ] Exposto via Kong: `admin.seudominio.com` ou via rota `/admin` no Kong

### Integração com Kong
- [ ] Rota para o painel admin configurada no `kong/kong.yml`
- [ ] Protegida por `key-auth` (ou `basic-auth`) para não expor status publicamente

## Contexto Técnico

- **Arquivos criados:** `go-service/main.go`, `go-service/go.mod`, `go-service/Dockerfile`, `go-service/templates/`
- **Arquivos modificados:** `docker-compose.yml`, `kong/kong.yml`
- **Depende das stories:** Story 01 (docker-compose.yml), Story 04 (backup.sh)
- **Estimativa:** G (4-6h)

## Definition of Done

- [ ] Binário Go compila com `CGO_ENABLED=0 GOOS=linux go build`
- [ ] Container Docker com < 20 MB
- [ ] Dashboard acessível via `http://localhost:XXXX`
- [ ] Cards coloridos mostram status correto de cada serviço
- [ ] Status do backup reflete realidade (ok / atrasado / nunca)
- [ ] Disco mostra uso correto
- [ ] Auto-refresh 30s funciona
- [ ] Modo escuro respeita preferência do sistema
