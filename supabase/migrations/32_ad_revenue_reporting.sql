-- =====================================================================
-- 32_ad_revenue_reporting.sql — Mesure du revenu publicitaire
--
-- Toutes les projections faites jusqu'ici reposent sur un eCPM estimé,
-- faute de donnée publique pour l'Afrique de l'Ouest. Ce chiffre décide
-- pourtant à lui seul de la viabilité du modèle : entre 0,15 $ et 1,00 $,
-- l'audience nécessaire pour atteindre le même revenu varie d'un facteur
-- vingt.
--
-- Il sera connu dès la première semaine de diffusion réelle. Encore
-- faut-il pouvoir le lire — d'où cette fonction, qui agrège
-- `ad_impressions` par jour et par emplacement.
--
-- Note sur `estimated_revenue` : la colonne n'est alimentée que si l'on
-- branche l'API de reporting AdMob. Sans elle, le nombre d'impressions
-- reste exploitable et se croise avec le revenu affiché dans la console
-- AdMob pour reconstituer l'eCPM par emplacement.
-- =====================================================================

create or replace function public.ad_revenue_summary(p_days integer default 14)
returns table (
  day               date,
  placement_key     text,
  format            public.ad_format,
  impressions       bigint,
  verified          bigint,
  consumed          bigint,
  reward_credits    bigint,
  estimated_revenue numeric
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Réservé aux administrateurs' using errcode = '42501';
  end if;

  return query
  select
    (ai.created_at at time zone 'UTC')::date        as day,
    coalesce(ai.placement_key, '(supprimé)')        as placement_key,
    ai.format,
    count(*)                                        as impressions,
    -- Un écart durable entre impressions et impressions vérifiées signale
    -- que la vérification serveur ne fonctionne pas : c'est l'indicateur
    -- de santé de l'Edge Function admob-ssv.
    count(*) filter (where ai.ssv_verified)         as verified,
    count(*) filter (where ai.consumed_at is not null) as consumed,
    coalesce(sum(ai.reward_credits), 0)::bigint     as reward_credits,
    coalesce(sum(ai.estimated_revenue), 0)          as estimated_revenue
  from public.ad_impressions ai
  where ai.created_at >= now() - make_interval(days => greatest(p_days, 1))
  group by 1, 2, 3
  order by 1 desc, 4 desc;
end;
$$;

revoke execute on function public.ad_revenue_summary(integer) from public, anon;
grant  execute on function public.ad_revenue_summary(integer) to authenticated;

comment on function public.ad_revenue_summary(integer) is
  'Revenu et volume publicitaires par jour et par emplacement. '
  'Réservée aux administrateurs.';

-- =====================================================================
-- SANTÉ DE LA VÉRIFICATION SERVEUR
--
-- Une seule question, mais celle qui décide si les récompenses
-- fonctionnent : quelle proportion des visionnages récompensés a été
-- confirmée par Google ces dernières 24 heures ?
--
-- Proche de zéro = admob-ssv n'est pas déployée, mal configurée dans la
-- console AdMob, ou sa signature est refusée. Les ouvriers regardent
-- alors des vidéos sans jamais obtenir leur mise en avant, ce qui est la
-- pire des situations : on encaisse la gêne sans livrer la contrepartie.
-- =====================================================================
create or replace function public.ad_ssv_health()
returns table (
  rewarded_impressions bigint,
  verified             bigint,
  verified_ratio       numeric
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Réservé aux administrateurs' using errcode = '42501';
  end if;

  return query
  select
    count(*)                                  as rewarded_impressions,
    count(*) filter (where ai.ssv_verified)   as verified,
    case when count(*) = 0 then null
         else round(count(*) filter (where ai.ssv_verified)::numeric
                    / count(*)::numeric, 3)
    end                                       as verified_ratio
  from public.ad_impressions ai
  where ai.created_at >= now() - interval '24 hours'
    and ai.format in ('rewarded', 'rewarded_interstitial');
end;
$$;

revoke execute on function public.ad_ssv_health() from public, anon;
grant  execute on function public.ad_ssv_health() to authenticated;

comment on function public.ad_ssv_health() is
  'Taux de vérification serveur des publicités récompensées sur 24 h. '
  'Un taux effondré signale une Edge Function admob-ssv en panne.';
