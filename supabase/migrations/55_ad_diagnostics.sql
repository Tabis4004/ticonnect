-- =====================================================================
-- 55_ad_diagnostics.sql — La chaîne de récompense, lisible d'un coup
--
-- Vérifier qu'un boost a fonctionné demandait cinq requêtes et la
-- connaissance de subtilités qui ne se devinent pas : qu'une unité de
-- démonstration ne déclenche jamais de rappel, ou qu'un profil sous la
-- note plancher reste au classement organique même boosté. Les deux se
-- manifestent par « rien ne se passe ».
--
-- Redéfinie par la suite pour tenir compte de `load_error` : voir
-- 60_ad_impressions_load_error.sql.
-- =====================================================================
create or replace function public.ad_diagnostics(p_limit integer default 20)
returns table (
  quand timestamptz, emplacement text, mode text, etape text,
  ouvrier text, boost_restant text, note numeric,
  sponsorisable boolean, blocage text)
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_min_rating numeric := coalesce(
    (public.app_setting('sponsored_min_rating', '3.5'::jsonb))::text::numeric, 3.5);
begin
  if not public.is_admin() then
    raise exception 'Réservé aux administrateurs' using errcode = '42501';
  end if;

  return query
  select
    ai.created_at, ai.placement_key,
    case
      when ai.ad_unit_id is null then 'inconnu'
      when ai.ad_unit_id like 'ca-app-pub-3940256099942544/%' then 'TEST'
      else 'production' end,
    case
      when ai.load_error is not null then '0/4 · annonce non affichée'
      when not ai.ssv_verified       then '1/4 · affichée, non vérifiée'
      when ai.consumed_at is null    then '2/4 · vérifiée par Google'
      when wp.boosted_until is null
        or wp.boosted_until <= now() then '3/4 · consommée, boost expiré'
      else                                '4/4 · boost actif' end,
    coalesce(p.username, p.full_name),
    case when wp.boosted_until is null or wp.boosted_until <= now() then '—'
         else to_char(wp.boosted_until - now(), 'HH24"h"MI') end,
    wp.rating_avg,
    coalesce(wp.rating_avg >= v_min_rating, false),
    case
      when ai.load_error like 'Chargement : 3%'
        then 'Aucun annonceur disponible (no fill). Fréquent tant que '
             'l''application n''est pas publiée sur un store.'
      when ai.load_error is not null
        then 'Annonce non affichée — ' || ai.load_error
      when ai.ad_unit_id like 'ca-app-pub-3940256099942544/%'
        then 'Unité de démonstration : aucune vérification possible. Reconstruire avec ADS_TEST=false.'
      when not ai.ssv_verified
        then 'Annonce vue mais Google n''a pas rappelé. Vérifier l''URL de validation sur le bloc AdMob.'
      when ai.consumed_at is null and ai.placement_key = 'boost_profile_rewarded'
        then 'Vérifiée mais non échangée : grant_boost n''a pas été appelée.'
      when wp.profile_id is null
        then 'Pas de profil ouvrier : rien à mettre en avant.'
      when coalesce(wp.rating_avg, 0) < v_min_rating
        then format('Note %s < %s : reste au classement organique malgré le boost.',
                    coalesce(wp.rating_avg, 0), v_min_rating)
      else null end
  from public.ad_impressions ai
  left join public.profiles p         on p.id = ai.profile_id
  left join public.worker_profiles wp on wp.profile_id = ai.profile_id
  order by ai.created_at desc
  limit greatest(p_limit, 1);
end;
$$;

revoke execute on function public.ad_diagnostics(integer) from public, anon;
grant  execute on function public.ad_diagnostics(integer) to authenticated;
