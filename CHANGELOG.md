# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-06-29

### Added

- **Fase 1 — Infraestrutura Base**
  - Docker Compose com 13 serviços (PostgreSQL 17, Kong, GoTrue, PostgREST, Realtime, Storage, ImgProxy, Meta, Edge Functions, Studio, Supavisor, Vector, Cloudflared)
  - Rede Docker interna, 5 volumes nomeados, healthchecks em todos os serviços
  - `.env.example` com 57 variáveis documentadas em 13 seções
  - `generate-secrets.sh`: gera 9 secrets criptográficos (openssl + JWTs HS256)
  - `install.sh`: bootstrap completo (prerequisites → secrets → validate → up → healthy)
  - `backup.sh`: pg_dump custom → gzip → integrity check → retention (7 dias)
  - `restore.sh`: gunzip pipe → pg_restore → confirm → NOTIFY pgrst
  - README completo com Quick Start de 5 passos

- **Fase 2 — Gestão e Monitoramento**
  - `update.sh`: pull → backup → restart → healthcheck → rollback automático (git tag)
  - Prometheus + Grafana (+ node-exporter, postgres-exporter, profile `monitoring`)
  - Alertmanager com 8 regras de alerta (disco, serviços, PostgreSQL, Kong, backup)
  - `test-alert.sh`: dispara alerta de teste no Alertmanager
  - Painel Admin Go (Docker multi-stage ~10 MB, profile `admin`)
  - Rota `/admin` no Kong para o painel de status
  - Flag `--monitoring` no `install.sh`

### Infrastructure

- Otimizado para Oracle Cloud ARM Ampere (4 vCPU, 24 GB RAM, 200 GB)
- Cloudflare Tunnel como única entrada externa (zero portas expostas)
- Arquitetura documentada com 7 ADRs
