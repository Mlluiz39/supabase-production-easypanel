# Story 11 — GitHub Release Structure ✅

**Como** mantenedor do projeto,
**quero** uma estrutura pronta para publicar releases versionadas no GitHub,
**para** que usuários possam acompanhar mudanças e baixar versões específicas.

## Critérios de Aceitação

- [x] `LICENSE` — MIT License com ano e autor corretos
- [x] `CHANGELOG.md` — formato Keep a Changelog + Semantic Versioning
- [x] Versão inicial `1.0.0` documentando Fase 1 e Fase 2
- [x] `.github/workflows/release.yml` — workflow que cria Release automaticamente ao push de tag `v*.*.*`
- [x] Release inclui artifacts: template.json, docker-compose.yml, .env.example, LICENSE
- [x] Release notes geradas automaticamente (CHANGELOG.md na primeira, git log nas subsequentes)

## Contexto Técnico

- **Arquivos criados:** `LICENSE`, `CHANGELOG.md`, `.github/workflows/release.yml`
- **Convenção de versão:** SemVer (v1.0.0, v1.1.0, v2.0.0)
- **Trigger:** `git tag v1.0.0 && git push origin v1.0.0`
