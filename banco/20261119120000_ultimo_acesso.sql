-- Último acesso de verdade. users.last_active só é gravado no login, então fica velho.
-- Aqui vale o sinal mais recente: sessão renovada (o app renova enquanto está aberto),
-- login, treino começado, post ou o próprio last_active.

create or replace function public.ultimo_acesso(p_user uuid)
returns timestamptz language sql stable security definer set search_path = public, auth, pg_temp as $$
  select greatest(
    (select u.last_active from public.users u where u.id = p_user),
    (select a.last_sign_in_at from auth.users a where a.id = p_user),
    (select max(coalesce(s.refreshed_at, s.updated_at, s.created_at)) from auth.sessions s where s.user_id = p_user),
    (select max(w.started_at) from public.workout_sessions w where w.user_id = p_user),
    (select max(p.created_at) from public.community_posts p where p.user_id = p_user)
  )
$$;
revoke all on function public.ultimo_acesso(uuid) from public, anon, authenticated;

-- Lista de usuários com ordenação. p_ordem: criado_desc (padrão), criado_asc, acesso_desc, acesso_asc,
-- treinos_desc, treinos_asc, nome_asc, nome_desc.
drop function if exists public.adm_usuarios(text, text, integer, integer);
create or replace function public.adm_usuarios(p_busca text default null, p_filtro text default 'todos', p_limite integer default 50, p_offset integer default 0, p_ordem text default 'criado_desc')
returns table (id uuid, nome text, email text, username text, avatar text, criado_em timestamptz, ultimo_acesso timestamptz,
               treinos integer, pro text, banido_ate timestamptz, origem text, idioma text, cidade text, total bigint)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform adm_exigir('usuarios.ver');
  return query
  with base as (
    select u.*, public.ultimo_acesso(u.id) as acesso,
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
      when 'inativos' then coalesce(b.acesso, b.created_at) < now() - interval '14 days'
      else true end
  )
  select f.id, f.full_name, f.email, f.username, f.avatar_url, f.created_at, f.acesso, f.total_workouts,
    f.pro_tipo, f.banido_ate, f.origem, f.idioma, f.cidade, count(*) over ()
  from f
  order by
    case when p_ordem = 'acesso_desc' then f.acesso end desc nulls last,
    case when p_ordem = 'acesso_asc' then f.acesso end asc nulls first,
    case when p_ordem = 'treinos_desc' then f.total_workouts end desc nulls last,
    case when p_ordem = 'treinos_asc' then f.total_workouts end asc nulls first,
    case when p_ordem = 'nome_asc' then lower(coalesce(f.full_name, f.email, 'zzz')) end asc,
    case when p_ordem = 'nome_desc' then lower(coalesce(f.full_name, f.email, '')) end desc,
    case when p_ordem = 'criado_asc' then f.created_at end asc,
    f.created_at desc
  limit least(coalesce(p_limite, 50), 200) offset greatest(coalesce(p_offset, 0), 0);
end $$;
revoke all on function public.adm_usuarios(text, text, integer, integer, text) from public, anon;
grant execute on function public.adm_usuarios(text, text, integer, integer, text) to authenticated;

-- Resumo e ficha do usuário passam a usar o último acesso de verdade.
create or replace function public.adm_resumo()
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v jsonb;
begin
  perform adm_exigir('numeros.ver');
  with a as (select public.ultimo_acesso(id) as acesso from users)
  select jsonb_build_object(
    'usuarios', (select count(*) from users),
    'salvos', (select count(*) from users where email is not null),
    'anonimos', (select count(*) from users where email is null),
    'novos_hoje', (select count(*) from users where created_at >= date_trunc('day', now() at time zone 'America/Sao_Paulo') at time zone 'America/Sao_Paulo'),
    'novos_7d', (select count(*) from users where created_at > now() - interval '7 days'),
    'novos_30d', (select count(*) from users where created_at > now() - interval '30 days'),
    'ativos_hoje', (select count(*) from a where acesso > now() - interval '1 day'),
    'ativos_7d', (select count(*) from a where acesso > now() - interval '7 days'),
    'ativos_30d', (select count(*) from a where acesso > now() - interval '30 days'),
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

-- Ficha: mesmo cálculo no campo last_active devolvido pro painel.
create or replace function public.adm_usuario_acesso(p_id uuid)
returns timestamptz language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform adm_exigir('usuarios.ver');
  return public.ultimo_acesso(p_id);
end $$;
revoke all on function public.adm_usuario_acesso(uuid) from public, anon;
grant execute on function public.adm_usuario_acesso(uuid) to authenticated;

-- Público "sumidos" do push também usa o último acesso de verdade.
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
      when 'inativos' then coalesce(public.ultimo_acesso(u.id), u.created_at) < now() - interval '7 days'
      when 'sem_treino' then not exists (select 1 from workout_sessions s where s.user_id = u.id and s.completed_at is not null)
      when 'equipe' then exists (select 1 from admin_equipe e where e.user_id = u.id)
      else false end
$$;
revoke all on function public.adm_push_alvos(text, text) from public, anon, authenticated;
