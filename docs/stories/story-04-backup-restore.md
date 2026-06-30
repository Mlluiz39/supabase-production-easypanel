# Story 04 — Scripts de Backup e Restore ✅

**Como** DevOps,
**quero** scripts de backup diário e restore testado,
**para** garantir que os dados possam ser recuperados em caso de falha.

## Critérios de Aceitação

### backup.sh
- [x] Shebang `#!/usr/bin/env bash` com `set -euo pipefail`
- [x] Carrega variáveis do `.env` (POSTGRES_PASSWORD, POSTGRES_DB) com cut seguro
- [x] `pg_dump` usa `--format=custom` (comprimido, restaurável seletivamente)
- [x] Nome do arquivo: `supabase_YYYY-MM-DD_HHMMSS.dump`
- [x] Compressão adicional com `gzip --best`
- [x] Arquivo final salvo em `BACKUP_DIR` (default: `./backups/`)
- [x] Verifica integridade após gerar: `pg_restore --list` via pipe (exit code 0 = íntegro)
- [x] Remove backups mais antigos que `RETAIN_DAYS` (default: 7)
- [x] Log de cada passo com timestamp (logs via stderr para não poluir output capturado)
- [x] Suporte a flag `--output-dir <path>` para destino customizado
- [x] Suporte a flag `--retain-days <N>` para retenção customizada
- [x] Se `BACKUP_DIR` não existe, cria automaticamente
- [x] Trata falha do pg_dump com mensagem clara e exit code != 0

### restore.sh
- [x] Shebang `#!/usr/bin/env bash` com `set -euo pipefail`
- [x] Argumento obrigatório: caminho do arquivo `.dump` ou `.dump.gz`
- [x] Se `.gz`, faz `gunzip` para pipe (sem arquivo temporário)
- [x] `pg_restore` com `--clean --if-exists --no-owner --no-acl --single-transaction`
- [x] **Confirmação interativa:** lista conteúdo + tipo "YES" para prosseguir
- [x] Suporte a flag `--force` para pular confirmação (uso em scripts)
- [x] Suporte a flag `--dry-run` para só listar conteúdo sem restaurar
- [x] Verifica compatibilidade de versão PostgreSQL (major version match)
- [x] Após restore, dispara `NOTIFY pgrst, 'reload schema'` para atualizar PostgREST
- [x] Trata erros: arquivo não encontrado, formato inválido, container offline

## Contexto Técnico

- **Arquivos criados:** `scripts/backup.sh`, `scripts/restore.sh`
- **Referências:** `docs/architecture.md` seção 8 (estratégia de backup)
- **Nota:** Usa `supabase_admin` (não `postgres`) — é o superuser na imagem Supabase PostgreSQL
- **Nota:** pg_restore na imagem Supabase não aceita `-` como alias de stdin; dados via pipe sem argumento de arquivo
- **Nota:** Dump binário NÃO pode ser armazenado em variável shell (corrompe null bytes). Usamos pipes diretos com funções `cat_backup()` e `pg_restore_data()`

## Definition of Done

- [x] `scripts/backup.sh` criado e executável
- [x] `scripts/restore.sh` criado e executável
- [x] Backup testado com ambiente rodando: gera arquivo (1088 bytes raw → 503 bytes gz), verifica integridade
- [x] Restore --dry-run testado: lista conteúdo, mostra summary, zero alterações
- [x] Retenção testada: backups de 28 e 14 dias removidos, backups recentes mantidos
- [x] Erro tratado: arquivo inválido → "Unexpected file header", container offline → mensagem clara
- [x] Dry-run do restore lista conteúdo sem alterar nada
