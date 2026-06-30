# Story 10 — EasyPanel Template (template.json) ✅

**Como** administrador do EasyPanel,
**quero** um template.json que define o Supabase como um serviço de 1 click,
**para** que qualquer pessoa possa implantar o ambiente sem configurar nada manualmente.

## Critérios de Aceitação

- [x] `template.json` na raiz do projeto com metadados (nome, versão, descrição, categorias, licença, ícone)
- [x] Lista de 12 serviços com nome e descrição
- [x] 8 variáveis de template: SUPABASE_PUBLIC_URL, STUDIO_URL, CLOUDFLARE_TUNNEL_TOKEN, POSTGRES_PASSWORD, JWT_SECRET, SMTP_HOST, SMTP_USER, SMTP_PASS
- [x] Tipos corretos: string, password
- [x] Valores default e placeholders
- [x] Recursos mínimos: 4 CPU, 8 GB RAM, 20 GB disco
- [x] JSON válido (`python3 -c "import json; json.load(open('template.json'))"`)
- [ ] Testado no EasyPanel (requer deploy real)

## Contexto Técnico

- **Arquivo criado:** `template.json`
- **Nota:** Compatível com sistema de templates customizados do EasyPanel (suporte a variáveis {{ }})
- **Nota:** Secrets vazios no template para serem preenchidos no momento do deploy
