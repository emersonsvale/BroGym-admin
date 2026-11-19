-- Lista de usuários: quando terminou o onboarding.
-- Data exata vem do funil (evento "onboarding", desde a 2.0.6). Pra contas antigas que já tinham
-- terminado (users.onboarded) a data é estimada pelo 1º treino gerado pela IA (o fim do onboarding gera os treinos).

drop function if exists public.adm_usuarios(text, text, integer, integer, text);
create or replace function public.adm_usuarios(p_busca text default null, p_filtro text default 'todos', p_limite integer default 50, p_offset integer default 0, p_ordem text default 'criado_desc')
returns table (id uuid, nome text, email text, username text, avatar text, criado_em timestamptz, ultimo_acesso timestamptz,
               treinos integer, pro text, banido_ate timestamptz, origem text, idioma text, cidade text, total bigint,
               onboarding_em timestamptz, onboarding_feito boolean, onboarding_aprox boolean)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform adm_exigir('usuarios.ver');
  return query
  with base as (
    select u.*, public.ultimo_acesso(u.id) as acesso,
      case when exists (select 1 from user_subscriptions s where s.user_id = u.id and s.is_premium and (s.expiration_date is null or s.expiration_date > now())) then 'pago'
           when exists (select 1 from pro_cortesia c where c.user_id = u.id and c.ate > now()) then 'cortesia'
           else null end as pro_tipo,
      (select min(fe.em) from funil_eventos fe where fe.user_id = u.id and fe.evento = 'onboarding') as onb_exato,
      (select min(w.created_at) from workouts w where w.user_id = u.id and w.is_ai_generated) as onb_ia
    from users u
    where (p_busca is null or trim(p_busca) = ''
           or u.full_name ilike '%' || trim(p_busca) || '%'
           or u.email ilike '%' || trim(p_busca) || '%'
           or u.username ilike '%' || ltrim(trim(p_busca), '@') || '%'
           or u.id::text = trim(p_busca))
  ), b2 as (
    select b.*,
      (b.onb_exato is not null or coalesce(b.onboarded, false)) as onb_feito,
      coalesce(b.onb_exato, case when coalesce(b.onboarded, false) then b.onb_ia end) as onb_em,
      (b.onb_exato is null and coalesce(b.onboarded, false)) as onb_aprox
    from base b
  ), f as (
    select * from b2 b where case coalesce(p_filtro, 'todos')
      when 'pro' then b.pro_tipo is not null
      when 'pagos' then b.pro_tipo = 'pago'
      when 'anonimos' then b.email is null
      when 'banidos' then b.banido_ate > now()
      when 'novos' then b.created_at > now() - interval '7 days'
      when 'inativos' then coalesce(b.acesso, b.created_at) < now() - interval '14 days'
      when 'sem_onboarding' then not b.onb_feito
      else true end
  )
  select f.id, f.full_name, f.email, f.username, f.avatar_url, f.created_at, f.acesso, f.total_workouts,
    f.pro_tipo, f.banido_ate, f.origem, f.idioma, f.cidade, count(*) over (),
    f.onb_em, f.onb_feito, f.onb_aprox
  from f
  order by
    case when p_ordem = 'acesso_desc' then f.acesso end desc nulls last,
    case when p_ordem = 'acesso_asc' then f.acesso end asc nulls first,
    case when p_ordem = 'treinos_desc' then f.total_workouts end desc nulls last,
    case when p_ordem = 'treinos_asc' then f.total_workouts end asc nulls first,
    case when p_ordem = 'onboarding_desc' then f.onb_em end desc nulls last,
    case when p_ordem = 'onboarding_asc' then f.onb_em end asc nulls last,
    case when p_ordem like 'onboarding%' then f.onb_feito end desc,
    case when p_ordem = 'nome_asc' then lower(coalesce(f.full_name, f.email, 'zzz')) end asc,
    case when p_ordem = 'nome_desc' then lower(coalesce(f.full_name, f.email, '')) end desc,
    case when p_ordem = 'criado_asc' then f.created_at end asc,
    f.created_at desc
  limit least(coalesce(p_limite, 50), 200) offset greatest(coalesce(p_offset, 0), 0);
end $$;
revoke all on function public.adm_usuarios(text, text, integer, integer, text) from public, anon;
grant execute on function public.adm_usuarios(text, text, integer, integer, text) to authenticated;
notify pgrst, 'reload schema';
