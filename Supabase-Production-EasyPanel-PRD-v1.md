# Supabase Production for EasyPanel

> Documento de Arquitetura e PRD (Versão 1.0)

## 1. Objetivo

Implantar um ambiente Supabase self-hosted otimizado para EasyPanel,
Oracle Cloud e Cloudflare Tunnel.

## 2. Arquitetura

``` text
Internet
   │
Cloudflare DNS
   │
Cloudflare Tunnel
   │
EasyPanel
   │
├── Kong (8000)
├── Studio (3000)
├── Auth
├── PostgREST
├── Storage
├── Realtime
├── Meta
├── Supavisor
├── PostgreSQL
└── ImgProxy
```

## 3. Domínios

-   supabase.mlluizdevtech.com.br → Kong
-   studio.mlluizdevtech.com.br → Studio

## 4. Objetivos Funcionais

-   Deploy em um clique no EasyPanel
-   Cloudflare Tunnel
-   HTTPS
-   Backup automático
-   Atualização com rollback
-   Healthchecks
-   Logs centralizados

## 5. Estrutura do Projeto

``` text
supabase-production/
├── docker-compose.yml
├── docker-compose.prod.yml
├── .env.example
├── scripts/
├── docs/
├── postgres/
├── kong/
├── monitoring/
└── backups/
```

## 6. Serviços

-   PostgreSQL 15
-   Kong
-   Studio
-   GoTrue
-   PostgREST
-   Storage
-   Realtime
-   Meta
-   Supavisor
-   ImgProxy
-   Vector

Não incluir: - Analytics - Logflare

## 7. Segurança

Gerar automaticamente: - JWT_SECRET - POSTGRES_PASSWORD -
SECRET_KEY_BASE - VAULT_SECRET - ANON_KEY - SERVICE_ROLE_KEY

## 8. Backup

-   pg_dump diário
-   Compressão gzip
-   Retenção configurável
-   Restore por script

## 9. Cloudflare Tunnel

Ingress: - supabase.mlluizdevtech.com.br -\> http://localhost:8000 -
studio.mlluizdevtech.com.br -\> http://localhost:3000

## 10. Roadmap

### Fase 1

-   Infraestrutura
-   Compose
-   Scripts
-   Documentação

### Fase 2

-   Interface administrativa em Go
-   Atualizações automáticas
-   Monitoramento

### Fase 3

-   Template oficial EasyPanel
-   Publicação GitHub
-   Releases versionadas

## 11. Checklist Produção

-   [ ] DNS configurado
-   [ ] Tunnel criado
-   [ ] Secrets gerados
-   [ ] Backup testado
-   [ ] Restore testado
-   [ ] SMTP configurado
-   [ ] OAuth configurado
-   [ ] Healthchecks OK

## 12. Próximos Artefatos

-   docker-compose.yml
-   .env.example
-   install.sh
-   update.sh
-   backup.sh
-   restore.sh
-   generate-secrets.sh
-   README.md
-   documentação completa
