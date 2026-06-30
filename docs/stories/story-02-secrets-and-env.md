# Story 02 — .env.example + Script de Secrets ✅

**Como** DevOps,
**quero** um template de ambiente documentado e um script que gera secrets criptograficamente seguros,
**para** configurar o ambiente de forma segura e reprodutível.

## Critérios de Aceitação

### .env.example
- [x] Todas as variáveis referenciadas no `docker-compose.yml` aparecem no `.env.example` (57 variáveis verificadas)
- [x] Placeholders usam valores dummy óbvios (ex: `your-super-secret-password-change-me`)
- [x] Cada variável tem comentário explicando o que é e como obter/gerar
- [x] Agrupamento lógico: Secrets, URLs, Pooling, Auth, SMTP, REST, Storage, ImgProxy, Meta, Kong, Studio, Cloudflare
- [x] Domínios corretos: `supabase.mlluizdevtech.com.br` e `studio.mlluizdevtech.com.br`

### generate-secrets.sh
- [x] Shebang `#!/usr/bin/env bash` com `set -euo pipefail`
- [x] Gera `POSTGRES_PASSWORD` (64 chars hex, via `openssl rand -hex 32`)
- [x] Gera `JWT_SECRET` (64 chars hex, via `openssl rand -hex 32`)
- [x] Gera `SECRET_KEY_BASE` (128 chars hex, via `openssl rand -hex 64`)
- [x] Gera `VAULT_ENC_KEY` (32 chars hex, via `openssl rand -hex 16` — ajustado do spec original de 64: Supabase requer exatamente 32)
- [x] Gera `PG_META_CRYPTO_KEY` (32 chars hex, via `openssl rand -hex 16` — ajustado: Supabase requer min 32)
- [x] Gera `ANON_KEY` e `SERVICE_ROLE_KEY` como JWTs HS256 assinados com o JWT_SECRET (usando `jq` + `openssl`)
- [x] Output é arquivo `.env` pronto para uso + flag `--stdout` para revisão
- [x] Se `.env` já existe, pergunta antes de sobrescrever
- [x] Arquivo `.env` gerado tem permissões `600`
- [x] Dependências: `openssl`, `jq`, `base64` (coreutils), `xxd` — todos padrão em qualquer distro

## Contexto Técnico

- **Arquivos criados:** `.env.example`, `scripts/generate-secrets.sh`
- **Nota:** `VAULT_ENC_KEY` usa 32 chars (não 64) e `PG_META_CRYPTO_KEY` usa 32 chars (não 64) — alinhado com a documentação oficial do Supabase
- **Nota:** `base64` do coreutils quebra linhas a cada 76 colunas. O script usa `tr -d '\n'` para remover quebras e garantir JWTs em linha única

## Definition of Done

- [x] `.env.example` criado e documentado (57 variáveis, 13 seções)
- [x] `scripts/generate-secrets.sh` criado
- [x] `chmod +x scripts/generate-secrets.sh` executado
- [x] Script testado: gera `.env` válido com JWTs decodificáveis
- [x] Script não sobrescreve `.env` existente sem confirmação
- [x] `.env` gerado tem permissões restritas (600)
