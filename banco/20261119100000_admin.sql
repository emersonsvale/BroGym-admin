-- =====================================================================
-- BroGym Admin (painel web brogym-admin.valeapps.com.br)
--
-- Regra de ouro: a segurança mora aqui no banco, não na tela.
--  * Ninguém lê nem grava as tabelas do admin direto: só pelas funções adm_*.
--  * Toda função adm_* confere: (1) a pessoa está na equipe e ativa,
--    (2) tem a permissão daquele item (ou é dona), (3) entrou com 2 etapas (aal2).
--  * Toda ação que muda algo fica registrada em admin_log.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Equipe, permissões por item e registro
-- ---------------------------------------------------------------------
create table if not exists public.admin_equipe (
  user_id uuid primary key references public.users(id) on delete cascade,
  dono boolean not null default false,
  ativo boolean not null default true,
  cargo text check (char_length(cargo) <= 60),
  adicionado_por uuid references public.users(id) on delete set null,
  criado_em timestamptz not null default now()
);

create table if not exists public.admin_permissoes (
  user_id uuid not null references public.admin_equipe(user_id) on delete cascade,
  permissao text not null,
  primary key (user_id, permissao)
);

create table if not exists public.admin_log (
  id bigserial primary key,
  user_id uuid references public.users(id) on delete set null,
  acao text not null,
  alvo text,
  detalhes jsonb,
  em timestamptz not null default now()
);
create index if not exists admin_log_em_idx on public.admin_log (em desc);

alter table public.admin_equipe enable row level security;
alter table public.admin_permissoes enable row level security;
alter table public.admin_log enable row level security;
revoke all on public.admin_equipe, public.admin_permissoes, public.admin_log from anon, authenticated;
revoke all on sequence public.admin_log_id_seq from anon, authenticated;

-- Catálogo de permissões (o painel mostra daqui).
create or replace function public.adm_catalogo()
returns table (permissao text, grupo text, nome text, descricao text)
language sql immutable set search_path = public as $$
  values
    ('numeros.ver',          'Números',     'Ver números e funil',        'Dashboard, crescimento, origens e funil'),
    ('usuarios.ver',         'Usuários',    'Ver usuários',               'Buscar e abrir a ficha de qualquer usuário'),
    ('usuarios.editar',      'Usuários',    'Editar usuário',             'Nome, @, bio e ajuste de pontos'),
    ('usuarios.pro',         'Usuários',    'Dar ou tirar PRO',           'PRO de cortesia por dias'),
    ('usuarios.banir',       'Usuários',    'Banir e desbanir',           'Bloqueia o login da pessoa'),
    ('usuarios.apagar',      'Usuários',    'Apagar conta',               'Apaga a conta e todos os dados (sem volta)'),
    ('comunidade.moderar',   'Comunidade',  'Moderar a Comunidade',       'Denúncias, posts, vídeos, stories, comentários e grupos'),
    ('conteudo.exercicios',  'Conteúdo',    'Exercícios',                 'Criar, editar, traduzir e trocar mídia'),
    ('conteudo.eventos',     'Conteúdo',    'Eventos oficiais',           'Criar, editar e cancelar eventos com selo'),
    ('conteudo.perguntas',   'Conteúdo',    'Pergunta do dia',            'Criar e editar as perguntas do quiz'),
    ('push.enviar',          'Conteúdo',    'Enviar push',                'Notificação pra todos ou por público'),
    ('receita.ver',          'Negócio',     'Assinaturas e receita',      'PRO pagos, cancelamentos e receita'),
    ('ia.ver',               'Negócio',     'Custo da IA',                'Gasto com OpenAI por dia, função e usuário'),
    ('app.config',           'App',         'Controle remoto do app',     'Manutenção, versão mínima e aviso na Home'),
    ('suporte.atender',      'Suporte',     'Suporte e feedback',         'Ler e responder os chamados'),
    ('log.ver',              'Equipe',      'Ver registro de ações',      'Quem fez o quê e quando'),
    ('equipe.gerenciar',     'Equipe',      'Gerenciar equipe',           'Adicionar pessoas e dar permissões')
$$;

-- A pessoa logada pode usar a permissão? (equipe ativa + permissão + 2 etapas)
create or replace function public.adm_ok(p_perm text)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce((select auth.jwt() ->> 'aal'), 'aal1') = 'aal2'
    and exists (
      select 1 from admin_equipe e
      where e.user_id = (select auth.uid()) and e.ativo
        and (e.dono or exists (select 1 from admin_permissoes p where p.user_id = e.user_id and p.permissao = p_perm))
    )
$$;

create or replace function public.adm_exigir(p_perm text)
returns void language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if not adm_ok(p_perm) then raise exception 'SEM_PERMISSAO: %', p_perm using errcode = '42501'; end if;
end $$;

create or replace function public.adm_registrar(p_acao text, p_alvo text, p_detalhes jsonb default null)
returns void language sql security definer set search_path = public, pg_temp as $$
  insert into admin_log (user_id, acao, alvo, detalhes) values ((select auth.uid()), p_acao, p_alvo, p_detalhes);
$$;
revoke all on function public.adm_registrar(text, text, jsonb) from public, anon, authenticated;
revoke all on function public.adm_exigir(text) from public, anon;

-- Quem sou eu no admin (não exige 2 etapas: é o que guia a tela de login).
create or replace function public.adm_eu()
returns jsonb language sql stable security definer set search_path = public, pg_temp as $$
  select case when e.user_id is null or not e.ativo then jsonb_build_object('membro', false)
  else jsonb_build_object(
    'membro', true,
    'dono', e.dono,
    'cargo', e.cargo,
    'nome', u.full_name,
    'email', u.email,
    'avatar', u.avatar_url,
    'aal', coalesce((select auth.jwt() ->> 'aal'), 'aal1'),
    'permissoes', case when e.dono then (select jsonb_agg(c.permissao) from adm_catalogo() c)
                  else coalesce((select jsonb_agg(p.permissao) from admin_permissoes p where p.user_id = e.user_id), '[]'::jsonb) end
  ) end
  from (select (select auth.uid()) as uid) x
  left join admin_equipe e on e.user_id = x.uid
  left join users u on u.id = x.uid
$$;

-- ---------------------------------------------------------------------
-- 2. Equipe
-- ---------------------------------------------------------------------
create or replace function public.adm_equipe_listar()
returns table (user_id uuid, nome text, email text, avatar text, dono boolean, ativo boolean, cargo text,
               permissoes text[], tem_2fa boolean, criado_em timestamptz)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform adm_exigir('equipe.gerenciar');
  return query
  select e.user_id, u.full_name, u.email, u.avatar_url, e.dono, e.ativo, e.cargo,
    coalesce(array(select p.permissao from admin_permissoes p where p.user_id = e.user_id order by 1), '{}'),
    exists (select 1 from auth.mfa_factors f where f.user_id = e.user_id and f.status = 'verified'),
    e.criado_em
  from admin_equipe e join users u on u.id = e.user_id
  order by e.dono desc, e.criado_em;
end $$;

-- Adiciona ou edita alguém. A pessoa precisa ter conta no BroGym (procura por e-mail ou @).
-- Ninguém dá uma permissão que não tem; só dono mexe em dono.
create or replace function public.adm_equipe_salvar(p_quem text, p_cargo text, p_permissoes text[], p_ativo boolean default true)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_eu uuid := (select auth.uid());
  v_eu_dono boolean;
  v_alvo uuid;
  v_alvo_dono boolean;
  v_perm text;
