#!/usr/bin/env bash
# Aplica as migrations do AgendaServ (schema "agendaserv") num banco Postgres/Supabase.
# Não usa `supabase db push` porque o projeto Supabase é compartilhado com o iCaixa, que tem
# o próprio histórico de migrations; aqui o controle fica em agendaserv.migracoes.
#
# Uso: DATABASE_URL='postgresql://...' scripts/migrar.sh
set -euo pipefail
: "${DATABASE_URL:?defina DATABASE_URL}"
cd "$(dirname "$0")/.."

export PGOPTIONS="${PGOPTIONS:-} -c client_min_messages=warning"
PSQL=(psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -X)

"${PSQL[@]}" <<'SQL'
create schema if not exists agendaserv;
create table if not exists agendaserv.migracoes (
  versao text primary key,
  aplicada_em timestamptz not null default now()
);
alter table agendaserv.migracoes enable row level security;
revoke all on agendaserv.migracoes from anon, authenticated;
SQL

for arquivo in supabase/migrations/*.sql; do
  versao=$(basename "$arquivo" .sql)
  ja=$("${PSQL[@]}" -tA -c "select 1 from agendaserv.migracoes where versao = '$versao'")
  if [ "$ja" = "1" ]; then
    echo "já aplicada: $versao"
    continue
  fi
  echo "aplicando:   $versao"
  "${PSQL[@]}" -1 -f "$arquivo" -c "insert into agendaserv.migracoes (versao) values ('$versao'); revoke all on agendaserv.migracoes from anon, authenticated;"
done
