-- =====================================================================
-- 15_premium_search.sql — Visibilité premium plafonnée
--
-- Le classement précédent remontait TOUS les profils boostés en tête,
-- sans limite. C'est le mécanisme qui, poussé à l'échelle, détruit la
-- recherche : dès que le nombre d'abonnés premium dépasse la hauteur d'un
-- écran, les premiers résultats deviennent intégralement payants, les
-- clients l'apprennent vite et cessent de faire confiance au classement.
-- On finance alors le produit en le vidant de sa valeur.
--
-- Deux garde-fous, tous deux réglables en base sans republier :
--
--   · `sponsored_slot_ratio`  — au plus un résultat sponsorisé toutes les
--     N positions (4 par défaut : positions 1, 5, 9…).
--   · `sponsored_min_rating`  — en dessous de cette note, un profil payant
--     retombe dans le classement organique. On peut acheter de la
--     visibilité, jamais l'exemption de la qualité.
--
-- Deux sources alimentent désormais la mise en avant :
--   · `boosted_until` — boost ponctuel gagné par publicité récompensée ;
--   · un abonnement `premium` actif — mise en avant continue.
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
      -- Un ratio inférieur à 2 signifierait « tout est sponsorisé » :
      -- le plafond se désactiverait lui-même.
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
    -- La note plancher s'applique ici : un profil boosté mais mal noté
    -- n'est pas exclu, il perd seulement son privilège de position.
    select b.*, (b.eligible_boost and b.rating_avg >= c.min_rating) as eligible
      from base b cross join cfg c
  ),
  ranked_eligible as (
    select s.*,
           row_number() over (
             partition by s.eligible
             order by (s.verification = 'verified') desc,
                      s.rating_avg desc,
                      s.jobs_completed desc,
                      s.profile_id
           ) as rn_eligible
      from scored s
  ),
  caps as (
    -- Le plafond ne tient que si le vivier organique peut le nourrir.
    -- Avec 20 abonnés premium et 3 profils gratuits, entrelacer un
    -- sponsorisé sur quatre est arithmétiquement impossible : les
    -- sponsorisés se retrouvent collés et la première page redevient
    -- intégralement payante — précisément ce que ce plafond existe pour
    -- empêcher. On limite donc leur NOMBRE à ce que les organiques
    -- permettent d'espacer ; les suivants retombent au mérite.
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
               -- Aucun profil organique : rien à protéger, le plafond
               -- n'aurait aucun sens.
               (select organic_count from caps) = 0
               or r.rn_eligible <= greatest(
                    floor((select organic_count from caps)::numeric
                          / ((select ratio from caps) - 1)),
                    -- Au moins une place dès qu'un profil organique
                    -- existe. Sans ce plancher, un marché naissant — un
                    -- abonné, deux profils gratuits — encaisserait un
                    -- abonnement premium sans jamais rien mettre en
                    -- avant. Le ratio y perd un peu de sa rigueur, sur un
                    -- volume où il ne veut de toute façon rien dire.
                    1
                  )
             )
           ) as sponsored
      from ranked_eligible r
  ),
  ranked as (
    -- Second classement : les sponsorisés déclassés rejoignent les
    -- organiques et sont réordonnés avec eux, au mérite.
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
    -- Les sponsorisés prennent les positions 1, 1+ratio, 1+2*ratio…
    -- Les organiques comblent les intervalles, dans l'ordre du mérite.
    -- Quand les sponsorisés manquent, des trous apparaissent dans la
    -- numérotation : sans importance, seul l'ordre relatif compte.
    select r.*,
           case when r.sponsored
                then (r.rn - 1) * c.ratio + 1
                else r.rn + ceil(r.rn::numeric / (c.ratio - 1))::int
           end as slot
      from ranked r cross join cfg c
  )
  -- Projection systématiquement qualifiée par `f.`.
  --
  -- Dans une fonction `language sql`, les colonnes déclarées par
  -- `returns table` se comportent comme des paramètres OUT et entrent dans
  -- la portée des noms. Une référence nue à `full_name` ou `rating_avg`
  -- devient alors ambiguë et la fonction refuse de se créer. Le préfixe
  -- lève l'ambiguïté : un paramètre OUT ne se qualifie pas par un alias
  -- de table.
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

grant execute on function public.search_workers(
  smallint, text, text, double precision, double precision,
  numeric, text, integer, integer) to authenticated;

comment on function public.search_workers(
  smallint, text, text, double precision, double precision,
  numeric, text, integer, integer) is
  'is_boosted indique que le profil occupe une position sponsorisée, pas '
  'seulement qu''il dispose d''un boost : c''est ce que l''interface doit '
  'signaler au client.';