begin
  perform adm_exigir('equipe.gerenciar');
  select dono into v_eu_dono from admin_equipe where user_id = v_eu;
  select id into v_alvo from users
   where lower(email) = lower(trim(p_quem)) or lower(username) = lower(ltrim(trim(p_quem), '@'))
   limit 1;
  if v_alvo is null then raise exception 'Não achei ninguém com esse e-mail ou @ no BroGym. A pessoa precisa criar conta no app primeiro.'; end if;
  select dono into v_alvo_dono from admin_equipe where user_id = v_alvo;
  if coalesce(v_alvo_dono, false) and not v_eu_dono then raise exception 'Só o dono mexe no acesso do dono.'; end if;
  if v_alvo = v_eu and not coalesce(p_ativo, true) then raise exception 'Você não pode se desativar.'; end if;

  foreach v_perm in array coalesce(p_permissoes, '{}') loop
    if not exists (select 1 from adm_catalogo() c where c.permissao = v_perm) then raise exception 'Permissão desconhecida: %', v_perm; end if;
    if not adm_ok(v_perm) then raise exception 'Você não pode dar uma permissão que não tem: %', v_perm; end if;
  end loop;

  insert into admin_equipe (user_id, cargo, ativo, adicionado_por) values (v_alvo, nullif(trim(p_cargo), ''), coalesce(p_ativo, true), v_eu)
  on conflict (user_id) do update set cargo = excluded.cargo, ativo = case when admin_equipe.dono then true else excluded.ativo end;

  delete from admin_permissoes where user_id = v_alvo;
  insert into admin_permissoes (user_id, permissao) select v_alvo, unnest(coalesce(p_permissoes, '{}')) on conflict do nothing;

  perform adm_registrar('equipe.salvar', v_alvo::text, jsonb_build_object('cargo', p_cargo, 'permissoes', p_permissoes, 'ativo', p_ativo));
  return v_alvo;
end $$;

create or replace function public.adm_equipe_remover(p_user uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform adm_exigir('equipe.gerenciar');
  if p_user = (select auth.uid()) then raise exception 'Você não pode se remover.'; end if;
  if exists (select 1 from admin_equipe where user_id = p_user and dono) then raise exception 'O dono não pode ser removido.'; end if;
  delete from admin_equipe where user_id = p_user;
  perform adm_registrar('equipe.remover', p_user::text, null);
end $$;

create or replace function public.adm_log_listar(p_limite integer default 100, p_antes bigint default null, p_busca text default null)
returns table (id bigint, em timestamptz, quem text, quem_email text, acao text, alvo text, alvo_nome text, detalhes jsonb)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform adm_exigir('log.ver');
  return query
  select l.id, l.em, u.full_name, u.email, l.acao, l.alvo,
    (select coalesce(x.full_name, x.username) from users x where x.id::text = l.alvo),
    l.detalhes
  from admin_log l left join users u on u.id = l.user_id
  where (p_antes is null or l.id < p_antes)
    and (p_busca is null or l.acao ilike '%' || p_busca || '%' or u.full_name ilike '%' || p_busca || '%' or l.alvo = p_busca)
  order by l.id desc
  limit least(coalesce(p_limite, 100), 500);
end $$;

-- ---------------------------------------------------------------------
-- 3. Números
-- ---------------------------------------------------------------------
create or replace function public.adm_resumo()
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v jsonb;
begin
  perform adm_exigir('numeros.ver');
  select jsonb_build_object(
    'usuarios', (select count(*) from users),
    'salvos', (select count(*) from users where email is not null),
    'anonimos', (select count(*) from users where email is null),
    'novos_hoje', (select count(*) from users where created_at >= date_trunc('day', now() at time zone 'America/Sao_Paulo') at time zone 'America/Sao_Paulo'),
    'novos_7d', (select count(*) from users where created_at > now() - interval '7 days'),
    'novos_30d', (select count(*) from users where created_at > now() - interval '30 days'),
    'ativos_hoje', (select count(*) from users where last_active > now() - interval '1 day'),
    'ativos_7d', (select count(*) from users where last_active > now() - interval '7 days'),
    'ativos_30d', (select count(*) from users where last_active > now() - interval '30 days'),
    'treinos_hoje', (select count(*) from workout_sessions where completed_at > now() - interval '1 day'),
    'treinos_7d', (select count(*) from workout_sessions where completed_at > now() - interval '7 days'),
    'treinaram_7d', (select count(distinct user_id) from workout_sessions where completed_at > now() - interval '7 days'),
    'pro_pagos', (select count(distinct user_id) from user_subscriptions where is_premium and (expiration_date is null or expiration_date > now())),
    'pro_cortesia', (select count(*) from pro_cortesia where ate > now()),
    'posts_7d', (select count(*) from community_posts where created_at > now() - interval '7 days'),
    'stories_ativos', (select count(*) from stories where expira_em > now()),
    'denuncias_abertas', (select count(distinct (tipo, alvo_id)) from denuncias where status = 'aberta'),
    'chamados_abertos', (select count(*) from suporte_tickets where status = 'aberto'),
    'meta_contas', 1000,
    'meta_data', '2026-12-31'
  ) into v;
  return v;
end $$;

-- Série por dia (fuso de Brasília): novos, salvos, treinos, ativos (quem treinou), posts.
create or replace function public.adm_serie(p_dias integer default 30)
returns table (dia date, novos bigint, treinos bigint, treinaram bigint, posts bigint)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform adm_exigir('numeros.ver');
  return query
  with d as (
    select generate_series((now() at time zone 'America/Sao_Paulo')::date - (least(p_dias, 365) - 1), (now() at time zone 'America/Sao_Paulo')::date, interval '1 day')::date as dia
  )
  select d.dia,
    (select count(*) from users u where (u.created_at at time zone 'America/Sao_Paulo')::date = d.dia),
    (select count(*) from workout_sessions s where (s.completed_at at time zone 'America/Sao_Paulo')::date = d.dia),
    (select count(distinct s.user_id) from workout_sessions s where (s.completed_at at time zone 'America/Sao_Paulo')::date = d.dia),
    (select count(*) from community_posts p where (p.created_at at time zone 'America/Sao_Paulo')::date = d.dia)
  from d order by d.dia;
end $$;

create or replace function public.adm_funil(p_desde date default (now() - interval '30 days')::date)
returns table (origem text, contas bigint, abriu bigint, onboarding bigint, salvou_conta bigint, primeiro_treino bigint, dia_7 bigint, convidou bigint)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform adm_exigir('numeros.ver');
  return query
  select coalesce(nullif(u.origem, ''), 'orgânico'),
    count(distinct u.id),
    count(distinct u.id) filter (where f.evento = 'abriu'),
    count(distinct u.id) filter (where f.evento = 'onboarding'),
    count(distinct u.id) filter (where f.evento = 'salvou_conta'),
    count(distinct u.id) filter (where f.evento = 'primeiro_treino'),
    count(distinct u.id) filter (where f.evento = 'dia_7'),
    count(distinct u.id) filter (where f.evento = 'convidou')
  from users u
  left join funil_eventos f on f.user_id = u.id
  where u.created_at >= p_desde
  group by 1 order by 2 desc;
end $$;

create or replace function public.adm_distribuicao()
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform adm_exigir('numeros.ver');
  return jsonb_build_object(
    'idioma', (select jsonb_object_agg(k, n) from (select coalesce(idioma, 'pt') k, count(*) n from users group by 1) x),
    'sexo', (select jsonb_object_agg(k, n) from (select coalesce(nullif(gender, ''), '—') k, count(*) n from users group by 1) x),
    'objetivo', (select jsonb_object_agg(k, n) from (select coalesce(fitness_goals[1], '—') k, count(*) n from users group by 1) x),
    'cidade', (select jsonb_object_agg(k, n) from (select coalesce(nullif(cidade, ''), '—') k, count(*) n from users group by 1 order by 2 desc limit 15) x)
  );
end $$;

-- ---------------------------------------------------------------------
-- 4. Usuários
-- ---------------------------------------------------------------------
alter table public.users add column if not exists banido_ate timestamptz;
alter table public.users add column if not exists banido_motivo text;

create or replace function public.adm_usuarios(p_busca text default null, p_filtro text default 'todos', p_limite integer default 50, p_offset integer default 0)
returns table (id uuid, nome text, email text, username text, avatar text, criado_em timestamptz, ultimo_acesso timestamptz,
               treinos integer, pro text, banido_ate timestamptz, origem text, idioma text, cidade text, total bigint)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform adm_exigir('usuarios.ver');
  return query
  with base as (
    select u.*,
      case when exists (select 1 from user_subscriptions s where s.user_id = u.id and s.is_premium and (s.expiration_date is null or s.expiration_date > now())) then 'pago'
           when exists (select 1 from pro_cortesia c where c.user_id = u.id and c.ate > now()) then 'cortesia'
           else null end as pro_tipo
    from users u
    where (p_busca is null or trim(p_busca) = ''
           or u.full_name ilike '%' || trim(p_busca) || '%'
           or u.email ilike '%' || trim(p_busca) || '%'
           or u.username ilike '%' || ltrim(trim(p_busca), '@') || '%'
           or u.id::text = trim(p_busca))
  ), f as (
    select * from base b where case coalesce(p_filtro, 'todos')
      when 'pro' then b.pro_tipo is not null
      when 'pagos' then b.pro_tipo = 'pago'
      when 'anonimos' then b.email is null
      when 'banidos' then b.banido_ate > now()
      when 'novos' then b.created_at > now() - interval '7 days'
      when 'inativos' then coalesce(b.last_active, b.created_at) < now() - interval '14 days'
      else true end
  )
  select f.id, f.full_name, f.email, f.username, f.avatar_url, f.created_at, f.last_active, f.total_workouts,
    f.pro_tipo, f.banido_ate, f.origem, f.idioma, f.cidade, count(*) over ()
  from f order by f.created_at desc
  limit least(coalesce(p_limite, 50), 200) offset greatest(coalesce(p_offset, 0), 0);
end $$;

create or replace function public.adm_usuario(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v jsonb;
begin
  perform adm_exigir('usuarios.ver');
  select jsonb_build_object(
    'perfil', to_jsonb(u) - 'origem_detalhe',
    'origem_detalhe', u.origem_detalhe,
    'ultimo_login', (select a.last_sign_in_at from auth.users a where a.id = u.id),
    'provedor', (select a.raw_app_meta_data ->> 'provider' from auth.users a where a.id = u.id),
    'equipe', exists (select 1 from admin_equipe e where e.user_id = u.id),
    'assinatura', (select to_jsonb(s) from user_subscriptions s where s.user_id = u.id order by s.updated_at desc nulls last limit 1),
    'cortesia', (select to_jsonb(c) from pro_cortesia c where c.user_id = u.id),
    'pontos', (select coalesce(sum(p.pontos), 0) from pontos p where p.user_id = u.id),
    'seguidores', (select count(*) from seguidores s where s.seguido_id = u.id),
    'seguindo', (select count(*) from seguidores s where s.seguidor_id = u.id),
    'posts', (select count(*) from community_posts p where p.user_id = u.id),
    'treinos', (select coalesce(jsonb_agg(t), '[]') from (
        select s.id, s.started_at, s.completed_at, s.duration_minutes, s.status, w.name
        from workout_sessions s left join workouts w on w.id = s.workout_id
        where s.user_id = u.id order by s.started_at desc limit 15) t),
    'funil', (select coalesce(jsonb_object_agg(f.evento, f.em), '{}') from funil_eventos f where f.user_id = u.id),
    'denuncias_contra', (select count(*) from denuncias d where d.autor_id = u.id),
    'ia_30d', (select jsonb_build_object('chamadas', count(*), 'custo_usd', coalesce(sum(i.custo_usd), 0)) from ia_uso i where i.user_id = u.id and i.em > now() - interval '30 days'),
    'chamados', (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'assunto', t.assunto, 'status', t.status, 'criado_em', t.criado_em) order by t.criado_em desc), '[]') from suporte_tickets t where t.user_id = u.id)
  ) into v
  from users u where u.id = p_id;
  if v is null then raise exception 'Usuário não encontrado.'; end if;
  return v;
