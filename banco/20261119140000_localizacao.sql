-- De onde são os usuários.
-- 1) Pelo IP do último login (auth.sessions): país, estado e cidade via freeipapi.com
--    (sem chave, uso comercial liberado no plano grátis, 60/min). Roda sozinho a cada 2 min
--    pelo pg_net: lê as respostas da rodada anterior e pede até 30 novos.
-- 2) Pelo aparelho (região configurada no celular), a partir da versão do app que chama
--    definir_pais_aparelho. Quando existe, é o país que vale.
-- Cidade pelo IP é aproximada (internet móvel costuma cair na cidade da operadora).

alter table public.users add column if not exists pais_ip text;
alter table public.users add column if not exists estado text;
alter table public.users add column if not exists pais_aparelho text;
alter table public.users add column if not exists geo_ip text;
alter table public.users add column if not exists geo_rede text;
alter table public.users add column if not exists geo_em timestamptz;
-- users.cidade já existia (vazia): passa a ser preenchida pelo IP.

create or replace function public.definir_pais_aparelho(p_pais text)
returns void language sql security definer set search_path = public, pg_temp as $$
  update users set pais_aparelho = upper(p_pais)
  where id = auth.uid() and p_pais ~* '^[a-z]{2}$' and pais_aparelho is distinct from upper(p_pais);
$$;
revoke all on function public.definir_pais_aparelho(text) from public, anon;
grant execute on function public.definir_pais_aparelho(text) to authenticated;

create table if not exists public.geo_pedidos (
  req_id bigint primary key,
  user_id uuid not null,
  ip text not null,
  em timestamptz not null default now()
);
alter table public.geo_pedidos enable row level security;

create or replace function public.geo_ip_atual(p_user uuid)
returns text language sql stable security definer set search_path = public, pg_temp as $$
  select host(s.ip) from auth.sessions s
  where s.user_id = p_user and s.ip is not null
  order by coalesce(s.updated_at, s.created_at) desc nulls last
  limit 1;
$$;
revoke all on function public.geo_ip_atual(uuid) from public, anon, authenticated;

create or replace function public.geo_processar()
returns integer language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r record;
  j jsonb;
  n integer := 0;
begin
  -- Respostas da rodada anterior.
  for r in
    select p.req_id, p.user_id, p.ip, h.status_code, h.content
    from geo_pedidos p join net._http_response h on h.id = p.req_id
  loop
    if r.status_code = 200 then
      begin
        j := r.content::jsonb;
      exception when others then
        j := null;
      end;
      update users u set
        pais_ip = nullif(nullif(upper(j ->> 'countryCode'), ''), '-'),
        estado = nullif(nullif(j ->> 'regionName', ''), '-'),
        cidade = nullif(nullif(j ->> 'cityName', ''), '-'),
        geo_rede = nullif(j ->> 'asnOrganization', ''),
        geo_ip = r.ip,
        geo_em = now()
      where u.id = r.user_id;
    end if;
    delete from geo_pedidos where req_id = r.req_id;
  end loop;
  -- Pedido que nunca respondeu: libera pra tentar de novo.
  delete from geo_pedidos where em < now() - interval '30 minutes';

  -- Novos pedidos: quem nunca foi localizado ou trocou de IP (no máximo 1x por dia).
  for r in
    select x.id, x.ip from (
      select u.id, u.geo_ip, u.geo_em, public.geo_ip_atual(u.id) as ip
      from users u
      where not exists (select 1 from geo_pedidos g where g.user_id = u.id)
    ) x
    where x.ip is not null
      and (x.geo_ip is null or (x.geo_ip <> x.ip and x.geo_em < now() - interval '1 day'))
    limit 30
  loop
    insert into geo_pedidos (req_id, user_id, ip)
    values (net.http_get('https://free.freeipapi.com/api/json/' || r.ip, timeout_milliseconds := 10000), r.id, r.ip);
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.geo_processar() from public, anon, authenticated;

select cron.unschedule('geo_processar') where exists (select 1 from cron.job where jobname = 'geo_processar');
select cron.schedule('geo_processar', '*/2 * * * *', 'select public.geo_processar()');

