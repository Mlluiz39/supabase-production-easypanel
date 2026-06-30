# Phase 1 — Stories

| # | Story | Estimativa | Depende de | Status |
|---|-------|-----------|------------|--------|
| [01](story-01-docker-compose.md) | Docker Compose com 13 Serviços | G (4-6h) | — | ✅ Concluída |
| [02](story-02-secrets-and-env.md) | .env.example + Script de Secrets | G (4-6h) | 01 | ✅ Concluída |
| [03](story-03-install-script.md) | Script de Bootstrap (install.sh) | M (2-4h) | 01, 02 | ✅ Concluída |
| [04](story-04-backup-restore.md) | Scripts de Backup e Restore | M (2-4h) | 01 | ✅ Concluída |
| [05](story-05-readme-docs.md) | README.md e Documentação | P (<2h) | 01, 02, 03, 04 | ✅ Concluída |

## Gráfico de Dependências

```
Story 01 (docker-compose.yml)
  ├── Story 02 (.env + secrets)
  │     └── Story 03 (install.sh)
  ├── Story 04 (backup/restore)
  └── Story 05 (README) ← depende de todas as anteriores
```

## Ordem Recomendada

1. **Story 01** — Fundação: sem compose, nada sobe
2. **Story 02** — Secrets: `.env` é necessário para validar o compose
3. **Story 03 ou 04** — Paralelizáveis: install.sh e backup/restore não dependem entre si
4. **Story 05** — Por último: documenta o que foi construído

## Estimativa Total: 14-22 horas (Fase 1)