end $$;

-- p_dias > 0 soma dias de PRO; p_dias = 0 tira a cortesia.
create or replace function public.adm_dar_pro(p_user uuid, p_dias integer, p_motivo text default null)
returns timestamptz language plpgsql security definer set search_path = public, pg_temp as $$
declare v timestamptz;
begin
  perform adm_exigir('usuarios.pro');
  if p_dias < 0 or p_dias > 3650 then raise exception 'Dias inválidos.'; end if;
  if p_dias = 0 then
    update pro_cortesia set ate = now(), motivo = coalesce(p_motivo, 'removido pelo admin'), atualizado_em = now() where user_id = p_user;
  else
    insert into pro_cortesia (user_id, ate, motivo) values (p_user, now() + make_interval(days => p_dias), coalesce(p_motivo, 'admin'))
    on conflict (user_id) do update
      set ate = greatest(pro_cortesia.ate, now()) + make_interval(days => p_dias), motivo = coalesce(p_motivo, 'admin'), atualizado_em = now();
    insert into push_fila (user_id, titulo, texto, rota)
    values (p_user, 'Você ganhou PRO! 👑', 'Liberamos ' || p_dias || ' dias de BroGym PRO pra você. Aproveita!', '/home');
  end if;
  select ate into v from pro_cortesia where user_id = p_user;
  perform adm_registrar('usuario.pro', p_user::text, jsonb_build_object('dias', p_dias, 'motivo', p_motivo, 'ate', v));
  return v;
end $$;

