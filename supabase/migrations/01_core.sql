-- =====================================================================
-- 01_core.sql — Extensions, types, identité, référentiel métiers, ouvriers
-- Projet : Ouvrier-Connect
-- =====================================================================

create extension if not exists postgis with schema extensions;
create extension if not exists pg_trgm with schema extensions;

-- =====================================================================
-- TYPES
-- =====================================================================
create type public.user_role            as enum ('client', 'worker', 'both');
create type public.verification_status  as enum ('unverified', 'pending', 'verified', 'rejected');
create type public.availability_status  as enum ('available', 'busy', 'unavailable');
create type public.urgency_level        as enum ('immediate', 'this_week', 'flexible');
create type public.pricing_unit         as enum ('hour', 'day', 'project');
create type public.job_status           as enum ('open', 'assigned', 'in_progress', 'completed', 'cancelled', 'expired');
create type public.application_status   as enum ('pending', 'accepted', 'rejected', 'withdrawn');
create type public.unlock_method        as enum ('credits', 'rewarded_ad', 'subscription', 'free_quota');
create type public.credit_txn_type      as enum ('purchase', 'ad_reward', 'spend_unlock', 'spend_boost', 'refund', 'bonus', 'admin_adjust');
create type public.payment_provider     as enum ('cinetpay', 'paydunya', 'flutterwave', 'other');
create type public.payment_status       as enum ('pending', 'success', 'failed', 'refunded');
create type public.payment_purpose      as enum ('credits', 'subscription', 'boost', 'verification');
create type public.subscription_plan    as enum ('free', 'pro', 'premium');
create type public.subscription_status  as enum ('active', 'expired', 'cancelled', 'pending');
create type public.report_status        as enum ('open', 'reviewed', 'actioned', 'dismissed');
create type public.ad_format            as enum ('rewarded', 'rewarded_interstitial', 'interstitial', 'banner', 'app_open', 'native');

-- =====================================================================
-- UTILITAIRES
-- =====================================================================
create or replace function public.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- =====================================================================
-- ADMINISTRATEURS (back-office)
-- =====================================================================
create table public.admins (
  profile_id uuid primary key,
  created_at timestamptz not null default now()
);

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.admins a where a.profile_id = auth.uid());
$$;