-- Lista do painel: país, estado, cidade, fonte e rede; filtro por país; ordem por local.
drop function if exists public.adm_usuarios(text, text, integer, integer, text);
create or replace function public.adm_usuarios(p_busca text default null, p_filtro text default 'todos', p_limite integer default 50, p_offset integer default 0, p_ordem text default 'criado_desc', p_pais text default null)
returns table (id uuid, nome text, email text, username text, avatar text, criado_em timestamptz, ultimo_acesso timestamptz,
               treinos integer, pro text, banido_ate timestamptz, origem text, idioma text, cidade text, total bigint,
               onboarding_em timestamptz, onboarding_feito boolean, onboarding_aprox boolean,
               pais text, estado text, pais_fonte text, rede text)
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
      (select min(w.created_at) from workouts w where w.user_id = u.id and w.is_ai_generated) as onb_ia,
      coalesce(u.pais_aparelho, u.pais_ip) as pais_final
    from users u
    where (p_busca is null or trim(p_busca) = ''
           or u.full_name ilike '%' || trim(p_busca) || '%'
           or u.email ilike '%' || trim(p_busca) || '%'
           or u.username ilike '%' || ltrim(trim(p_busca), '@') || '%'
           or u.cidade ilike '%' || trim(p_busca) || '%'
           or u.id::text = trim(p_busca))
      and (p_pais is null or p_pais = '' or (p_pais = '??' and coalesce(u.pais_aparelho, u.pais_ip) is null)
           or coalesce(u.pais_aparelho, u.pais_ip) = upper(p_pais))
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
    f.onb_em, f.onb_feito, f.onb_aprox,
    f.pais_final, f.estado,
    case when f.pais_aparelho is not null then 'aparelho' when f.pais_ip is not null then 'ip' end,
    f.geo_rede
  from f
  order by
    case when p_ordem = 'acesso_desc' then f.acesso end desc nulls last,
    case when p_ordem = 'acesso_asc' then f.acesso end asc nulls first,
    case when p_ordem = 'treinos_desc' then f.total_workouts end desc nulls last,
    case when p_ordem = 'treinos_asc' then f.total_workouts end asc nulls first,
    case when p_ordem = 'onboarding_desc' then f.onb_em end desc nulls last,
    case when p_ordem = 'onboarding_asc' then f.onb_em end asc nulls last,
    case when p_ordem like 'onboarding%' then f.onb_feito end desc,
    case when p_ordem = 'local_asc' then f.pais_final end asc nulls last,
    case when p_ordem = 'local_desc' then f.pais_final end desc nulls last,
    case when p_ordem like 'local%' then lower(f.cidade) end asc nulls last,
    case when p_ordem = 'nome_asc' then lower(coalesce(f.full_name, f.email, 'zzz')) end asc,
    case when p_ordem = 'nome_desc' then lower(coalesce(f.full_name, f.email, '')) end desc,
    case when p_ordem = 'criado_asc' then f.created_at end asc,
    f.created_at desc
  limit least(coalesce(p_limite, 50), 200) offset greatest(coalesce(p_offset, 0), 0);
end $$;
revoke all on function public.adm_usuarios(text, text, integer, integer, text, text) from public, anon;
grant execute on function public.adm_usuarios(text, text, integer, integer, text, text) to authenticated;

-- Início: países e cidades.
create or replace function public.adm_distribuicao()
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform adm_exigir('numeros.ver');
  return jsonb_build_object(
    'idioma', (select jsonb_object_agg(k, n) from (select coalesce(idioma, 'pt') k, count(*) n from users group by 1) x),
    'sexo', (select jsonb_object_agg(k, n) from (select coalesce(nullif(gender, ''), '—') k, count(*) n from users group by 1) x),
    'objetivo', (select jsonb_object_agg(k, n) from (select coalesce(fitness_goals[1], '—') k, count(*) n from users group by 1) x),
    'pais', (select coalesce(jsonb_agg(jsonb_build_object('pais', k, 'n', n) order by n desc, k), '[]') from (
        select coalesce(pais_aparelho, pais_ip, '??') k, count(*) n from users group by 1) x),
    'cidade', (select jsonb_object_agg(k, n) from (
        select coalesce(nullif(cidade, ''), '—') || coalesce(' · ' || coalesce(pais_aparelho, pais_ip), '') k, count(*) n
        from users group by 1 order by 2 desc limit 15) x),
    'cidades', (select coalesce(jsonb_agg(jsonb_build_object('cidade', c, 'estado', e, 'pais', p, 'n', n) order by n desc, c), '[]') from (
        select cidade c, max(estado) e, coalesce(pais_aparelho, pais_ip) p, count(*) n
        from users where cidade is not null group by 1, 3 order by 4 desc, 1 limit 12) x)
  );
end $$;

notify pgrst, 'reload schema';
