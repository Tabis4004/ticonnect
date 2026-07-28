-- =====================================================================
-- 08_search.sql — Fonctions de recherche
-- Les profils boostés remontent en tête : c'est ce qui donne sa valeur
-- au boost, qu'il soit acheté en crédits ou gagné via pub récompensée.
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
  with origin as (
    select case
      when p_lat is not null and p_lon is not null
      then extensions.st_setsrid(extensions.st_makepoint(p_lon, p_lat), 4326)::extensions.geography
    end as pt
  )
  select
    p.id,
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
    (wp.boosted_until is not null and wp.boosted_until > now()) as is_boosted,
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
  order by
    (wp.boosted_until is not null and wp.boosted_until > now()) desc,
    (wp.verification = 'verified') desc,
    wp.rating_avg desc,
    wp.jobs_completed desc
  limit least(coalesce(p_limit, 20), 100)
  offset greatest(coalesce(p_offset, 0), 0);
$$;

grant execute on function public.search_workers(smallint, text, text, double precision, double precision, numeric, text, integer, integer) to authenticated;

-- =====================================================================
-- RECHERCHE DE MISSIONS (côté ouvrier)
-- Indique si le contact est déjà déverrouillé, pour que l'app sache
-- afficher le numéro ou le bouton "Regarder une vidéo pour débloquer".
-- =====================================================================
create or replace function public.search_jobs(
  p_trade_ids    smallint[] default null,
  p_country_code text default 'CI',
  p_city         text default null,
  p_urgency      public.urgency_level default null,
  p_limit        integer default 20,
  p_offset       integer default 0
)
returns table (
  id                 uuid,
  title              text,
  description        text,
  trade_id           smallint,
  trade_name         text,
  city               text,
  neighborhood       text,
  budget_min         numeric,
  budget_max         numeric,
  currency           text,
  pricing_unit       public.pricing_unit,
  urgency            public.urgency_level,
  unlock_cost        smallint,
  applications_count integer,
  client_name        text,
  is_unlocked        boolean,
  has_applied        boolean,
  created_at         timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    jr.id,
    jr.title,
    jr.description,
    jr.trade_id,
    t.name_fr,
    jr.city,
    jr.neighborhood,
    jr.budget_min,
    jr.budget_max,
    jr.currency,
    jr.pricing_unit,
    jr.urgency,
    jr.unlock_cost,
    jr.applications_count,
    p.full_name,
    public.has_unlocked(jr.client_id),
    exists (select 1 from public.job_applications ja
             where ja.job_id = jr.id and ja.worker_id = (select auth.uid())),
    jr.created_at
  from public.job_requests jr
  join public.trades t   on t.id = jr.trade_id
  join public.profiles p on p.id = jr.client_id
  where jr.status = 'open'
    and jr.expires_at > now()
    and jr.client_id <> (select auth.uid())
    and (p_trade_ids is null or jr.trade_id = any(p_trade_ids))
    and (p_country_code is null or jr.country_code = p_country_code)
    and (p_city is null or jr.city ilike p_city)
    and (p_urgency is null or jr.urgency = p_urgency)
    and not exists (
      select 1 from public.blocks b
       where (b.blocker_id = jr.client_id and b.blocked_id = (select auth.uid()))
          or (b.blocker_id = (select auth.uid()) and b.blocked_id = jr.client_id)
    )
  order by
    case jr.urgency when 'immediate' then 0 when 'this_week' then 1 else 2 end,
    jr.created_at desc
  limit least(coalesce(p_limit, 20), 100)
  offset greatest(coalesce(p_offset, 0), 0);
$$;

grant execute on function public.search_jobs(smallint[], text, text, public.urgency_level, integer, integer) to authenticated;
