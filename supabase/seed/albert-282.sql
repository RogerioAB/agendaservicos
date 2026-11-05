-- Cadastro inicial do condomínio Albert 282.
-- Rodar UMA vez no SQL Editor do Supabase (como postgres), depois das migrations.
-- Troque o celular do gestor antes de rodar (só dígitos, com 55 + DDD).
do $$
declare
  v_condo uuid;
  v_gestor uuid;
  v_bloco uuid;
  b record;
  celular_gestor constant text := '5511999999999';  -- TROCAR
begin
  insert into public.condominios (nome, slug, cidade, uf)
  values ('Albert 282', 'albert-282', null, null)
  returning id into v_condo;

  -- Blocos e unidades: 2 blocos x 17 andares x 8 apartamentos (101..1708)
  for b in select * from (values ('Bloco 1', 1), ('Bloco 2', 2)) as t(nome, ordem) loop
    insert into public.blocos (condominio_id, nome, ordem) values (v_condo, b.nome, b.ordem) returning id into v_bloco;
    insert into public.unidades (condominio_id, bloco_id, andar, numero)
    select v_condo, v_bloco, a, (a * 100 + n)::text
      from generate_series(1, 17) a, generate_series(1, 8) n;
  end loop;

  -- Serviços e preços iniciais (editáveis depois pela administração)
  insert into public.servicos (condominio_id, nome, preco) values
    (v_condo, 'Arrumadeira', 75),
    (v_condo, 'Encanador', 50),
    (v_condo, 'Eletricista', 40),
    (v_condo, 'Lavagem de carro', 50);

  -- Gestor do condomínio
  insert into public.pessoas (telefone, nome) values (celular_gestor, 'Gestor Albert 282')
    on conflict (telefone) do update set nome = public.pessoas.nome
    returning id into v_gestor;
  insert into public.vinculos (condominio_id, pessoa_id, papel) values (v_condo, v_gestor, 'admin');

  raise notice 'Condomínio % criado com % unidades', v_condo,
    (select count(*) from public.unidades where condominio_id = v_condo);
end $$;
