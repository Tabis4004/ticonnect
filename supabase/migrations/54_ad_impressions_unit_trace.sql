-- =====================================================================
-- 54_ad_impressions_unit_trace.sql — Trace de l'unité sollicitée
--
-- Sans elle, impossible de distinguer « l'application tournait sur les
-- unités de démonstration » de « la vérification serveur est en panne » :
-- les deux se manifestent par un ssv_verified qui reste faux. Le
-- diagnostic a coûté plusieurs allers-retours faute de cette colonne.
-- =====================================================================
alter table public.ad_impressions
  add column if not exists ad_unit_id text;

comment on column public.ad_impressions.ad_unit_id is
  'Unité publicitaire demandée. Un préfixe ca-app-pub-3940256099942544 '
  'signale les unités de démonstration Google : aucune vérification '
  'serveur ne peut aboutir dans ce cas, c''est attendu.';

create or replace function public.ad_mode_check(p_hours integer default 24)
returns table (mode text, impressions bigint, verifiees bigint, derniere timestamptz)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Réservé aux administrateurs' using errcode = '42501';
  end if;
  return query
  select
    case
      when ai.ad_unit_id is null then 'inconnu (build antérieur à la trace)'
      when ai.ad_unit_id like 'ca-app-pub-3940256099942544/%' then 'TEST — unités de démonstration'
      else 'production — tes unités'
    end,
    count(*), count(*) filter (where ai.ssv_verified), max(ai.created_at)
  from public.ad_impressions ai
  where ai.created_at >= now() - make_interval(hours => greatest(p_hours, 1))
  group by 1 order by 4 desc;
end;
$$;

revoke execute on function public.ad_mode_check(integer) from public, anon;
grant  execute on function public.ad_mode_check(integer) to authenticated;
