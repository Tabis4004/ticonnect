-- =====================================================================
-- 46_ad_funnel_metrics.sql — Décomposition de l'entonnoir publicitaire
--
-- `ad_ssv_health()` divisait les impressions vérifiées par TOUTES les
-- tentatives, et attribuait l'écart à l'Edge Function `admob-ssv`. Le
-- diagnostic était faux.
--
-- Relevé réel sur 21 tentatives récompensées :
--   · 9 n'ont jamais chargé — 8 « No fill », 1 « Publisher data not found »
--   · 10 ont chargé sans que la vidéo soit menée à son terme
--   · 2 ont été récompensées, et vérifiées toutes les deux
--
-- Les journaux de la fonction confirment : deux callbacks reçues, deux
-- réponses 200. `admob-ssv` traitait 100 % de ce qui lui arrivait. C'est le
-- remplissage (57 %) et la complétion (17 %) qui sont bas — deux problèmes
-- qui ne relèvent pas du code.
--
-- Une alerte qui accuse le mauvais composant est pire qu'une absence
-- d'alerte : elle envoie chercher la panne là où il n'y en a pas.
--
-- Trois taux, trois responsables :
--   remplissage  = affichées / tentatives      → inventaire AdMob, maturité du compte
--   complétion   = récompensées / affichées    → produit et placement
--   vérification = vérifiées / récompensées    → le code, et lui seul
-- =====================================================================

alter table public.ad_impressions
  add column if not exists earned_at timestamptz;

comment on column public.ad_impressions.earned_at is
  'Instant où AdMob a déclaré la récompense gagnée, côté application. '
  'Sans lui, une vidéo abandonnée à mi-parcours et une callback perdue '
  'produisent exactement la même ligne : chargée, non vérifiée.';

create index if not exists ad_impressions_funnel_idx
  on public.ad_impressions (created_at desc, format)
  where format in ('rewarded', 'rewarded_interstitial');

-- Rattrapage : une impression vérifiée a forcément été récompensée.
update public.ad_impressions
   set earned_at = coalesce(earned_at, created_at)
 where ssv_verified and earned_at is null;

-- Le type de retour change : il faut supprimer avant de recréer.
drop function if exists public.ad_ssv_health();

create or replace function public.ad_ssv_health()
returns table (
  attempts          bigint,
  no_fill           bigint,
  displayed         bigint,
  earned            bigint,
  verified          bigint,
  fill_ratio        numeric,
  completion_ratio  numeric,
  verified_ratio    numeric
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
  with f as (
    select
      count(*)                                          as n_attempts,
      count(*) filter (where ai.load_error is not null)  as n_no_fill,
      count(*) filter (where ai.load_error is null)      as n_displayed,
      count(*) filter (where ai.earned_at is not null)   as n_earned,
      count(*) filter (where ai.ssv_verified)            as n_verified
    from public.ad_impressions ai
    where ai.created_at >= now() - interval '24 hours'
      and ai.format in ('rewarded', 'rewarded_interstitial')
  )
  select
    f.n_attempts, f.n_no_fill, f.n_displayed, f.n_earned, f.n_verified,
    case when f.n_attempts  = 0 then null
         else round(f.n_displayed::numeric / f.n_attempts::numeric, 3) end,
    case when f.n_displayed = 0 then null
         else round(f.n_earned::numeric    / f.n_displayed::numeric, 3) end,
    -- Le dénominateur est le nombre de récompenses réellement gagnées :
    -- c'est le seul cas où AdMob s'engage à envoyer une callback.
    case when f.n_earned    = 0 then null
         else round(f.n_verified::numeric  / f.n_earned::numeric, 3) end
  from f;
end;
$$;

grant execute on function public.ad_ssv_health() to authenticated;
