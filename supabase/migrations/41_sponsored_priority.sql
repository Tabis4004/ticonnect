-- =====================================================================
-- 19_sponsored_priority.sql — Les abonnés premium servis en premier
--
-- Trois sources alimentent désormais la mise en avant : l'abonnement
-- premium, le boost gagné par publicité récompensée, et le boost gagné par
-- parrainage. Elles se disputent le même stock de places sponsorisées, qui
-- est volontairement limité.
--
-- Sans arbitrage, les boosts gratuits évincent les abonnements payants et
-- l'on cannibalise ce que l'on vend : un ouvrier qui paie 5 000 FCFA par
-- mois se retrouverait derrière un autre qui a invité trois clients. Le
-- premium prend donc rang d'abord sur les places disponibles ; le
-- parrainage et la publicité occupent ce qui reste.
--
-- Ce n'est pas un privilège de position dans l'affichage — l'ordre entre
-- promus reste au mérite — mais un droit de priorité sur la rareté.
-- =====================================================================

create or replace function public.search_workers(
  p_trade_id     smallint default null,
  p_country_code text default 'CI',
  p_city         text default null,
  p_lat          double precision default null,
  p_lon          double precision default null,
  p_radius_km    numeric default 25,
  p_query        text default null,
  p_limit        integer default 20,
  p_offset       integer default 0
)
returns table (
  profile_id     uuid,
  full_name      text,
  avatar_url     text,
  headline       text,
  city           text,
  neighborhood   text,
  rating_avg     numeric,
  rating_count   integer,
  jobs_completed integer,
  verification   public.verification_status,
  availability   public.availability_status,
  rate_min       numeric,
  rate_max       numeric,
  currency       text,
  pricing_unit   public.pricing_unit,
  is_boosted     boolean,
  distance_km    double precision
)
language sql
stable
security invoker
set search_path = ''
as $$
  with cfg as (
    select
      greatest(
        coalesce((public.app_setting('sponsored_slot_ratio', '4'::jsonb))::text::int, 4),
        2
      ) as ratio,
      coalesce(
        (public.app_setting('sponsored_min_rating', '3.5'::jsonb))::text::numeric,
        3.5
      ) as min_rating
  ),
  origin as (
    select case
      when p_lat is not null and p_lon is not null
      then extensions.st_setsrid(extensions.st_makepoint(p_lon, p_lat), 4326)::extensions.geography
    end as pt
  ),
  base as (
    select
      p.id                as profile_id,
      p.full_name,
      p.avatar_url,
      wp.headline,
      p.city,
      p.neighborhood,
      wp.rating_avg,
      wp.rating_count,
      wp.jobs_completed,
      wp.verification,
      wp.availability,
      wp.rate_min,
      wp.rate_max,
      wp.currency,
      wp.pricing_unit,
      (public.active_plan(p.id) = 'premium') as is_premium,
      (
        (wp.boosted_until is not null and wp.boosted_until > now())
        or public.active_plan(p.id) = 'premium'
      )                   as eligible_boost,
      min(extensions.st_distance(sa.center, o.pt)) / 1000.0 as distance_km
    from public.worker_profiles wp
    join public.profiles p on p.id = wp.profile_id
    cross join origin o
    left join public.worker_service_areas sa
           on sa.worker_id = wp.profile_id
    where wp.is_listed
      and not p.is_suspended
      and (p_trade_id is null or exists (
            select 1 from public.worker_trades wt
             where wt.worker_id = wp.profile_id and wt.trade_id = p_trade_id))
      and (p_country_code is null or p.country_code = p_country_code)
      and (p_city is null or p.city ilike p_city or sa.city ilike p_city)
      and (p_query is null or p.full_name ilike '%' || p_query || '%'
                           or wp.headline ilike '%' || p_query || '%')
      and (
        o.pt is null
        or sa.center is null
        or extensions.st_dwithin(sa.center, o.pt, (p_radius_km * 1000)::double precision)
      )
    group by p.id, p.full_name, p.avatar_url, wp.headline, p.city, p.neighborhood,
             wp.rating_avg, wp.rating_count, wp.jobs_completed, wp.verification,
             wp.availability, wp.rate_min, wp.rate_max, wp.currency, wp.pricing_unit,
             wp.boosted_until
  ),
  scored as (
    -- La note plancher s'applique ici : un profil boosté mais mal noté n'est
    -- pas exclu, il perd seulement son privilège de position. La visibilité
    -- s'achète, jamais l'exemption de la qualité.
    select b.*, (b.eligible_boost and b.rating_avg >= c.min_rating) as eligible
      from base b cross join cfg c
  ),
  ranked_eligible as (
    -- C'est ici que se joue la priorité : `is_premium desc` en tête du tri
    -- donne aux abonnés les premiers rangs, donc les places qui survivront
    -- au plafond calculé plus bas.
    select s.*,
           row_number() over (
             partition by s.eligible
             order by s.is_premium desc,
                      (s.verification = 'verified') desc,
                      s.rating_avg desc,
                      s.jobs_completed desc,
                      s.profile_id
           ) as rn_eligible
      from scored s
  ),
  caps as (
    -- Le plafond ne tient que si le vivier organique peut le nourrir. Avec
    -- vingt profils mis en avant et trois profils ordinaires, entrelacer un
    -- sponsorisé sur quatre est arithmétiquement impossible : ils se
    -- retrouvent collés et la première page redevient intégralement payante,
    -- précisément ce que ce plafond existe pour empêcher. On limite donc
    -- leur NOMBRE à ce que les organiques permettent d'espacer.
    select
      count(*) filter (where not eligible) as organic_count,
      (select ratio from cfg)              as ratio
      from ranked_eligible
  ),
  promoted as (
    select r.*,
           (
             r.eligible
             and (
               (select organic_count from caps) = 0
               or r.rn_eligible <= greatest(
                    floor((select organic_count from caps)::numeric
                          / ((select ratio from caps) - 1)),
                    -- Au moins une place dès qu'un profil organique existe.
                    -- Sans ce plancher, un marché naissant — un abonné, deux
                    -- profils gratuits — encaisserait un abonnement premium
                    -- sans jamais rien mettre en avant.
                    1
                  )
             )
           ) as sponsored
      from ranked_eligible r
  ),
  ranked as (
    -- Second classement : les éligibles déclassés rejoignent les organiques
    -- et sont réordonnés avec eux, au mérite seul. Entre promus, le premium
    -- ne rachète pas non plus la position — il n'a acheté que le droit
    -- d'entrer.
    select p.*,
           row_number() over (
             partition by p.sponsored
             order by (p.verification = 'verified') desc,
                      p.rating_avg desc,
                      p.jobs_completed desc,
                      p.profile_id
           ) as rn
      from promoted p
  ),
  positioned as (
    -- Les sponsorisés prennent les positions 1, 1+ratio, 1+2*ratio… Les
    -- organiques comblent les intervalles. Quand les sponsorisés manquent,
    -- des trous apparaissent dans la numérotation : sans importance, seul
    -- l'ordre relatif compte.
    select r.*,
           case when r.sponsored
                then (r.rn - 1) * c.ratio + 1
                else r.rn + ceil(r.rn::numeric / (c.ratio - 1))::int
           end as slot
      from ranked r cross join cfg c
  )
  -- Projection systématiquement qualifiée par `f.` : dans une fonction
  -- `language sql`, les colonnes déclarées par `returns table` se comportent
  -- comme des paramètres OUT et entrent dans la portée des noms. Une
  -- référence nue à `full_name` deviendrait ambiguë et la fonction refuserait
  -- de se créer.
  select
    f.profile_id,
    f.full_name,
    f.avatar_url,
    f.headline,
    f.city,
    f.neighborhood,
    f.rating_avg,
    f.rating_count,
    f.jobs_completed,
    f.verification,
    f.availability,
    f.rate_min,
    f.rate_max,
    f.currency,
    f.pricing_unit,
    f.sponsored as is_boosted,
    f.distance_km
  from positioned f
  order by f.slot, f.rating_avg desc, f.jobs_completed desc, f.profile_id
  limit least(coalesce(p_limit, 20), 100)
  offset greatest(coalesce(p_offset, 0), 0);
$$;

-- `create or replace` conserve les droits existants, mais on réaffirme
-- l'intention de la migration 09 : ni `public` ni `anon` ne doivent pouvoir
-- interroger l'annuaire. Un fichier qui recrée une fonction sans rejouer
-- ses révocations est la façon la plus discrète de rouvrir un accès.
revoke execute on function public.search_workers(
  smallint, text, text, double precision, double precision,
  numeric, text, integer, integer) from public, anon;

grant execute on function public.search_workers(
  smallint, text, text, double precision, double precision,
  numeric, text, integer, integer) to authenticated;

comment on function public.search_workers(
  smallint, text, text, double precision, double precision,
  numeric, text, integer, integer) is
  'is_boosted indique que le profil occupe une position sponsorisée, pas '
  'seulement qu''il dispose d''un boost. Les places sont plafonnées et les '
  'abonnés premium y ont priorité sur les boosts gagnés (publicité, '
  'parrainage).';
