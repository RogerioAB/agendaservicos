# AgendaServ

Agendamento de serviços em condomínios (arrumadeira, encanador, eletricista, lavagem de carro…).
O morador pede o serviço escolhendo profissional, data e período; a administração do condomínio aprova,
recusa ou sugere outra opção; o morador recebe os avisos pelo WhatsApp.

Produção: https://agendaserv.zarpa.tech

## Stack

React 19 + Vite + TypeScript + Tailwind v4 (PWA, mobile-first), Supabase (Postgres + RLS + Auth por celular +
Storage + Edge Functions), WhatsApp via Evolution API, deploy com Docker + nginx no Coolify.

## Rodar localmente

```bash
npm install
cp .env.example .env   # preencher com a URL e a anon key do projeto Supabase
npm run dev
```

Scripts: `npm run dev`, `npm run build`, `npm run lint`, `npm test`.

## Banco de dados

O AgendaServ usa o **mesmo projeto Supabase do iCaixa**, num schema próprio: `agendaserv`. Tabelas, funções,
bucket (`agendaserv-logos`) e triggers têm nome próprio, e nada toca nas tabelas do iCaixa. O cadastro de
usuários (`auth.users`) é compartilhado entre os dois apps.

Para a API enxergar o schema: Supabase → Settings → API → **Exposed schemas** → adicionar `agendaserv`.

- `supabase/migrations/` — esquema, regras de acesso (RLS) e funções.
- `scripts/migrar.sh` — aplica as migrations ainda não aplicadas (controle em `agendaserv.migracoes`).
  Não usamos `supabase db push` para não misturar com o histórico de migrations do iCaixa.
- `supabase/tests/rls_smoke.sql` — testes das permissões de cada perfil (rodam no CI num Postgres comum,
  com `supabase/tests/supabase_stub.sql` simulando o Supabase).
- `supabase/seed/albert-282.sql` — cadastro inicial do Albert 282 (272 unidades e os 4 serviços com preço).
  Rodar uma vez no SQL Editor, depois de trocar o celular do gestor.

Perfis: **plataforma** (dono do SaaS, tabela `plataforma_admins`), **admin** do condomínio, **morador** e
**profissional**, todos ligados a `pessoas` pelo celular. A administração cadastra a pessoa pelo celular; quando
ela entra pela primeira vez, o login é ligado automaticamente.

### Publicar no Supabase

O workflow `.github/workflows/supabase.yml` roda `scripts/migrar.sh` a cada push na `main` que mexa em
migrations. Configure no GitHub o secret `SUPABASE_DB_URL` com a connection string do **Session pooler**
(Supabase → Connect), incluindo a senha do banco.

Depois do primeiro deploy, cadastre seu usuário como dono da plataforma no SQL Editor:

```sql
insert into agendaserv.plataforma_admins (user_id)
select id from auth.users where phone = '55DDDNUMERO';
```

## Deploy (Coolify)

Dockerfile multi-stage (build Vite + nginx). Em Coolify, `VITE_SUPABASE_URL` e `VITE_SUPABASE_ANON_KEY`
devem ser **Build Variables** (o bundle é gerado em tempo de build). Domínio: `agendaserv.zarpa.tech`.
Lembre de incluir esse domínio em Auth → URL Configuration no Supabase.

## Roadmap

1. Projeto base, banco e RLS ← **esta fase**
2. Login por celular com código via WhatsApp
3. Cadastros (condomínio, unidades, moradores, serviços, profissionais, agenda de trabalho, feriados)
4. Busca de disponibilidade e pedido do morador
5. Painel da administração e agenda do profissional
6. Avisos por WhatsApp (confirmação, sugestão, cancelamento, lembrete da véspera)
7. Relatório mensal com exportação
