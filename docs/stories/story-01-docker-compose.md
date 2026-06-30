# Story 01 — Docker Compose com 13 Serviços ✅

**Como** DevOps,
**quero** um docker-compose.yml completo com todos os serviços do Supabase,
**para** subir o ambiente inteiro com `docker compose up -d`.

## Critérios de Aceitação

- [x] `docker-compose.yml` define todos os serviços: db, supavisor, kong, auth, rest, realtime, storage, imgproxy, meta, functions, studio, vector + cloudflared (13)
- [x] Rede `supabase` é criada e todos os serviços se conectam a ela
- [x] `depends_on` com `condition: service_healthy` garante ordem de inicialização correta: db → supavisor → (auth, rest, realtime, storage, meta, functions) → kong → studio → cloudflared
- [x] Volumes nomeados para `db-data`, `db-config`, `storage-data`, `functions-data`, `deno-cache` estão definidos
- [x] Variáveis de ambiente são referenciadas via `${VAR}` (não hardcoded) — todas as secrets e URLs
- [x] `docker compose config` valida sem erros (com `.env` de teste)
- [x] Imagens usam as versões exatas definidas no `architecture.md`
- [x] Nenhuma porta exposta no host (zero `ports:` em todos os serviços)

## Contexto Técnico

- **Arquivos criados:** `docker-compose.yml`, `kong/kong.yml`, `monitoring/vector.toml`, `.gitignore`
- **Referências:** `docs/architecture.md` seções 3 (topologia), 6 (volumes), 11 (dependências)
- **Base:** [docker-compose.yml oficial do Supabase](https://github.com/supabase/supabase/tree/master/docker)
- **Nota:** cloudflared incluído como 13º serviço (essencial para arquitetura Cloudflare Tunnel)

## Definition of Done

- [x] `docker-compose.yml` criado
- [x] `docker compose config` valida com um `.env` de teste
- [x] Todos os serviços têm `container_name`, `image`, `environment`, `volumes`, `depends_on`, `healthcheck`
- [x] Serviços que não precisam de exposição externa não têm seção `ports`