-- =====================================================================
-- PROFILS — données publiques, AUCUNE coordonnée de contact ici
-- =====================================================================
create table public.profiles (
  id                 uuid primary key references auth.users(id) on delete cascade,
  full_name          text not null check (char_length(full_name) between 2 and 120),
  role               public.user_role not null default 'client',
  avatar_url         text,
  bio                text check (char_length(bio) <= 1000),
  country_code       text not null default 'CI' check (char_length(country_code) = 2),
  city               text,
  neighborhood       text,
  preferred_language text not null default 'fr',
  is_suspended       boolean not null default false,
  last_seen_at       timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
comment on table public.profiles is
  'Profil public. Les coordonnées de contact sont volontairement isolées dans contact_details.';

alter table public.admins
  add constraint admins_profile_fk foreign key (profile_id) references public.profiles(id) on delete cascade;

create index profiles_city_idx on public.profiles (country_code, city);
create index profiles_role_idx on public.profiles (role) where not is_suspended;

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- =====================================================================
-- CONTACT_DETAILS — le cœur du modèle économique
-- Séparée des profils : l'accès est conditionné à un déverrouillage
-- (crédits, pub récompensée, ou abonnement).
-- =====================================================================
create table public.contact_details (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  phone      text not null,
  whatsapp   text,
  email      text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table public.contact_details is
  'Coordonnées privées. Lisibles par le propriétaire, ou après déverrouillage (voir contact_unlocks).';

create trigger contact_details_set_updated_at
  before update on public.contact_details
  for each row execute function public.set_updated_at();

-- =====================================================================
-- RÉFÉRENTIEL MÉTIERS
-- =====================================================================
create table public.trade_categories (
  id         smallint primary key generated always as identity,
  slug       text not null unique,
  name_fr    text not null,
  icon       text,
  sort_order smallint not null default 0
);

create table public.trades (
  id           smallint primary key generated always as identity,
  category_id  smallint not null references public.trade_categories(id) on delete restrict,
  slug         text not null unique,
  name_fr      text not null,
  search_terms text,
  is_active    boolean not null default true,
  sort_order   smallint not null default 0
);
comment on column public.trades.search_terms is
  'Synonymes et appellations locales, pour la recherche floue (ex. "maçon, mason, briqueteur").';

create index trades_category_idx on public.trades (category_id) where is_active;
create index trades_search_idx   on public.trades using gin (search_terms extensions.gin_trgm_ops);

-- =====================================================================
-- PROFIL OUVRIER
-- =====================================================================
create table public.worker_profiles (
  profile_id         uuid primary key references public.profiles(id) on delete cascade,
  headline           text check (char_length(headline) <= 160),
  years_experience   smallint check (years_experience between 0 and 70),
  rate_min           numeric(12,2) check (rate_min >= 0),
  rate_max           numeric(12,2) check (rate_max >= 0),
  currency           text not null default 'XOF' check (char_length(currency) = 3),
  pricing_unit       public.pricing_unit not null default 'day',
  availability       public.availability_status not null default 'available',
  verification       public.verification_status not null default 'unverified',
  id_document_url    text,
  id_document_type   text,
  verified_at        timestamptz,
  rating_avg         numeric(3,2) not null default 0 check (rating_avg between 0 and 5),
  rating_count       integer not null default 0,
  jobs_completed     integer not null default 0,
  response_rate      numeric(5,2) check (response_rate between 0 and 100),
  is_listed          boolean not null default true,
  boosted_until      timestamptz,
  free_unlocks_left  smallint not null default 3,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  constraint worker_rate_range check (rate_max is null or rate_min is null or rate_max >= rate_min)
);
comment on column public.worker_profiles.free_unlocks_left is
  'Quota offert à l''inscription : laisse l''ouvrier goûter au produit avant de payer.';
comment on column public.worker_profiles.boosted_until is
  'Mise en avant dans les résultats. Achetée en crédits ou gagnée via pub récompensée.';

create index worker_listed_idx  on public.worker_profiles (availability, rating_avg desc) where is_listed;
create index worker_boost_idx   on public.worker_profiles (boosted_until desc) where boosted_until is not null;

create trigger worker_profiles_set_updated_at
  before update on public.worker_profiles
  for each row execute function public.set_updated_at();

-- =====================================================================
-- MÉTIERS EXERCÉS PAR L'OUVRIER
-- =====================================================================
create table public.worker_trades (
  worker_id        uuid not null references public.worker_profiles(profile_id) on delete cascade,
  trade_id         smallint not null references public.trades(id) on delete restrict,
  years_experience smallint check (years_experience between 0 and 70),
  is_primary       boolean not null default false,
  primary key (worker_id, trade_id)
);

create index worker_trades_trade_idx on public.worker_trades (trade_id);
create unique index worker_trades_one_primary_idx
  on public.worker_trades (worker_id) where is_primary;

-- =====================================================================
-- ZONES D'INTERVENTION
-- Le champ géographique reste optionnel : beaucoup d'utilisateurs
-- travaillent au quartier, sans GPS. La géoloc est une couche premium.
-- =====================================================================
create table public.worker_service_areas (
  id           uuid primary key default gen_random_uuid(),
  worker_id    uuid not null references public.worker_profiles(profile_id) on delete cascade,
  country_code text not null default 'CI' check (char_length(country_code) = 2),
  city         text not null,
  neighborhood text,
  center       extensions.geography(Point, 4326),
  radius_km    numeric(6,2) check (radius_km > 0 and radius_km <= 500),
  created_at   timestamptz not null default now()
);

create index service_areas_worker_idx on public.worker_service_areas (worker_id);
create index service_areas_city_idx   on public.worker_service_areas (country_code, city);
create index service_areas_geo_idx    on public.worker_service_areas using gist (center);

-- =====================================================================
-- PORTFOLIO (photos de réalisations)
-- =====================================================================
create table public.worker_portfolio (
  id         uuid primary key default gen_random_uuid(),
  worker_id  uuid not null references public.worker_profiles(profile_id) on delete cascade,
  image_url  text not null,
  caption    text check (char_length(caption) <= 300),
  trade_id   smallint references public.trades(id) on delete set null,
  sort_order smallint not null default 0,
  created_at timestamptz not null default now()
);

create index portfolio_worker_idx on public.worker_portfolio (worker_id, sort_order);

-- =====================================================================
-- CRÉATION AUTOMATIQUE DU PROFIL À L'INSCRIPTION
-- =====================================================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, role, country_code)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'full_name', ''), 'Utilisateur'),
    coalesce((new.raw_user_meta_data ->> 'role')::public.user_role, 'client'),
    coalesce(nullif(new.raw_user_meta_data ->> 'country_code', ''), 'CI')
  );

  if new.phone is not null then
    insert into public.contact_details (profile_id, phone, email)
    values (new.id, new.phone, new.email);
  end if;

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
