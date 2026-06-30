# Story 06 — Script de Update com Rollback

**Como** DevOps,
**quero** um script de update que executa pull, backup automático, restart e rollback em caso de falha,
**para** atualizar o Supabase com segurança mínima de interrupção.

## Critérios de Aceitação

### update.sh
- [ ] Shebang `#!/usr/bin/env bash` com `set -euo pipefail`
- [ ] **Fase 1 — Preparação:** Verifica pré-requisitos (Docker, espaço em disco)
- [ ] **Fase 2 — Backup automático:** Executa `backup.sh` antes de qualquer alteração
- [ ] **Fase 3 — Pull:** `docker compose pull --quiet` com detecção de mudanças (compara hashes)
- [ ] **Fase 4 — Restart:** `docker compose up -d` com os novos containers
- [ ] **Fase 5 — Healthcheck:** Aguarda todos os serviços ficarem `healthy` (timeout configurável, default 300s)
- [ ] **Fase 6 — Rollback automático:** Se healthcheck falhar, restaura backup do compose (via git stash/tag) e restart dos containers anteriores
- [ ] Suporte a flag `--skip-backup` para ambientes onde backup já foi feito
- [ ] Suporte a flag `--rollback-only <tag>` para voltar para versão específica
- [ ] Suporte a flag `--dry-run` para mostrar quais imagens seriam atualizadas
- [ ] Log timestamps + duração total ao final
- [ ] Resumo final exibe versões antigas → novas de cada imagem

### Git Tagging para Rollback
- [ ] Antes de puxar novas imagens, cria git tag: `deploy-YYYY-MM-DD-HHMMSS`
- [ ] Em caso de rollback, o script retorna ao `deploy-*` anterior (git stash + reset)
- [ ] O rollback inclui restaurar o `docker-compose.yml` e `.env` se foram modificados

## Contexto Técnico

- **Arquivos afetados:** `scripts/update.sh` (criar)
- **Depende das stories:** Story 01 (docker-compose.yml), Story 04 (backup.sh)
- **Estimativa:** G (4-6h)

## Definition of Done

- [ ] `scripts/update.sh` criado e executável
- [ ] Fluxo completo testado: pull → backup → restart → healthy → sucesso
- [ ] Rollback testado: healthcheck falha → rollback automático → serviços estáveis
- [ ] Dry-run mostra diferenças sem alterar nada
- [ ] Git tags criadas antes de cada update
