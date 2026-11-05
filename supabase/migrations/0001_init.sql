-- AgendaServ — esquema inicial
-- Tudo fica no schema "agendaserv", que convive no mesmo projeto Supabase do iCaixa.
-- auth.users é compartilhado entre os apps; nada aqui altera tabelas do iCaixa.
-- Multi-condomínio: toda tabela de negócio tem condominio_id e é isolada por RLS.
-- Login por celular (Supabase Phone Auth): auth.users.phone guarda só dígitos, ex. '5511987654321'.

create schema if not exists agendaserv;
grant usage on schema agendaserv to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Tipos
-- ---------------------------------------------------------------------------
create type agendaserv.papel as enum ('admin', 'morador', 'profissional');
create type agendaserv.periodo as enum ('manha', 'tarde');
create type agendaserv.periodo_preferido as enum ('manha', 'tarde', 'tanto_faz');
create type agendaserv.status_agendamento as enum (
  'solicitado',  -- morador pediu, aguardando a administração
  'sugerido',    -- administração recusou e sugeriu outra data/profissional
  'confirmado',  -- vaga reservada
  'recusado',    -- administração recusou sem alternativa (ou morador recusou a sugestão)
  'cancelado',   -- cancelado pelo morador (até 24h antes) ou pela administração
  'realizado',   -- serviço feito (entra no relatório)
  'falta'        -- profissional não compareceu / serviço não aconteceu
);

