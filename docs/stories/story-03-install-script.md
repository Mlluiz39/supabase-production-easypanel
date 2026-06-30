# Story 03 — Script de Bootstrap (install.sh) ✅

**Como** DevOps,
**quero** um script que automatiza o bootstrap completo do ambiente,
**para** subir o Supabase em produção com um único comando.

## Critérios de Aceitação

- [x] Shebang `#!/usr/bin/env bash` com `set -euo pipefail`
- [x] Verifica pré-requisitos: Docker, Docker Compose, openssl, jq, curl + docker daemon running
- [x] Se `.env` não existe, executa `generate-secrets.sh` automaticamente
- [x] Se `.env` existe mas está com secrets padrão (dummy), avisa e oferece regenerar (7 padrões detectados)
- [x] Valida `docker compose config` antes de subir
- [x] `docker compose up -d` com output amigável (pull before, erros capturados)
- [x] Aguarda todos os healthchecks ficarem `healthy` (timeout de 5 minutos, progresso a cada 15s)
- [x] Exibe resumo final com URLs, anon key, acesso local PostgreSQL
- [x] Suporte a flag `--skip-healthcheck` para ambientes de teste
- [x] Suporte a flag `--no-cloudflare` para rodar sem o tunnel
- [x] Suporte a flag `--backup-dir <path>` para definir diretório de backup
- [x] Trata erros com mensagens claras (Docker não instalado, daemon offline, compose inválido, up failed)
- [x] Log timestamps em cada passo (`[2026-06-29 22:40:23]`)

### Integração Cloudflare Tunnel
- [x] Verifica se `CLOUDFLARE_TUNNEL_TOKEN` está definido no `.env`
- [x] Se estiver, sobe o serviço `cloudflared` via `--profile cloudflare`; se não, avisa + instruções
- [x] Instruções no output de como obter o token (link para dashboard Cloudflare Zero Trust)
- [x] Docker Compose usa `profiles: ["cloudflare"]` para controle declarativo do serviço

## Contexto Técnico

- **Arquivos criados:** `scripts/install.sh`
- **Arquivos modificados:** `docker-compose.yml` (+1 linha: `profiles: ["cloudflare"]` no cloudflared)
- **Referências:** `docs/architecture.md` seções 3 (rede), 9 (healthchecks), 11 (dependências)
- **Depende das stories:** Story 01 (docker-compose.yml), Story 02 (.env.example + secrets)

## Definition of Done

- [x] `scripts/install.sh` criado e executável (`chmod +x`)
- [x] Script testado com .env válido: detecta secrets reais, prossegue
- [x] Script testado com .env dummy: detecta 7 placeholders, oferece regeneração
- [x] Timeout de healthcheck configurado (300s, mostra falhas ao estourar)
- [x] Todas as flags documentadas no `--help`
- [x] Resumo final exibe URLs e anon key do .env
