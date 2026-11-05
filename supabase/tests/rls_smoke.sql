-- Teste de fumaça das regras de acesso (RLS). Roda num banco com a migration aplicada.
-- Uso local: psql -v ON_ERROR_STOP=1 -f supabase/tests/rls_smoke.sql (dentro de uma transação, nada fica salvo)
begin;

-- Usuários de login (simulando auth.users)
insert into auth.users (id, phone) values
  ('00000000-0000-0000-0000-00000000000a', '5511900000001'),  -- plataforma
  ('00000000-0000-0000-0000-00000000000b', '5511900000002'),  -- admin Albert
  ('00000000-0000-0000-0000-00000000000c', '5511900000003'),  -- morador
  ('00000000-0000-0000-0000-00000000000d', '5511900000004'),  -- profissional
  ('00000000-0000-0000-0000-00000000000e', '5511900000005');  -- admin de outro condomínio
insert into public.plataforma_admins values ('00000000-0000-0000-0000-00000000000a');

insert into public.condominios (id, nome, slug) values
  ('10000000-0000-0000-0000-000000000001', 'Albert 282', 'albert-282'),
  ('10000000-0000-0000-0000-000000000002', 'Outro', 'outro');

-- Pessoas cadastradas antes do login devem ser ligadas pelo telefone
insert into public.pessoas (id, telefone, nome) values
  ('20000000-0000-0000-0000-00000000000b', '5511900000002', 'Admin'),
  ('20000000-0000-0000-0000-00000000000c', '5511900000003', 'Morador'),
  ('20000000-0000-0000-0000-00000000000d', '5511900000004', 'Maria'),
  ('20000000-0000-0000-0000-00000000000e', '5511900000005', 'Admin Outro');
do $$ begin
  assert (select count(*) from public.pessoas where user_id is not null) = 4, 'pessoas não ligadas ao login';
end $$;

insert into public.vinculos (condominio_id, pessoa_id, papel) values
  ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-00000000000b', 'admin'),
  ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-00000000000c', 'morador'),
  ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-00000000000d', 'profissional'),
  ('10000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-00000000000e', 'admin');

-- Como admin do Albert: gera unidades, cria serviço e profissional
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
do $$ begin
  assert public.gerar_unidades('10000000-0000-0000-0000-000000000001', array['Bloco 1','Bloco 2'], 17, 8) = 272,
    'deveria gerar 272 unidades';
end $$;
insert into public.servicos (id, condominio_id, nome, preco) values
  ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Arrumadeira', 75);
insert into public.profissionais (id, condominio_id, pessoa_id, nome_exibicao) values
  ('40000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-00000000000d', 'Maria');
insert into public.unidade_moradores (unidade_id, pessoa_id, condominio_id)
  select id, '20000000-0000-0000-0000-00000000000c', condominio_id from public.unidades where numero = '1704'
   and bloco_id = (select id from public.blocos where nome = 'Bloco 1');

-- Admin de outro condomínio não vê nada do Albert
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000e';
do $$ begin
  assert (select count(*) from public.unidades) = 0, 'vazou unidades para outro condomínio';
  assert (select count(*) from public.condominios) = 1, 'deveria ver só o próprio condomínio';
  assert (select count(*) from public.pessoas where nome = 'Morador') = 0, 'vazou pessoa';
end $$;
do $$ begin
  begin
    perform public.gerar_unidades('10000000-0000-0000-0000-000000000001', array['X'], 1, 1);
    raise exception 'deveria negar';
  exception when insufficient_privilege then null;
  end;
end $$;

-- Morador: vê serviços/profissionais, pede serviço só para a própria unidade
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
do $$ begin
  assert (select count(*) from public.servicos) = 1, 'morador deveria ver serviços';
  assert (select count(*) from public.profissionais) = 1, 'morador deveria ver profissionais';
end $$;
insert into public.agendamentos (condominio_id, unidade_id, solicitante_id, servico_id, profissional_id, data, periodo_preferido)
  select '10000000-0000-0000-0000-000000000001', um.unidade_id, '20000000-0000-0000-0000-00000000000c',
         '30000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', current_date + 3, 'tanto_faz'
    from public.unidade_moradores um;
do $$ begin
  assert (select count(*) from public.agendamentos) = 1, 'morador deveria ver o próprio pedido';
  -- tentar pedir para outra unidade
  begin
    insert into public.agendamentos (condominio_id, unidade_id, solicitante_id, servico_id, profissional_id, data, periodo_preferido)
      select '10000000-0000-0000-0000-000000000001', u.id, '20000000-0000-0000-0000-00000000000c',
             '30000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', current_date + 3, 'manha'
        from public.unidades u where u.numero = '101' limit 1;
    raise exception 'morador pediu para unidade alheia';
  exception when insufficient_privilege then null;
  end;
  -- morador não confirma sozinho
  update public.agendamentos set status = 'confirmado', periodo = 'manha', preco = 75;
  assert (select status from public.agendamentos) = 'solicitado', 'morador não pode confirmar';
end $$;

-- Profissional não vê pedido ainda não confirmado
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
do $$ begin
  assert (select count(*) from public.agendamentos) = 0, 'profissional viu pedido não confirmado';
end $$;

-- Admin confirma; segunda reserva na mesma vaga é bloqueada
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
update public.agendamentos set status = 'confirmado', periodo = 'manha', preco = 75, confirmado_em = now();
do $$ begin
  begin
    insert into public.agendamentos (condominio_id, unidade_id, servico_id, profissional_id, data, periodo_preferido, periodo, status, preco)
      select condominio_id, unidade_id, servico_id, profissional_id, data, 'manha', 'manha', 'confirmado', 75
        from public.agendamentos limit 1;
    raise exception 'permitiu duas reservas na mesma vaga';
  exception when unique_violation then null;
  end;
end $$;

-- Agora o profissional enxerga, mas não altera
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
do $$ begin
  assert (select count(*) from public.agendamentos) = 1, 'profissional deveria ver confirmado';
  update public.agendamentos set status = 'cancelado';
  assert (select status from public.agendamentos) = 'confirmado', 'profissional não pode alterar';
end $$;

reset role;
rollback;
\echo 'RLS OK'