-- ---------------------------------------------------------------------------
-- Utilitário: updated_at automático
-- ---------------------------------------------------------------------------
create or replace function agendaserv.tg_set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ---------------------------------------------------------------------------
-- Plataforma (dono do SaaS)
-- ---------------------------------------------------------------------------
create table agendaserv.plataforma_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Condomínios
-- ---------------------------------------------------------------------------
create table agendaserv.condominios (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  slug text not null unique check (slug ~ '^[a-z0-9-]+$'),
  endereco text,
  cidade text,
  uf char(2),
  cep text,
  responsavel_nome text,
  responsavel_telefone text,
  logo_path text,                                  -- caminho no bucket "logos"
  fuso_horario text not null default 'America/Sao_Paulo',
  ativo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger condominios_updated_at before update on agendaserv.condominios
  for each row execute function agendaserv.tg_set_updated_at();

-- ---------------------------------------------------------------------------
-- Pessoas: cadastradas pela administração pelo celular, antes de existir login.
-- Quando a pessoa entra pela primeira vez, user_id é ligado automaticamente (trigger abaixo).
-- ---------------------------------------------------------------------------
create table agendaserv.pessoas (
  id uuid primary key default gen_random_uuid(),
  telefone text not null unique check (telefone ~ '^55[0-9]{10,11}$'),
  nome text not null,
  user_id uuid unique references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger pessoas_updated_at before update on agendaserv.pessoas
  for each row execute function agendaserv.tg_set_updated_at();

-- Papel de uma pessoa em um condomínio (pode ter mais de um).
create table agendaserv.vinculos (
  id uuid primary key default gen_random_uuid(),
  condominio_id uuid not null references agendaserv.condominios(id) on delete cascade,
  pessoa_id uuid not null references agendaserv.pessoas(id) on delete cascade,
  papel agendaserv.papel not null,
  ativo boolean not null default true,
  created_at timestamptz not null default now(),
  unique (condominio_id, pessoa_id, papel)
);
create index vinculos_pessoa_idx on agendaserv.vinculos (pessoa_id);

-- ---------------------------------------------------------------------------
-- Estrutura física
-- ---------------------------------------------------------------------------
create table agendaserv.blocos (
  id uuid primary key default gen_random_uuid(),
  condominio_id uuid not null references agendaserv.condominios(id) on delete cascade,
  nome text not null,
  ordem int not null default 0,
  unique (condominio_id, nome),
  unique (id, condominio_id)
);

create table agendaserv.unidades (
  id uuid primary key default gen_random_uuid(),
  condominio_id uuid not null,
  bloco_id uuid not null,
  andar int not null,
  numero text not null,                            -- ex.: '1704'
  ativo boolean not null default true,
  foreign key (bloco_id, condominio_id) references agendaserv.blocos(id, condominio_id) on delete cascade,
  unique (bloco_id, numero),
  unique (id, condominio_id)
);
create index unidades_condominio_idx on agendaserv.unidades (condominio_id);

create table agendaserv.unidade_moradores (
  unidade_id uuid not null,
  pessoa_id uuid not null references agendaserv.pessoas(id) on delete cascade,
  condominio_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (unidade_id, pessoa_id),
  foreign key (unidade_id, condominio_id) references agendaserv.unidades(id, condominio_id) on delete cascade
);
create index unidade_moradores_pessoa_idx on agendaserv.unidade_moradores (pessoa_id);

-- ---------------------------------------------------------------------------
-- Serviços e profissionais
-- ---------------------------------------------------------------------------
create table agendaserv.servicos (
  id uuid primary key default gen_random_uuid(),
  condominio_id uuid not null references agendaserv.condominios(id) on delete cascade,
  nome text not null,
  descricao text,
  preco numeric(10,2) not null check (preco >= 0),
  ativo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (condominio_id, nome),
  unique (id, condominio_id)
);
create trigger servicos_updated_at before update on agendaserv.servicos
  for each row execute function agendaserv.tg_set_updated_at();

create table agendaserv.profissionais (
  id uuid primary key default gen_random_uuid(),
  condominio_id uuid not null references agendaserv.condominios(id) on delete cascade,
  pessoa_id uuid not null references agendaserv.pessoas(id) on delete restrict,
  nome_exibicao text not null,                     -- nome que o morador vê
  ativo boolean not null default true,
  created_at timestamptz not null default now(),
  unique (condominio_id, pessoa_id),
  unique (id, condominio_id)
);

-- Habilidades: quais serviços cada profissional presta.
create table agendaserv.profissional_servicos (
  profissional_id uuid not null,
  servico_id uuid not null,
  condominio_id uuid not null,
  primary key (profissional_id, servico_id),
  foreign key (profissional_id, condominio_id) references agendaserv.profissionais(id, condominio_id) on delete cascade,
  foreign key (servico_id, condominio_id) references agendaserv.servicos(id, condominio_id) on delete cascade
);

-- Dias/períodos em que o profissional trabalha (linha existe = trabalha). 0 = domingo … 6 = sábado.
create table agendaserv.disponibilidade_semanal (
  profissional_id uuid not null,
  condominio_id uuid not null,
  dia_semana smallint not null check (dia_semana between 0 and 6),
  periodo agendaserv.periodo not null,
  primary key (profissional_id, dia_semana, periodo),
  foreign key (profissional_id, condominio_id) references agendaserv.profissionais(id, condominio_id) on delete cascade
);

-- Folgas, férias, ausências pontuais. periodo null = dia inteiro.
create table agendaserv.bloqueios (
  id uuid primary key default gen_random_uuid(),
  profissional_id uuid not null,
  condominio_id uuid not null,
  data date not null,
  periodo agendaserv.periodo,
  motivo text,
  created_at timestamptz not null default now(),
  foreign key (profissional_id, condominio_id) references agendaserv.profissionais(id, condominio_id) on delete cascade
);
create index bloqueios_prof_data_idx on agendaserv.bloqueios (profissional_id, data);

-- Feriados bloqueiam a agenda, exceto para profissionais liberados.
create table agendaserv.feriados (
  id uuid primary key default gen_random_uuid(),
  condominio_id uuid not null references agendaserv.condominios(id) on delete cascade,
  data date not null,
  nome text not null,
  unique (condominio_id, data),
  unique (id, condominio_id)
);

create table agendaserv.feriado_liberacoes (
  feriado_id uuid not null,
  profissional_id uuid not null,
  condominio_id uuid not null,
  primary key (feriado_id, profissional_id),
  foreign key (feriado_id, condominio_id) references agendaserv.feriados(id, condominio_id) on delete cascade,
  foreign key (profissional_id, condominio_id) references agendaserv.profissionais(id, condominio_id) on delete cascade
);

-- ---------------------------------------------------------------------------
-- Agendamentos
-- ---------------------------------------------------------------------------
create table agendaserv.agendamentos (
  id uuid primary key default gen_random_uuid(),
  condominio_id uuid not null references agendaserv.condominios(id) on delete cascade,
  unidade_id uuid not null,
  solicitante_id uuid references agendaserv.pessoas(id) on delete set null,
  servico_id uuid not null,
  profissional_id uuid not null,
  data date not null,
  periodo_preferido agendaserv.periodo_preferido not null,
  periodo agendaserv.periodo,                          -- período final; obrigatório a partir de confirmado
  status agendaserv.status_agendamento not null default 'solicitado',
  preco numeric(10,2),                             -- copiado do serviço na confirmação
  observacao text,                                 -- recado do morador
  motivo text,                                     -- motivo da recusa/cancelamento
  sugestao_data date,
  sugestao_periodo agendaserv.periodo,
  sugestao_profissional_id uuid,
  confirmado_em timestamptz,
  cancelado_em timestamptz,
  cancelado_por uuid references agendaserv.pessoas(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (unidade_id, condominio_id) references agendaserv.unidades(id, condominio_id) on delete restrict,
  foreign key (servico_id, condominio_id) references agendaserv.servicos(id, condominio_id) on delete restrict,
  foreign key (profissional_id, condominio_id) references agendaserv.profissionais(id, condominio_id) on delete restrict,
  foreign key (sugestao_profissional_id, condominio_id) references agendaserv.profissionais(id, condominio_id) on delete set null (sugestao_profissional_id),
  constraint periodo_quando_reservado check (
    status not in ('confirmado', 'realizado', 'falta') or (periodo is not null and preco is not null)
  ),
  constraint periodo_coerente check (
    periodo is null or periodo_preferido = 'tanto_faz' or periodo::text = periodo_preferido::text
    or status in ('confirmado', 'realizado', 'falta', 'cancelado')  -- administração pode ajustar
  ),
  constraint sugestao_completa check (
    status <> 'sugerido' or (sugestao_data is not null or sugestao_profissional_id is not null)
  )
);
create trigger agendamentos_updated_at before update on agendaserv.agendamentos
  for each row execute function agendaserv.tg_set_updated_at();

-- Um profissional nunca tem dois serviços reservados no mesmo período.
create unique index agendamentos_vaga_unica
  on agendaserv.agendamentos (profissional_id, data, periodo)
  where status in ('confirmado', 'realizado');

create index agendamentos_condominio_data_idx on agendaserv.agendamentos (condominio_id, data);
create index agendamentos_unidade_idx on agendaserv.agendamentos (unidade_id, data desc);
create index agendamentos_profissional_idx on agendaserv.agendamentos (profissional_id, data);

-- ---------------------------------------------------------------------------
-- Log de notificações (WhatsApp). Escrito só pelas Edge Functions (service role).
-- ---------------------------------------------------------------------------
create table agendaserv.notificacoes (
  id uuid primary key default gen_random_uuid(),
  condominio_id uuid not null references agendaserv.condominios(id) on delete cascade,
  agendamento_id uuid references agendaserv.agendamentos(id) on delete cascade,
  tipo text not null,                              -- 'confirmacao', 'sugestao', 'cancelamento', 'lembrete', ...
  telefone text not null,
  status text not null default 'pendente' check (status in ('pendente', 'enviado', 'erro')),
  erro text,
  enviado_em timestamptz,
  created_at timestamptz not null default now()
);
create unique index notificacoes_lembrete_unico
  on agendaserv.notificacoes (agendamento_id, tipo) where tipo = 'lembrete';

-- ---------------------------------------------------------------------------
-- Ligação automática pessoa <-> login, pelo celular
-- ---------------------------------------------------------------------------
-- Este trigger roda para todo usuário do projeto (inclusive do iCaixa). Ele nunca pode
-- quebrar um cadastro: qualquer erro aqui é engolido e só gera um aviso no log.
create or replace function agendaserv.tg_ligar_pessoa_ao_usuario()
returns trigger language plpgsql security definer set search_path = agendaserv as $$
begin
  if new.phone is not null then
    begin
      update agendaserv.pessoas set user_id = new.id
       where telefone = new.phone and user_id is null;
    exception when others then
      raise warning 'agendaserv: falha ao ligar pessoa ao usuário %: %', new.id, sqlerrm;
    end;
  end if;
  return new;
end $$;

create trigger agendaserv_ligar_pessoa_ao_usuario
  after insert or update of phone on auth.users
  for each row execute function agendaserv.tg_ligar_pessoa_ao_usuario();

create or replace function agendaserv.tg_ligar_usuario_a_pessoa()
returns trigger language plpgsql security definer set search_path = agendaserv as $$
begin
  if new.user_id is null then
    select u.id into new.user_id from auth.users u where u.phone = new.telefone;
  end if;
  return new;
end $$;

create trigger agendaserv_ligar_usuario_a_pessoa
  before insert or update of telefone on agendaserv.pessoas
  for each row execute function agendaserv.tg_ligar_usuario_a_pessoa();

-- ---------------------------------------------------------------------------
-- Funções auxiliares de autorização (security definer para não recursar no RLS)
-- ---------------------------------------------------------------------------
create or replace function agendaserv.eh_plataforma_admin()
returns boolean language sql stable security definer set search_path = agendaserv as $$
  select exists (select 1 from agendaserv.plataforma_admins where user_id = auth.uid())
$$;

create or replace function agendaserv.minha_pessoa_id()
returns uuid language sql stable security definer set search_path = agendaserv as $$
  select id from agendaserv.pessoas where user_id = auth.uid()
$$;

create or replace function agendaserv.tem_papel(p_condominio uuid, p_papel agendaserv.papel)
returns boolean language sql stable security definer set search_path = agendaserv as $$
  select exists (
    select 1 from agendaserv.vinculos v
      join agendaserv.pessoas p on p.id = v.pessoa_id
     where p.user_id = auth.uid()
       and v.condominio_id = p_condominio
       and v.papel = p_papel
       and v.ativo
  )
$$;

create or replace function agendaserv.eh_admin(p_condominio uuid)
returns boolean language sql stable security definer set search_path = agendaserv as $$
  select agendaserv.eh_plataforma_admin() or agendaserv.tem_papel(p_condominio, 'admin')
$$;

create or replace function agendaserv.eh_membro(p_condominio uuid)
returns boolean language sql stable security definer set search_path = agendaserv as $$
  select agendaserv.eh_plataforma_admin() or exists (
    select 1 from agendaserv.vinculos v
      join agendaserv.pessoas p on p.id = v.pessoa_id
     where p.user_id = auth.uid() and v.condominio_id = p_condominio and v.ativo
  )
$$;

create or replace function agendaserv.mora_na_unidade(p_unidade uuid)
returns boolean language sql stable security definer set search_path = agendaserv as $$
  select exists (
    select 1 from agendaserv.unidade_moradores um
      join agendaserv.pessoas p on p.id = um.pessoa_id
      join agendaserv.vinculos v on v.pessoa_id = p.id and v.condominio_id = um.condominio_id
                             and v.papel = 'morador' and v.ativo
     where p.user_id = auth.uid() and um.unidade_id = p_unidade
  )
$$;

create or replace function agendaserv.eh_o_profissional(p_profissional uuid)
returns boolean language sql stable security definer set search_path = agendaserv as $$
  select exists (
    select 1 from agendaserv.profissionais pr
      join agendaserv.pessoas p on p.id = pr.pessoa_id
     where p.user_id = auth.uid() and pr.id = p_profissional
  )
$$;

-- Admin do condomínio só enxerga/edita pessoas ligadas ao seu condomínio.
create or replace function agendaserv.pessoa_visivel(p_pessoa uuid)
returns boolean language sql stable security definer set search_path = agendaserv as $$
  select agendaserv.eh_plataforma_admin()
      or exists (select 1 from agendaserv.pessoas where id = p_pessoa and user_id = auth.uid())
      or exists (
        select 1 from agendaserv.vinculos v
         where v.pessoa_id = p_pessoa and agendaserv.tem_papel(v.condominio_id, 'admin')
      )
$$;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table agendaserv.plataforma_admins       enable row level security;
alter table agendaserv.condominios             enable row level security;
alter table agendaserv.pessoas                 enable row level security;
alter table agendaserv.vinculos                enable row level security;
alter table agendaserv.blocos                  enable row level security;
alter table agendaserv.unidades                enable row level security;
alter table agendaserv.unidade_moradores       enable row level security;
alter table agendaserv.servicos                enable row level security;
alter table agendaserv.profissionais           enable row level security;
alter table agendaserv.profissional_servicos   enable row level security;
alter table agendaserv.disponibilidade_semanal enable row level security;
alter table agendaserv.bloqueios               enable row level security;
alter table agendaserv.feriados                enable row level security;
alter table agendaserv.feriado_liberacoes      enable row level security;
alter table agendaserv.agendamentos            enable row level security;
alter table agendaserv.notificacoes            enable row level security;

-- plataforma_admins: cada um vê a si mesmo; gestão só via SQL/service role.
create policy plataforma_admins_select on agendaserv.plataforma_admins
  for select to authenticated using (user_id = auth.uid());

-- condominios
create policy condominios_select on agendaserv.condominios
  for select to authenticated using (agendaserv.eh_membro(id));
create policy condominios_insert on agendaserv.condominios
  for insert to authenticated with check (agendaserv.eh_plataforma_admin());
create policy condominios_update on agendaserv.condominios
  for update to authenticated using (agendaserv.eh_admin(id)) with check (agendaserv.eh_admin(id));
create policy condominios_delete on agendaserv.condominios
  for delete to authenticated using (agendaserv.eh_plataforma_admin());

-- pessoas: admins de qualquer condomínio podem cadastrar; o vínculo é que dá visibilidade.
create policy pessoas_select on agendaserv.pessoas
  for select to authenticated using (agendaserv.pessoa_visivel(id));
create policy pessoas_insert on agendaserv.pessoas
  for insert to authenticated with check (
    agendaserv.eh_plataforma_admin()
    or exists (select 1 from agendaserv.vinculos v join agendaserv.pessoas p on p.id = v.pessoa_id
                where p.user_id = auth.uid() and v.papel = 'admin' and v.ativo)
  );
create policy pessoas_update on agendaserv.pessoas
  for update to authenticated using (agendaserv.pessoa_visivel(id)) with check (agendaserv.pessoa_visivel(id));

-- vinculos
create policy vinculos_select on agendaserv.vinculos
  for select to authenticated using (pessoa_id = agendaserv.minha_pessoa_id() or agendaserv.eh_admin(condominio_id));
create policy vinculos_write on agendaserv.vinculos
  for all to authenticated using (agendaserv.eh_admin(condominio_id)) with check (agendaserv.eh_admin(condominio_id));

-- Tabelas de cadastro: membros leem, administração escreve.
create policy blocos_select on agendaserv.blocos for select to authenticated using (agendaserv.eh_membro(condominio_id));
create policy blocos_write  on agendaserv.blocos for all to authenticated
  using (agendaserv.eh_admin(condominio_id)) with check (agendaserv.eh_admin(condominio_id));

create policy unidades_select on agendaserv.unidades for select to authenticated using (agendaserv.eh_membro(condominio_id));
create policy unidades_write  on agendaserv.unidades for all to authenticated
  using (agendaserv.eh_admin(condominio_id)) with check (agendaserv.eh_admin(condominio_id));

create policy unidade_moradores_select on agendaserv.unidade_moradores for select to authenticated
  using (pessoa_id = agendaserv.minha_pessoa_id() or agendaserv.eh_admin(condominio_id));
create policy unidade_moradores_write on agendaserv.unidade_moradores for all to authenticated
  using (agendaserv.eh_admin(condominio_id)) with check (agendaserv.eh_admin(condominio_id));

create policy servicos_select on agendaserv.servicos for select to authenticated using (agendaserv.eh_membro(condominio_id));
create policy servicos_write  on agendaserv.servicos for all to authenticated
  using (agendaserv.eh_admin(condominio_id)) with check (agendaserv.eh_admin(condominio_id));

create policy profissionais_select on agendaserv.profissionais for select to authenticated using (agendaserv.eh_membro(condominio_id));
create policy profissionais_write  on agendaserv.profissionais for all to authenticated
  using (agendaserv.eh_admin(condominio_id)) with check (agendaserv.eh_admin(condominio_id));

create policy profissional_servicos_select on agendaserv.profissional_servicos for select to authenticated
  using (agendaserv.eh_membro(condominio_id));
create policy profissional_servicos_write on agendaserv.profissional_servicos for all to authenticated
  using (agendaserv.eh_admin(condominio_id)) with check (agendaserv.eh_admin(condominio_id));

create policy disponibilidade_select on agendaserv.disponibilidade_semanal for select to authenticated
  using (agendaserv.eh_membro(condominio_id));
create policy disponibilidade_write on agendaserv.disponibilidade_semanal for all to authenticated
  using (agendaserv.eh_admin(condominio_id)) with check (agendaserv.eh_admin(condominio_id));

create policy bloqueios_select on agendaserv.bloqueios for select to authenticated using (agendaserv.eh_membro(condominio_id));
create policy bloqueios_write  on agendaserv.bloqueios for all to authenticated
  using (agendaserv.eh_admin(condominio_id)) with check (agendaserv.eh_admin(condominio_id));

create policy feriados_select on agendaserv.feriados for select to authenticated using (agendaserv.eh_membro(condominio_id));
create policy feriados_write  on agendaserv.feriados for all to authenticated
  using (agendaserv.eh_admin(condominio_id)) with check (agendaserv.eh_admin(condominio_id));

create policy feriado_liberacoes_select on agendaserv.feriado_liberacoes for select to authenticated
  using (agendaserv.eh_membro(condominio_id));
create policy feriado_liberacoes_write on agendaserv.feriado_liberacoes for all to authenticated
  using (agendaserv.eh_admin(condominio_id)) with check (agendaserv.eh_admin(condominio_id));

-- agendamentos
--  * administração: tudo no seu condomínio
--  * morador: vê os da sua unidade; cria pedidos 'solicitado' em nome próprio.
--    Cancelar e aceitar sugestão serão RPCs (Fase 4/5) que validam a regra das 24h.
--  * profissional: só lê a própria agenda
create policy agendamentos_select on agendaserv.agendamentos for select to authenticated using (
  agendaserv.eh_admin(condominio_id)
  or agendaserv.mora_na_unidade(unidade_id)
  or (agendaserv.eh_o_profissional(profissional_id) and status in ('confirmado', 'realizado', 'falta'))
);
create policy agendamentos_insert_morador on agendaserv.agendamentos for insert to authenticated with check (
  agendaserv.mora_na_unidade(unidade_id)
  and solicitante_id = agendaserv.minha_pessoa_id()
  and status = 'solicitado'
  and periodo is null and preco is null
  and data > current_date
);
create policy agendamentos_admin_write on agendaserv.agendamentos for all to authenticated
  using (agendaserv.eh_admin(condominio_id)) with check (agendaserv.eh_admin(condominio_id));

-- notificacoes: só leitura para a administração.
create policy notificacoes_select on agendaserv.notificacoes for select to authenticated
  using (agendaserv.eh_admin(condominio_id));

-- ---------------------------------------------------------------------------
-- Gerar unidades em lote (ex.: 2 blocos x 17 andares x 8 aptos)
-- Numeração: andar * 100 + apto (101..108, ..., 1701..1708).
-- ---------------------------------------------------------------------------
create or replace function agendaserv.gerar_unidades(
  p_condominio uuid,
  p_blocos text[],
  p_andares int,
  p_aptos_por_andar int
) returns int language plpgsql security definer set search_path = agendaserv as $$
declare
  v_bloco text;
  v_bloco_id uuid;
  v_ordem int := 0;
  v_total int := 0;
  v_n int;
begin
  if not agendaserv.eh_admin(p_condominio) then
    raise exception 'sem permissão' using errcode = '42501';
  end if;
  if p_andares < 1 or p_aptos_por_andar < 1 or p_aptos_por_andar > 99 then
    raise exception 'parâmetros inválidos';
  end if;

  foreach v_bloco in array p_blocos loop
    v_ordem := v_ordem + 1;
    insert into agendaserv.blocos (condominio_id, nome, ordem) values (p_condominio, v_bloco, v_ordem)
      on conflict (condominio_id, nome) do update set ordem = excluded.ordem
      returning id into v_bloco_id;

    insert into agendaserv.unidades (condominio_id, bloco_id, andar, numero)
    select p_condominio, v_bloco_id, a, (a * 100 + n)::text
      from generate_series(1, p_andares) a, generate_series(1, p_aptos_por_andar) n
    on conflict (bloco_id, numero) do nothing;
    get diagnostics v_n = row_count;
    v_total := v_total + v_n;
  end loop;

  return v_total;
end $$;

revoke execute on function agendaserv.gerar_unidades(uuid, text[], int, int) from public, anon;
grant execute on function agendaserv.gerar_unidades(uuid, text[], int, int) to authenticated;

-- ---------------------------------------------------------------------------
-- Storage: logos dos condomínios (leitura pública; escrita pela administração).
-- Bucket com prefixo do app, para não colidir com os do iCaixa. Caminho: <condominio_id>/logo.<ext>
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('agendaserv-logos', 'agendaserv-logos', true)
on conflict (id) do nothing;

create policy agendaserv_logos_write on storage.objects for all to authenticated
  using (bucket_id = 'agendaserv-logos' and agendaserv.eh_admin(((storage.foldername(name))[1])::uuid))
  with check (bucket_id = 'agendaserv-logos' and agendaserv.eh_admin(((storage.foldername(name))[1])::uuid));

-- ---------------------------------------------------------------------------
-- Permissões do schema para a API do Supabase (o RLS continua decidindo as linhas).
-- Lembrete: incluir "agendaserv" em Settings → API → Exposed schemas.
-- ---------------------------------------------------------------------------
grant select, insert, update, delete on all tables in schema agendaserv to authenticated;
grant all on all tables in schema agendaserv to service_role;
grant execute on all functions in schema agendaserv to authenticated, service_role;
revoke execute on all functions in schema agendaserv from anon, public;
alter default privileges in schema agendaserv grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema agendaserv grant all on tables to service_role;
alter default privileges in schema agendaserv grant execute on functions to authenticated, service_role;
alter default privileges in schema agendaserv revoke execute on functions from public;