create or replace function public.adm_editar_usuario(p_user uuid, p_nome text, p_username text, p_bio text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_antes jsonb;
begin
  perform adm_exigir('usuarios.editar');
  select jsonb_build_object('nome', full_name, 'username', username, 'bio', bio) into v_antes from users where id = p_user;
  if p_username is not null and exists (select 1 from users where lower(username) = lower(trim(p_username)) and id <> p_user) then
    raise exception 'Esse @ já é de outra pessoa.';
  end if;
  update users set full_name = coalesce(nullif(trim(p_nome), ''), full_name),
                   username = coalesce(nullif(lower(trim(p_username)), ''), username),
                   bio = p_bio, updated_at = now()
  where id = p_user;
  perform adm_registrar('usuario.editar', p_user::text, jsonb_build_object('antes', v_antes, 'depois', jsonb_build_object('nome', p_nome, 'username', p_username, 'bio', p_bio)));
end $$;

create or replace function public.adm_ajustar_pontos(p_user uuid, p_pontos integer, p_motivo text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform adm_exigir('usuarios.editar');
  if p_pontos = 0 or abs(p_pontos) > 10000 then raise exception 'Pontos inválidos.'; end if;
  insert into pontos (user_id, motivo, ref, pontos) values (p_user, 'ajuste_admin', gen_random_uuid()::text, p_pontos);
  perform adm_registrar('usuario.pontos', p_user::text, jsonb_build_object('pontos', p_pontos, 'motivo', p_motivo));
end $$;

-- Banir: bloqueia login no Auth (banned_until) e derruba as sessões abertas.
-- p_dias nulo = sem prazo.
create or replace function public.adm_banir(p_user uuid, p_dias integer, p_motivo text)
returns void language plpgsql security definer set search_path = public, auth, pg_temp as $$
declare v_ate timestamptz := case when p_dias is null then now() + interval '100 years' else now() + make_interval(days => p_dias) end;
begin
  perform adm_exigir('usuarios.banir');
  if exists (select 1 from admin_equipe where user_id = p_user) then raise exception 'Tire a pessoa da equipe antes de banir.'; end if;
  if coalesce(trim(p_motivo), '') = '' then raise exception 'Diga o motivo.'; end if;
  update public.users set banido_ate = v_ate, banido_motivo = p_motivo, is_online = false where id = p_user;
  update auth.users set banned_until = v_ate where id = p_user;
  delete from auth.sessions where user_id = p_user;
  perform adm_registrar('usuario.banir', p_user::text, jsonb_build_object('dias', p_dias, 'motivo', p_motivo, 'ate', v_ate));
end $$;

create or replace function public.adm_desbanir(p_user uuid)
returns void language plpgsql security definer set search_path = public, auth, pg_temp as $$
begin
  perform adm_exigir('usuarios.banir');
  update public.users set banido_ate = null, banido_motivo = null where id = p_user;
  update auth.users set banned_until = null where id = p_user;
  perform adm_registrar('usuario.desbanir', p_user::text, null);
end $$;

-- A função delete-account (servidor) pergunta aqui se quem chamou pode apagar outra conta.
create or replace function public.adm_pode_apagar(p_user uuid)
returns boolean language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if not adm_ok('usuarios.apagar') then return false; end if;
  if exists (select 1 from admin_equipe where user_id = p_user) then return false; end if;
  return true;
end $$;

create or replace function public.adm_registrar_apagou(p_user uuid, p_email text, p_nome text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform adm_exigir('usuarios.apagar');
  perform adm_registrar('usuario.apagar', p_user::text, jsonb_build_object('email', p_email, 'nome', p_nome));
end $$;

-- ---------------------------------------------------------------------
-- 5. Comunidade
-- ---------------------------------------------------------------------
create or replace function public.adm_denuncias()
returns table (tipo text, alvo_id text, autor_id uuid, autor_nome text, motivos text[], qtd integer, ultima timestamptz, texto text, imagem text, video text)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform adm_exigir('comunidade.moderar');
  return query
  with d as (
    select d.tipo, d.alvo_id, max(d.autor_id::text)::uuid as autor_id, array_agg(distinct d.motivo) as motivos, count(*)::int as qtd, max(d.criado_em) as ultima
    from denuncias d where d.status = 'aberta' group by d.tipo, d.alvo_id
  )
  select d.tipo, d.alvo_id, d.autor_id, u.full_name, d.motivos, d.qtd, d.ultima,
    case d.tipo
      when 'post' then (select p.content from community_posts p where p.id::text = d.alvo_id)
      when 'video' then (select p.content from community_posts p where p.id::text = d.alvo_id)
      when 'story' then (select s.legenda from stories s where s.id::text = d.alvo_id)
      when 'comentario' then (select c.content from post_comments c where c.id::text = d.alvo_id)
      when 'usuario' then (select x.bio from users x where x.id::text = d.alvo_id)
      else null end,
    case d.tipo
      when 'post' then (select p.image_url from community_posts p where p.id::text = d.alvo_id)
      when 'story' then (select s.media_url from stories s where s.id::text = d.alvo_id and s.tipo = 'foto')
      when 'usuario' then (select x.avatar_url from users x where x.id::text = d.alvo_id)
      else null end,
    case d.tipo
      when 'video' then (select p.video_url from community_posts p where p.id::text = d.alvo_id)
      when 'story' then (select s.media_url from stories s where s.id::text = d.alvo_id and s.tipo = 'video')
      else null end
  from d left join users u on u.id = d.autor_id
  order by d.qtd desc, d.ultima desc;
end $$;

create or replace function public.adm_resolver_denuncia(p_tipo text, p_alvo text, p_acao text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform adm_exigir('comunidade.moderar');
  if p_acao not in ('remover', 'ignorar') then raise exception 'Ação inválida.'; end if;
  if p_acao = 'remover' then
    if p_tipo in ('post', 'video') then delete from community_posts where id::text = p_alvo;
    elsif p_tipo = 'story' then delete from stories where id::text = p_alvo;
    elsif p_tipo = 'comentario' then delete from post_comments where id::text = p_alvo;
    elsif p_tipo = 'usuario' then
      delete from community_posts where user_id::text = p_alvo;
      delete from stories where user_id::text = p_alvo;
    end if;
  end if;
  update denuncias set status = case when p_acao = 'remover' then 'resolvida' else 'ignorada' end
  where tipo = p_tipo and alvo_id = p_alvo and status = 'aberta';
  perform adm_registrar('denuncia.' || p_acao, p_alvo, jsonb_build_object('tipo', p_tipo));
end $$;

create or replace function public.adm_posts(p_busca text default null, p_tipo text default null, p_limite integer default 40, p_antes timestamptz default null)
returns table (id uuid, user_id uuid, autor text, autor_username text, autor_avatar text, conteudo text, imagem text, video text, tipo text,
               visibilidade text, criado_em timestamptz, curtidas bigint, comentarios bigint, denuncias bigint)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform adm_exigir('comunidade.moderar');
  return query
  select p.id, p.user_id, u.full_name, u.username, u.avatar_url, p.content, p.image_url, p.video_url, p.tipo, p.visibility, p.created_at,
    (select count(*) from post_likes l where l.post_id = p.id),
    (select count(*) from post_comments c where c.post_id = p.id),
    (select count(*) from denuncias d where d.alvo_id = p.id::text)
  from community_posts p left join users u on u.id = p.user_id
  where (p_antes is null or p.created_at < p_antes)
    and (p_tipo is null or (p_tipo = 'video' and p.video_url is not null) or (p_tipo = 'foto' and p.image_url is not null) or (p_tipo = 'treino' and p.workout_session_id is not null))
    and (p_busca is null or p.content ilike '%' || p_busca || '%' or u.full_name ilike '%' || p_busca || '%' or u.username ilike '%' || ltrim(p_busca, '@') || '%')
  order by p.created_at desc
  limit least(coalesce(p_limite, 40), 100);
end $$;

create or replace function public.adm_comentarios(p_post uuid default null, p_limite integer default 60)
returns table (id uuid, post_id uuid, user_id uuid, autor text, autor_avatar text, conteudo text, criado_em timestamptz)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform adm_exigir('comunidade.moderar');
  return query
  select c.id, c.post_id, c.user_id, u.full_name, u.avatar_url, c.content, c.created_at
  from post_comments c left join users u on u.id = c.user_id
  where p_post is null or c.post_id = p_post
  order by c.created_at desc limit least(coalesce(p_limite, 60), 200);
end $$;

create or replace function public.adm_stories()
returns table (id uuid, user_id uuid, autor text, autor_avatar text, media text, tipo text, legenda text, criado_em timestamptz, expira_em timestamptz, vistas bigint)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform adm_exigir('comunidade.moderar');
  return query
  select s.id, s.user_id, u.full_name, u.avatar_url, s.media_url, s.tipo, s.legenda, s.criado_em, s.expira_em,
    (select count(*) from story_vistas v where v.story_id = s.id)
  from stories s left join users u on u.id = s.user_id
  where s.expira_em > now() - interval '2 days'
  order by s.criado_em desc limit 200;
end $$;

-- Apaga post, story ou comentário. Avisa o autor (se p_avisar).
create or replace function public.adm_apagar_conteudo(p_tipo text, p_id uuid, p_motivo text default null, p_avisar boolean default true)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_autor uuid;
begin
  perform adm_exigir('comunidade.moderar');
  if p_tipo = 'post' then delete from community_posts where id = p_id returning user_id into v_autor;
  elsif p_tipo = 'story' then delete from stories where id = p_id returning user_id into v_autor;
  elsif p_tipo = 'comentario' then delete from post_comments where id = p_id returning user_id into v_autor;
  else raise exception 'Tipo inválido.'; end if;
  update denuncias set status = 'resolvida' where alvo_id = p_id::text and status = 'aberta';
  if p_avisar and v_autor is not null then
    insert into push_fila (user_id, titulo, texto, rota)
    values (v_autor, 'Removemos uma publicação sua',
            coalesce('Motivo: ' || nullif(trim(p_motivo), ''), 'Ela não segue as regras da Comunidade do BroGym.'), '/notificacoes');
  end if;
  perform adm_registrar('comunidade.apagar_' || p_tipo, p_id::text, jsonb_build_object('autor', v_autor, 'motivo', p_motivo));
end $$;

create or replace function public.adm_grupos()
returns table (id uuid, nome text, descricao text, oficial boolean, categoria text, cidade text, publico boolean, dono text, membros bigint, criado_em timestamptz, capa text)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform adm_exigir('comunidade.moderar');
  return query
  select c.id, c.name, c.description, c.oficial, c.categoria, c.cidade, c.is_public, u.full_name,
    (select count(*) from club_members m where m.club_id = c.id), c.created_at, c.capa_url
  from clubs c left join users u on u.id = c.owner_id
  order by c.oficial desc, 9 desc;
end $$;

create or replace function public.adm_grupo_salvar(p_id uuid, p_nome text, p_descricao text, p_categoria text, p_capa text default null)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare v uuid;
begin
  perform adm_exigir('comunidade.moderar');
  if p_id is null then
    insert into clubs (name, description, is_public, oficial, categoria, capa_url, owner_id)
    values (trim(p_nome), p_descricao, true, true, nullif(p_categoria, ''), p_capa, null) returning id into v;
  else
    update clubs set name = trim(p_nome), description = p_descricao, categoria = coalesce(nullif(p_categoria, ''), categoria), capa_url = coalesce(p_capa, capa_url)
    where id = p_id returning id into v;
  end if;
  perform adm_registrar('grupo.salvar', v::text, jsonb_build_object('nome', p_nome));
  return v;
end $$;

create or replace function public.adm_grupo_apagar(p_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_nome text;
begin
  perform adm_exigir('comunidade.moderar');
  delete from clubs where id = p_id returning name into v_nome;
  perform adm_registrar('grupo.apagar', p_id::text, jsonb_build_object('nome', v_nome));
end $$;

-- ---------------------------------------------------------------------
-- 6. Conteúdo: exercícios, eventos oficiais, pergunta do dia, push
-- ---------------------------------------------------------------------
create or replace function public.adm_exercicios(p_busca text default null, p_categoria uuid default null)
returns table (id uuid, nome text, nome_en text, nome_es text, categoria_id uuid, categoria text, media_url text, media_type text, ativo boolean, usos bigint)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform adm_exigir('conteudo.exercicios');
  return query
  select e.id, e.name, e.name_en, e.name_es, e.category_id, c.name, e.media_url, e.media_type, e.is_active,
    (select count(*) from exercicios_favoritos f where f.exercise_id = e.id)
  from exercises e left join exercise_categories c on c.id = e.category_id
  where (p_categoria is null or e.category_id = p_categoria)
    and (p_busca is null or e.name ilike '%' || p_busca || '%' or e.name_en ilike '%' || p_busca || '%' or e.name_es ilike '%' || p_busca || '%')
  order by c.name, e.name;
end $$;

create or replace function public.adm_categorias()
returns table (id uuid, nome text, nome_en text, nome_es text, exercicios bigint)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform adm_exigir('conteudo.exercicios');
  return query
  select c.id, c.name, c.name_en, c.name_es, (select count(*) from exercises e where e.category_id = c.id)
  from exercise_categories c order by c.name;
end $$;

create or replace function public.adm_exercicio_salvar(p_id uuid, p_dados jsonb)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare v uuid;
begin
  perform adm_exigir('conteudo.exercicios');
  if coalesce(trim(p_dados ->> 'nome'), '') = '' then raise exception 'Dê um nome pro exercício.'; end if;
  if p_id is null then
    insert into exercises (name, name_en, name_es, category_id, media_url, media_type, is_active)
    values (trim(p_dados ->> 'nome'), nullif(trim(p_dados ->> 'nome_en'), ''), nullif(trim(p_dados ->> 'nome_es'), ''),
            (p_dados ->> 'categoria_id')::uuid, nullif(p_dados ->> 'media_url', ''), coalesce(nullif(p_dados ->> 'media_type', ''), 'image'),
            coalesce((p_dados ->> 'ativo')::boolean, true))
    returning id into v;
  else
    update exercises set
      name = trim(p_dados ->> 'nome'),
      name_en = nullif(trim(p_dados ->> 'nome_en'), ''),
      name_es = nullif(trim(p_dados ->> 'nome_es'), ''),
      category_id = (p_dados ->> 'categoria_id')::uuid,
      media_url = nullif(p_dados ->> 'media_url', ''),
      media_type = coalesce(nullif(p_dados ->> 'media_type', ''), media_type),
      is_active = coalesce((p_dados ->> 'ativo')::boolean, is_active)
    where id = p_id returning id into v;
  end if;
  perform adm_registrar('exercicio.salvar', v::text, p_dados);
  return v;
end $$;

create or replace function public.adm_categoria_salvar(p_id uuid, p_nome text, p_nome_en text, p_nome_es text)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare v uuid;
begin
  perform adm_exigir('conteudo.exercicios');
  if p_id is null then
    insert into exercise_categories (name, name_en, name_es) values (trim(p_nome), nullif(trim(p_nome_en), ''), nullif(trim(p_nome_es), '')) returning id into v;
  else
    update exercise_categories set name = trim(p_nome), name_en = nullif(trim(p_nome_en), ''), name_es = nullif(trim(p_nome_es), '') where id = p_id returning id into v;
  end if;
  perform adm_registrar('categoria.salvar', v::text, jsonb_build_object('nome', p_nome));
  return v;
end $$;

-- Eventos (todos, oficiais primeiro).
create or replace function public.adm_eventos(p_so_oficiais boolean default false)
returns table (id uuid, titulo text, descricao text, tipo text, inicio timestamptz, fim timestamptz, local_nome text, lat double precision, lng double precision,
               meta_km numeric, placar text, premio text, publico boolean, oficial boolean, codigo text, cancelado boolean, fechado_em timestamptz,
               capa_url text, conta_treinos boolean, em_dupla boolean, criador text, inscritos bigint)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform adm_exigir('conteudo.eventos');
  return query
  select e.id, e.titulo, e.descricao, e.tipo, e.inicio, e.fim, e.local_nome, e.lat, e.lng, e.meta_km, e.placar, e.premio, e.publico, e.oficial,
    e.codigo, e.cancelado, e.fechado_em, e.capa_url, e.conta_treinos, e.em_dupla, u.full_name,
    (select count(*) from evento_participantes p where p.evento_id = e.id)
  from eventos e left join users u on u.id = e.criador_id
  where not p_so_oficiais or e.oficial
  order by e.oficial desc, e.inicio desc
  limit 300;
end $$;

-- Cria/edita evento oficial. O organizador é a conta oficial @brogym.
create or replace function public.adm_evento_salvar(p_id uuid, p_dados jsonb)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v uuid;
  v_brogym uuid := (select id from users where username = 'brogym' limit 1);
begin
  perform adm_exigir('conteudo.eventos');
  if p_id is null then
    insert into eventos (criador_id, titulo, descricao, tipo, inicio, fim, local_nome, lat, lng, meta_km, placar, premio, publico, oficial, capa_url, conta_treinos, em_dupla)
    values (v_brogym, trim(p_dados ->> 'titulo'), p_dados ->> 'descricao', p_dados ->> 'tipo',
            (p_dados ->> 'inicio')::timestamptz, (p_dados ->> 'fim')::timestamptz, nullif(p_dados ->> 'local_nome', ''),
            (p_dados ->> 'lat')::double precision, (p_dados ->> 'lng')::double precision, (p_dados ->> 'meta_km')::numeric,
            coalesce(p_dados ->> 'placar', 'maior'), nullif(p_dados ->> 'premio', ''), coalesce((p_dados ->> 'publico')::boolean, true), true,
            nullif(p_dados ->> 'capa_url', ''), coalesce((p_dados ->> 'conta_treinos')::boolean, false), coalesce((p_dados ->> 'em_dupla')::boolean, false))
    returning id into v;
  else
    update eventos set
      titulo = trim(p_dados ->> 'titulo'), descricao = p_dados ->> 'descricao', tipo = p_dados ->> 'tipo',
      inicio = (p_dados ->> 'inicio')::timestamptz, fim = (p_dados ->> 'fim')::timestamptz,
      local_nome = nullif(p_dados ->> 'local_nome', ''), lat = (p_dados ->> 'lat')::double precision, lng = (p_dados ->> 'lng')::double precision,
      meta_km = (p_dados ->> 'meta_km')::numeric, placar = coalesce(p_dados ->> 'placar', placar), premio = nullif(p_dados ->> 'premio', ''),
      publico = coalesce((p_dados ->> 'publico')::boolean, publico), capa_url = nullif(p_dados ->> 'capa_url', ''),
      conta_treinos = coalesce((p_dados ->> 'conta_treinos')::boolean, conta_treinos), em_dupla = coalesce((p_dados ->> 'em_dupla')::boolean, em_dupla)
    where id = p_id returning id into v;
  end if;
  perform adm_registrar('evento.salvar', v::text, p_dados);
  return v;
end $$;

create or replace function public.adm_evento_cancelar(p_id uuid, p_cancelar boolean default true)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform adm_exigir('conteudo.eventos');
  update eventos set cancelado = p_cancelar where id = p_id;
  perform adm_registrar(case when p_cancelar then 'evento.cancelar' else 'evento.reativar' end, p_id::text, null);
end $$;

create or replace function public.adm_perguntas()
returns table (id integer, texto text, opcoes text[], correta smallint, explicacao text, texto_en text, opcoes_en text[], explicacao_en text,
               texto_es text, opcoes_es text[], explicacao_es text, respostas bigint, acertos bigint)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform adm_exigir('conteudo.perguntas');
  return query
  select p.id, p.texto, p.opcoes, p.correta, p.explicacao, p.texto_en, p.opcoes_en, p.explicacao_en, p.texto_es, p.opcoes_es, p.explicacao_es,
    (select count(*) from respostas_pergunta r where r.pergunta_id = p.id),
    (select count(*) from respostas_pergunta r where r.pergunta_id = p.id and r.escolha = p.correta)
  from perguntas p order by p.id;
end $$;

create or replace function public.adm_pergunta_salvar(p_id integer, p_dados jsonb)
returns integer language plpgsql security definer set search_path = public, pg_temp as $$
declare v integer;
  v_opcoes text[];
begin
  perform adm_exigir('conteudo.perguntas');
  v_opcoes := array(select jsonb_array_elements_text(p_dados -> 'opcoes'));
  if coalesce(trim(p_dados ->> 'texto'), '') = '' or array_length(v_opcoes, 1) < 2 then raise exception 'Pergunta precisa de texto e pelo menos 2 opções.'; end if;
  if (p_dados ->> 'correta')::int not between 0 and array_length(v_opcoes, 1) - 1 then raise exception 'Marque a opção certa.'; end if;
  v := coalesce(p_id, (select coalesce(max(id), 0) + 1 from perguntas));
  insert into perguntas (id, texto, opcoes, correta, explicacao, texto_en, opcoes_en, explicacao_en, texto_es, opcoes_es, explicacao_es)
  values (v, trim(p_dados ->> 'texto'), v_opcoes, (p_dados ->> 'correta')::smallint, coalesce(p_dados ->> 'explicacao', ''),
          nullif(p_dados ->> 'texto_en', ''), nullif(array(select jsonb_array_elements_text(coalesce(p_dados -> 'opcoes_en', '[]'))), '{}'), nullif(p_dados ->> 'explicacao_en', ''),
          nullif(p_dados ->> 'texto_es', ''), nullif(array(select jsonb_array_elements_text(coalesce(p_dados -> 'opcoes_es', '[]'))), '{}'), nullif(p_dados ->> 'explicacao_es', ''))
  on conflict (id) do update set texto = excluded.texto, opcoes = excluded.opcoes, correta = excluded.correta, explicacao = excluded.explicacao,
    texto_en = excluded.texto_en, opcoes_en = excluded.opcoes_en, explicacao_en = excluded.explicacao_en,
    texto_es = excluded.texto_es, opcoes_es = excluded.opcoes_es, explicacao_es = excluded.explicacao_es;
  perform adm_registrar('pergunta.salvar', v::text, jsonb_build_object('texto', p_dados ->> 'texto'));
  return v;
end $$;

create or replace function public.adm_pergunta_apagar(p_id integer)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform adm_exigir('conteudo.perguntas');
  delete from perguntas where id = p_id;
  perform adm_registrar('pergunta.apagar', p_id::text, null);
end $$;

-- Push: públicos.
create or replace function public.adm_push_alvos(p_publico text, p_idioma text default null)
returns setof uuid language sql stable security definer set search_path = public, pg_temp as $$
  select u.id from users u
  where coalesce(u.banido_ate, '-infinity') < now()
    and (p_idioma is null or p_idioma = '' or coalesce(u.idioma, 'pt') = p_idioma)
    and case p_publico
      when 'todos' then true
      when 'pro' then eh_pro(u.id)
      when 'gratis' then not eh_pro(u.id)
      when 'anonimos' then u.email is null
      when 'novos' then u.created_at > now() - interval '7 days'
      when 'inativos' then coalesce(u.last_active, u.created_at) < now() - interval '7 days'
      when 'sem_treino' then not exists (select 1 from workout_sessions s where s.user_id = u.id and s.completed_at is not null)
      when 'equipe' then exists (select 1 from admin_equipe e where e.user_id = u.id)
      else false end
$$;
revoke all on function public.adm_push_alvos(text, text) from public, anon, authenticated;

create or replace function public.adm_push_contar(p_publico text, p_idioma text default null)
returns bigint language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform adm_exigir('push.enviar');
  return (select count(*) from adm_push_alvos(p_publico, p_idioma));
end $$;

create or replace function public.adm_push_enviar(p_publico text, p_titulo text, p_texto text, p_rota text default '/home', p_idioma text default null)
returns integer language plpgsql security definer set search_path = public, pg_temp as $$
declare v integer;
begin
  perform adm_exigir('push.enviar');
  if coalesce(trim(p_titulo), '') = '' or coalesce(trim(p_texto), '') = '' then raise exception 'Preencha título e texto.'; end if;
  if char_length(p_titulo) > 65 or char_length(p_texto) > 240 then raise exception 'Texto grande demais pro push.'; end if;
  if p_publico = 'eu' then
    insert into push_fila (user_id, titulo, texto, rota) values ((select auth.uid()), trim(p_titulo), trim(p_texto), coalesce(nullif(p_rota, ''), '/home'));
    return 1;
  end if;
  -- Trava: 1 push em massa a cada 10 minutos (evita disparo duplo sem querer).
  if exists (select 1 from admin_log where acao = 'push.enviar' and em > now() - interval '10 minutes') then
    raise exception 'Já saiu um push em massa nos últimos 10 minutos. Espera um pouco.';
  end if;
  insert into push_fila (user_id, titulo, texto, rota)
  select a, trim(p_titulo), trim(p_texto), coalesce(nullif(p_rota, ''), '/home') from adm_push_alvos(p_publico, p_idioma) a;
  get diagnostics v = row_count;
  perform adm_registrar('push.enviar', p_publico, jsonb_build_object('titulo', p_titulo, 'texto', p_texto, 'rota', p_rota, 'idioma', p_idioma, 'enviados', v));
  return v;
end $$;

create or replace function public.adm_push_historico()
returns table (em timestamptz, quem text, publico text, titulo text, texto text, enviados integer)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform adm_exigir('push.enviar');
  return query
  select l.em, u.full_name, l.alvo, l.detalhes ->> 'titulo', l.detalhes ->> 'texto', (l.detalhes ->> 'enviados')::int
  from admin_log l left join users u on u.id = l.user_id
  where l.acao = 'push.enviar' order by l.em desc limit 50;
end $$;

-- ---------------------------------------------------------------------
-- 7. Assinaturas e receita
-- ---------------------------------------------------------------------
create or replace function public.adm_receita()
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform adm_exigir('receita.ver');
  return jsonb_build_object(
    'ativos', (select count(distinct user_id) from user_subscriptions where is_premium and (expiration_date is null or expiration_date > now())),
    'renovam', (select count(distinct user_id) from user_subscriptions where is_premium and expiration_date > now() and coalesce(auto_renew_status, true)),
    'cancelaram', (select count(distinct user_id) from user_subscriptions where is_premium and expiration_date > now() and auto_renew_status = false),
    'expirados_30d', (select count(distinct user_id) from user_subscriptions where expiration_date between now() - interval '30 days' and now()),
    'cortesias', (select count(*) from pro_cortesia where ate > now()),
    'por_plano', (select coalesce(jsonb_agg(x), '[]') from (
        select coalesce(product_id, '—') plano, coalesce(currency, '—') moeda, count(*) qtd, sum(coalesce(price_cents, 0)) total_cents
        from user_subscriptions where is_premium and (expiration_date is null or expiration_date > now())
        group by 1, 2 order by 3 desc) x),
    -- Receita mensal recorrente estimada por moeda (anual dividido por 12).
    'mrr', (select coalesce(jsonb_object_agg(moeda, cents), '{}') from (
        select coalesce(currency, 'BRL') moeda,
          round(sum(case when product_id ilike '%anual%' or product_id ilike '%year%' or product_id ilike '%annual%' then coalesce(price_cents, 0) / 12.0 else coalesce(price_cents, 0) end)) cents
        from user_subscriptions where is_premium and expiration_date > now() and coalesce(auto_renew_status, true)
        group by 1) m),
    'assinantes', (select coalesce(jsonb_agg(a order by a.compra desc), '[]') from (
        select s.user_id, u.full_name nome, u.email, s.product_id plano, s.price_cents, s.currency moeda, s.purchase_date compra,
          s.expiration_date expira, s.auto_renew_status renova, s.is_premium ativo
        from user_subscriptions s left join users u on u.id = s.user_id
        order by s.purchase_date desc nulls last limit 200) a),
    'por_mes', (select coalesce(jsonb_agg(m order by m.mes), '[]') from (
        select to_char(date_trunc('month', purchase_date), 'YYYY-MM') mes, count(*) novas, sum(coalesce(price_cents, 0)) cents
        from user_subscriptions where purchase_date > now() - interval '12 months'
        group by 1) m)
  );
end $$;

-- ---------------------------------------------------------------------
-- 8. Custo da IA (as funções do servidor gravam cada chamada)
-- ---------------------------------------------------------------------
create table if not exists public.ia_uso (
  id bigserial primary key,
  user_id uuid references auth.users(id) on delete set null,
  funcao text not null,
  modelo text,
  tokens_entrada integer not null default 0,
  tokens_saida integer not null default 0,
  custo_usd numeric(12, 6) not null default 0,
  em timestamptz not null default now()
);
create index if not exists ia_uso_em_idx on public.ia_uso (em desc);
create index if not exists ia_uso_user_idx on public.ia_uso (user_id, em desc);
alter table public.ia_uso enable row level security;
revoke all on public.ia_uso from anon, authenticated;

-- Preço por 1 milhão de tokens (US$). Calcula o custo na hora de gravar.
create or replace function public.ia_custo(p_modelo text, p_in integer, p_out integer)
returns numeric language sql immutable as $$
  select round((
    case
      when p_modelo like 'gpt-4o-mini%' then p_in * 0.15 + p_out * 0.60
      when p_modelo like 'gpt-4o%' then p_in * 2.50 + p_out * 10.00
      when p_modelo like 'gpt-4.1-mini%' then p_in * 0.40 + p_out * 1.60
      when p_modelo like 'gpt-4.1-nano%' then p_in * 0.10 + p_out * 0.40
      when p_modelo like 'gpt-4.1%' then p_in * 2.00 + p_out * 8.00
      when p_modelo like 'gpt-5-mini%' then p_in * 0.25 + p_out * 2.00
      when p_modelo like 'gpt-5-nano%' then p_in * 0.05 + p_out * 0.40
      when p_modelo like 'gpt-5%' then p_in * 1.25 + p_out * 10.00
      when p_modelo like 'whisper%' or p_modelo like 'tts%' then 0
      else p_in * 2.50 + p_out * 10.00
    end / 1000000.0)::numeric, 6)
$$;

create or replace function public.ia_registrar(p_user uuid, p_funcao text, p_modelo text, p_in integer, p_out integer)
returns void language sql security definer set search_path = public, pg_temp as $$
  insert into ia_uso (user_id, funcao, modelo, tokens_entrada, tokens_saida, custo_usd)
  values (p_user, p_funcao, p_modelo, coalesce(p_in, 0), coalesce(p_out, 0), ia_custo(p_modelo, coalesce(p_in, 0), coalesce(p_out, 0)));
$$;
revoke all on function public.ia_registrar(uuid, text, text, integer, integer) from public, anon, authenticated;

create or replace function public.adm_ia(p_dias integer default 30)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_desde timestamptz := now() - make_interval(days => least(p_dias, 365));
begin
  perform adm_exigir('ia.ver');
  return jsonb_build_object(
    'custo_total', (select coalesce(sum(custo_usd), 0) from ia_uso where em > v_desde),
    'chamadas', (select count(*) from ia_uso where em > v_desde),
    'custo_hoje', (select coalesce(sum(custo_usd), 0) from ia_uso where em > now() - interval '1 day'),
    'custo_mes', (select coalesce(sum(custo_usd), 0) from ia_uso where em >= date_trunc('month', now())),
    'desde_registro', (select min(em) from ia_uso),
    'por_dia', (select coalesce(jsonb_agg(d order by d.dia), '[]') from (
        select (em at time zone 'America/Sao_Paulo')::date dia, count(*) chamadas, sum(custo_usd) custo
        from ia_uso where em > v_desde group by 1) d),
    'por_funcao', (select coalesce(jsonb_agg(f order by f.custo desc), '[]') from (
        select funcao, modelo, count(*) chamadas, sum(tokens_entrada) tokens_in, sum(tokens_saida) tokens_out, sum(custo_usd) custo
        from ia_uso where em > v_desde group by 1, 2) f),
    'top_usuarios', (select coalesce(jsonb_agg(t order by t.custo desc), '[]') from (
        select i.user_id, u.full_name nome, u.email, eh_pro(i.user_id) pro, count(*) chamadas, sum(i.custo_usd) custo
        from ia_uso i left join users u on u.id = i.user_id
        where i.em > v_desde group by 1, 2, 3 order by 6 desc limit 20) t),
    -- Antes de existir o registro de tokens: contagem de uso pelos limites.
    'contadores', (select coalesce(jsonb_agg(c), '[]') from (
        select feature, sum(count) usos from usage_counters where period_start > (v_desde)::date group by 1 order by 2 desc) c),
    'mensagens_coach', (select count(*) from chat_messages where is_user and created_at > v_desde)
  );
end $$;

-- ---------------------------------------------------------------------
-- 9. Controle remoto do app (o app lê sem login)
-- ---------------------------------------------------------------------
create table if not exists public.app_config (
  chave text primary key,
  valor jsonb not null,
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid references public.users(id) on delete set null
);
alter table public.app_config enable row level security;
drop policy if exists "config: todos leem" on public.app_config;
create policy "config: todos leem" on public.app_config for select to anon, authenticated using (true);
revoke insert, update, delete on public.app_config from anon, authenticated;
grant select on public.app_config to anon, authenticated;

insert into public.app_config (chave, valor) values
  ('manutencao', '{"ativo": false, "titulo": "Voltamos já", "mensagem": "O BroGym está em manutenção rápida. Tenta de novo em alguns minutos."}'),
  ('versao_minima', '{"build": 0, "mensagem": "Tem versão nova do BroGym. Atualiza pra continuar treinando."}'),
  ('aviso', '{"ativo": false, "titulo": "", "texto": "", "rota": "", "botao": "", "cor": "#E11D2D", "ate": null, "publico": "todos"}')
on conflict (chave) do nothing;

create or replace function public.adm_config_salvar(p_chave text, p_valor jsonb)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_antes jsonb;
begin
  perform adm_exigir('app.config');
  if p_chave not in ('manutencao', 'versao_minima', 'aviso') then raise exception 'Chave desconhecida.'; end if;
  select valor into v_antes from app_config where chave = p_chave;
  insert into app_config (chave, valor, atualizado_em, atualizado_por) values (p_chave, p_valor, now(), (select auth.uid()))
  on conflict (chave) do update set valor = excluded.valor, atualizado_em = now(), atualizado_por = excluded.atualizado_por;
  perform adm_registrar('config.' || p_chave, p_chave, jsonb_build_object('antes', v_antes, 'depois', p_valor));
end $$;

-- ---------------------------------------------------------------------
-- 10. Suporte e feedback (o app abre chamado; o time responde no painel)
-- ---------------------------------------------------------------------
create table if not exists public.suporte_tickets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  tipo text not null default 'duvida' check (tipo in ('bug', 'duvida', 'sugestao', 'pagamento', 'outro')),
  assunto text not null check (char_length(assunto) between 2 and 120),
  status text not null default 'aberto' check (status in ('aberto', 'respondido', 'fechado')),
  versao_app text,
  aparelho text,
  responsavel uuid references public.users(id) on delete set null,
  nao_lido_usuario boolean not null default false,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create index if not exists suporte_tickets_user_idx on public.suporte_tickets (user_id, atualizado_em desc);
create index if not exists suporte_tickets_status_idx on public.suporte_tickets (status, atualizado_em desc);

create table if not exists public.suporte_mensagens (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references public.suporte_tickets(id) on delete cascade,
  autor_id uuid references public.users(id) on delete set null,
  do_time boolean not null default false,
  texto text not null check (char_length(texto) between 1 and 4000),
  imagem_url text,
  criado_em timestamptz not null default now()
);
create index if not exists suporte_mensagens_ticket_idx on public.suporte_mensagens (ticket_id, criado_em);

alter table public.suporte_tickets enable row level security;
alter table public.suporte_mensagens enable row level security;
drop policy if exists "tickets: dono ve" on public.suporte_tickets;
create policy "tickets: dono ve" on public.suporte_tickets for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists "mensagens: dono ve" on public.suporte_mensagens;
create policy "mensagens: dono ve" on public.suporte_mensagens for select to authenticated
  using (exists (select 1 from suporte_tickets t where t.id = ticket_id and t.user_id = (select auth.uid())));
revoke insert, update, delete on public.suporte_tickets, public.suporte_mensagens from anon, authenticated;
revoke all on public.suporte_tickets, public.suporte_mensagens from anon;

-- App: abrir chamado.
create or replace function public.suporte_abrir(p_tipo text, p_texto text, p_versao text default null, p_aparelho text default null, p_imagem text default null)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare v uuid; v_eu uuid := (select auth.uid());
begin
  if v_eu is null then raise exception 'Faça login.'; end if;
  if coalesce(trim(p_texto), '') = '' then raise exception 'Escreva sua mensagem.'; end if;
  if (select count(*) from suporte_tickets where user_id = v_eu and criado_em > now() - interval '1 day') >= 5 then
    raise exception 'Você já abriu vários chamados hoje. Responde num que já está aberto.';
  end if;
  insert into suporte_tickets (user_id, tipo, assunto, versao_app, aparelho)
  values (v_eu, case when p_tipo in ('bug', 'duvida', 'sugestao', 'pagamento', 'outro') then p_tipo else 'outro' end,
          left(regexp_replace(trim(p_texto), '\s+', ' ', 'g'), 80), left(p_versao, 40), left(p_aparelho, 120))
  returning id into v;
  insert into suporte_mensagens (ticket_id, autor_id, texto, imagem_url) values (v, v_eu, left(trim(p_texto), 4000), p_imagem);
  -- Avisa quem atende o suporte.
  insert into push_fila (user_id, titulo, texto, rota)
  select e.user_id, 'Novo chamado no BroGym', left(trim(p_texto), 120), '/home'
  from admin_equipe e where e.ativo and (e.dono or exists (select 1 from admin_permissoes p where p.user_id = e.user_id and p.permissao = 'suporte.atender'));
  return v;
end $$;

-- App: responder no próprio chamado.
create or replace function public.suporte_responder(p_ticket uuid, p_texto text, p_imagem text default null)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not exists (select 1 from suporte_tickets where id = p_ticket and user_id = (select auth.uid())) then raise exception 'Chamado não encontrado.'; end if;
  if coalesce(trim(p_texto), '') = '' then raise exception 'Escreva sua mensagem.'; end if;
  insert into suporte_mensagens (ticket_id, autor_id, texto, imagem_url) values (p_ticket, (select auth.uid()), left(trim(p_texto), 4000), p_imagem);
  update suporte_tickets set status = 'aberto', atualizado_em = now() where id = p_ticket;
end $$;

create or replace function public.suporte_marcar_lido(p_ticket uuid)
returns void language sql security definer set search_path = public, pg_temp as $$
  update suporte_tickets set nao_lido_usuario = false where id = p_ticket and user_id = (select auth.uid());
$$;

create or replace function public.suporte_nao_lidos()
returns integer language sql stable security definer set search_path = public, pg_temp as $$
  select count(*)::int from suporte_tickets where user_id = (select auth.uid()) and nao_lido_usuario;
$$;

-- Painel.
create or replace function public.adm_chamados(p_status text default 'aberto')
returns table (id uuid, user_id uuid, nome text, email text, avatar text, tipo text, assunto text, status text, versao_app text, aparelho text,
               responsavel text, mensagens bigint, ultima text, criado_em timestamptz, atualizado_em timestamptz)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform adm_exigir('suporte.atender');
  return query
  select t.id, t.user_id, u.full_name, u.email, u.avatar_url, t.tipo, t.assunto, t.status, t.versao_app, t.aparelho, r.full_name,
    (select count(*) from suporte_mensagens m where m.ticket_id = t.id),
    (select m.texto from suporte_mensagens m where m.ticket_id = t.id order by m.criado_em desc limit 1),
    t.criado_em, t.atualizado_em
  from suporte_tickets t left join users u on u.id = t.user_id left join users r on r.id = t.responsavel
  where p_status is null or p_status = 'todos' or t.status = p_status
  order by t.atualizado_em desc limit 300;
end $$;

create or replace function public.adm_chamado(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform adm_exigir('suporte.atender');
  return (select jsonb_build_object(
    'chamado', to_jsonb(t),
    'usuario', jsonb_build_object('id', u.id, 'nome', u.full_name, 'email', u.email, 'avatar', u.avatar_url, 'idioma', u.idioma, 'pro', eh_pro(u.id)),
    'mensagens', (select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'texto', m.texto, 'imagem', m.imagem_url, 'do_time', m.do_time,
                    'autor', a.full_name, 'em', m.criado_em) order by m.criado_em), '[]')
                  from suporte_mensagens m left join users a on a.id = m.autor_id where m.ticket_id = t.id)
  ) from suporte_tickets t join users u on u.id = t.user_id where t.id = p_id);
end $$;

create or replace function public.adm_chamado_responder(p_id uuid, p_texto text, p_fechar boolean default false)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_user uuid;
begin
  perform adm_exigir('suporte.atender');
  if coalesce(trim(p_texto), '') = '' then raise exception 'Escreva a resposta.'; end if;
  insert into suporte_mensagens (ticket_id, autor_id, do_time, texto) values (p_id, (select auth.uid()), true, left(trim(p_texto), 4000));
  update suporte_tickets set status = case when p_fechar then 'fechado' else 'respondido' end, responsavel = (select auth.uid()),
    nao_lido_usuario = true, atualizado_em = now()
  where id = p_id returning user_id into v_user;
  insert into push_fila (user_id, titulo, texto, rota) values (v_user, 'O time BroGym te respondeu 💬', left(trim(p_texto), 120), '/suporte');
  perform adm_registrar('suporte.responder', p_id::text, jsonb_build_object('fechar', p_fechar));
end $$;

create or replace function public.adm_chamado_status(p_id uuid, p_status text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform adm_exigir('suporte.atender');
  update suporte_tickets set status = p_status, atualizado_em = now() where id = p_id;
  perform adm_registrar('suporte.status', p_id::text, jsonb_build_object('status', p_status));
end $$;

-- ---------------------------------------------------------------------
-- 11. Mídias do painel (capas de evento, mídias de exercício)
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('admin-midias', 'admin-midias', true, 20971520, array['image/webp', 'image/png', 'image/jpeg', 'image/gif', 'video/mp4'])
on conflict (id) do nothing;

drop policy if exists "admin-midias: equipe envia" on storage.objects;
create policy "admin-midias: equipe envia" on storage.objects for insert to authenticated
  with check (bucket_id = 'admin-midias' and (public.adm_ok('conteudo.exercicios') or public.adm_ok('conteudo.eventos') or public.adm_ok('comunidade.moderar')));
drop policy if exists "admin-midias: equipe troca" on storage.objects;
create policy "admin-midias: equipe troca" on storage.objects for update to authenticated
  using (bucket_id = 'admin-midias' and (public.adm_ok('conteudo.exercicios') or public.adm_ok('conteudo.eventos') or public.adm_ok('comunidade.moderar')));

-- Prints do suporte: privados. Só quem mandou e quem atende o suporte abrem (link assinado).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('suporte', 'suporte', false, 10485760, array['image/webp', 'image/png', 'image/jpeg'])
on conflict (id) do nothing;
drop policy if exists "suporte: dono envia" on storage.objects;
create policy "suporte: dono envia" on storage.objects for insert to authenticated
  with check (bucket_id = 'suporte' and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists "suporte: dono e time veem" on storage.objects;
create policy "suporte: dono e time veem" on storage.objects for select to authenticated
  using (bucket_id = 'suporte' and ((storage.foldername(name))[1] = (select auth.uid())::text or public.adm_ok('suporte.atender')));

-- ---------------------------------------------------------------------
-- 12. Permissões de execução
-- ---------------------------------------------------------------------
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and (p.proname like 'adm\_%' or p.proname like 'suporte\_%')
      and p.proname not in ('adm_registrar', 'adm_push_alvos')
  loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
revoke all on function public.adm_registrar(text, text, jsonb) from public, anon, authenticated;
revoke all on function public.adm_push_alvos(text, text) from public, anon, authenticated;
grant execute on function public.adm_ok(text) to authenticated;

-- ---------------------------------------------------------------------
-- 13. Dono inicial: Emerson
-- ---------------------------------------------------------------------
insert into public.admin_equipe (user_id, dono, cargo)
select id, true, 'Dono' from public.users where lower(email) = 'emersonsousa.vale@gmail.com'
on conflict (user_id) do update set dono = true, ativo = true;
