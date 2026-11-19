-- Contas sem cadastro (anônimas, do "Começar agora").
-- 1) Lembrete: 1 push (de dia) entre 20 h e 48 h depois de criar a conta, pra quem ainda não salvou com o Google.
-- 2) Limpeza: conta anônima com mais de 30 dias, sem salvar e sem nenhum treino concluído, é apagada (1x por dia).

create or replace function public.lembrar_salvar_conta()
returns integer language plpgsql security definer set search_path = public, auth, pg_temp as $$
declare n integer;
begin
  insert into push_fila (user_id, titulo, texto, rota)
  select u.id,
    case coalesce(u.idioma, 'pt') when 'en' then 'Your workout is waiting 💪' when 'es' then 'Tu entrenamiento te espera 💪' else 'Seu treino está te esperando 💪' end,
    case coalesce(u.idioma, 'pt')
      when 'en' then 'Save your account with Google so you don''t lose your plan and your points.'
      when 'es' then 'Guarda tu cuenta con Google para no perder tu plan y tus puntos.'
      else 'Salva sua conta com o Google pra não perder o seu plano e os seus pontos.' end,
    '/home'
  from public.users u
  join auth.users a on a.id = u.id
  where a.is_anonymous
    and u.email is null
    and a.created_at between now() - interval '48 hours' and now() - interval '20 hours'
    and coalesce(u.banido_ate, '-infinity') < now()
    -- Só manda de dia (9h às 21h de Brasília). A janela de 28 h garante que todo mundo cai num horário bom.
    and extract(hour from now() at time zone 'America/Sao_Paulo') between 9 and 21
    and not exists (
      select 1 from push_fila f where f.user_id = u.id
        and f.titulo in ('Your workout is waiting 💪', 'Tu entrenamiento te espera 💪', 'Seu treino está te esperando 💪')
    );
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.lembrar_salvar_conta() from public, anon, authenticated;

create or replace function public.limpar_anonimos()
returns integer language plpgsql security definer set search_path = public, auth, pg_temp as $$
declare r record; n integer := 0;
begin
  for r in
    select a.id from auth.users a join public.users u on u.id = a.id
    where a.is_anonymous
      and u.email is null
      and a.created_at < now() - interval '30 days'
      and not exists (select 1 from workout_sessions s where s.user_id = a.id and s.completed_at is not null)
      and not exists (select 1 from admin_equipe e where e.user_id = a.id)
  loop
    begin
      delete from public.users where id = r.id;
      delete from auth.users where id = r.id;
      n := n + 1;
    exception when others then
      -- Alguma tabela antiga segurando a conta: pula e tenta de novo amanhã.
      null;
    end;
  end loop;
  if n > 0 then
    insert into admin_log (user_id, acao, alvo, detalhes) values (null, 'sistema.limpar_anonimos', null, jsonb_build_object('apagadas', n));
  end if;
  return n;
end $$;
revoke all on function public.limpar_anonimos() from public, anon, authenticated;

do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname in ('lembrar_salvar_conta', 'limpar_anonimos');
end $$;
select cron.schedule('lembrar_salvar_conta', '17 * * * *', 'select public.lembrar_salvar_conta()');
select cron.schedule('limpar_anonimos', '25 4 * * *', 'select public.limpar_anonimos()');
