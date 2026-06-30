# Story 12 — CI/CD com GitHub Actions ✅

**Como** mantenedor do projeto,
**quero** pipelines automatizados que validam compose, scripts, build, template e segurança,
**para** garantir que cada PR e push mantenha a qualidade do projeto.

## Critérios de Aceitação

### CI (Push/PR na main)
- [x] **validate-compose:** cria .env, valida `docker compose config` (com e sem profiles)
- [x] **lint-scripts:** shellcheck em todos os `.sh`, bash -n syntax check
- [x] **build-admin:** go build + docker build do Go service
- [x] **validate-template:** JSON schema validation do template.json
- [x] **security-scan:** gitleaks + verificação de secrets placeholder
- [x] **lint-docs:** markdownlint no README.md
- [x] **summary:** tabela de resultados consolidada

### Release (Push de tag v*.*.*)
- [x] Cria GitHub Release automaticamente
- [x] Gera release notes (CHANGELOG.md ou git log)
- [x] Anexa artifacts: template.json, docker-compose.yml, .env.example, LICENSE

### Configuração
- [x] Concorrência configurada (cancel-in-progress)
- [x] Paths-ignore para docs/ e .md (não acionam CI desnecessário)
- [x] Continue-on-error para gitleaks (não bloqueia CI)

## Contexto Técnico

- **Arquivos criados:** `.github/workflows/ci.yml`, `.github/workflows/release.yml`
- **Nota:** Gitleaks pode falar em secrets do .env.example (esperado — `changeme` é intencional)
