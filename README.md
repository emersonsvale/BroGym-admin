# BroGym Admin

Painel web da equipe do BroGym (`brogym-admin.valeapps.com.br`).

- Vue 3 + Vite, página estática servida por nginx (Dockerfile) no Coolify.
- Login: Google ou link no e-mail (mesma conta do app) + código de 2 etapas (TOTP) obrigatório.
- Segurança no banco: toda ação chama uma função `adm_*` do Supabase que confere equipe ativa,
  permissão do item e login com 2 etapas (`aal2`). Tudo que muda algo vai pro `admin_log`.
- Banco: `banco/20261119100000_admin.sql` (cópia; a original fica no repositório do app, em `supabase/migrations/`). Já aplicado no Supabase.
- Funções do servidor usadas: `delete-account` (apagar conta pelo painel) e o registro de custo da IA (`ia_registrar`) nas funções `ai-coach`, `diet-ai`, `refactor-workout` e `relatorio-semanal`.

## Deploy

Coolify (coo.valeapps.com.br), build pelo `Dockerfile`, porta 80. Push na `main` publica sozinho.

## Rodar local

```
npm install
npm run dev
```

O login com Google/link só volta pra endereços cadastrados em Supabase > Auth > URL Configuration.
