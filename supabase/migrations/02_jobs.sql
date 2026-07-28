-- =====================================================================
-- 02_jobs.sql — Demandes de service, candidatures, favoris
-- =====================================================================

-- =====================================================================
-- DEMANDES DE SERVICE
-- =====================================================================
create table public.job_requests (
  id                 uuid primary key default gen_random_uuid(),
  client_id          uuid not null references public.profiles(id) on delete cascade,
  trade_id           smallint not null references public.trades(id) on delete restrict,
  title              text not null check (char_length(title) between 5 and 140),
  description        text not null check (char_length(description) between 10 and 4000),
  photos             text[] not null default '{}',

  country_code       text not null default 'CI' check (char_length(country_code) = 2),
  city               text not null,
  neighborhood       text,
  location           extensions.geography(Point, 4326),

  budget_min         numeric(12,2) check (budget_min >= 0),
  budget_max         numeric(12,2) check (budget_max >= 0),
  currency           text not null default 'XOF' check (char_length(currency) = 3),
  pricing_unit       public.pricing_unit not null default 'day',

  urgency            public.urgency_level not null default 'flexible',
  status             public.job_status not null default 'open',
  starts_on          date,
  duration_days      smallint check (duration_days > 0),

  assigned_worker_id uuid references public.profiles(id) on delete set null,
  unlock_cost        smallint not null default 1 check (unlock_cost >= 0),

  views_count        integer not null default 0,
  applications_count integer not null default 0,

  expires_at         timestamptz not null default (now() + interval '30 days'),
  completed_at       timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),

  constraint job_budget_range check (budget_max is null or budget_min is null or budget_max >= budget_min),
  constraint job_assigned_requires_status check (
    assigned_worker_id is null or status in ('assigned', 'in_progress', 'completed')
  )
);
comment on column public.job_requests.unlock_cost is
  'Nombre de crédits que l''ouvrier dépense pour accéder au contact du client. 0 = gratuit.';

create index job_open_idx      on public.job_requests (country_code, city, trade_id, created_at desc)
  where status = 'open';
create index job_client_idx    on public.job_requests (client_id, created_at desc);
create index job_worker_idx    on public.job_requests (assigned_worker_id) where assigned_worker_id is not null;
create index job_geo_idx       on public.job_requests using gist (location);
create index job_expiry_idx    on public.job_requests (expires_at) where status = 'open';

create trigger job_requests_set_updated_at
  before update on public.job_requests
  for each row execute function public.set_updated_at();

-- =====================================================================
-- CANDIDATURES
-- =====================================================================
create table public.job_applications (
  id             uuid primary key default gen_random_uuid(),
  job_id         uuid not null references public.job_requests(id) on delete cascade,
  worker_id      uuid not null references public.worker_profiles(profile_id) on delete cascade,
  message        text check (char_length(message) <= 2000),
  proposed_price numeric(12,2) check (proposed_price >= 0),
  currency       text not null default 'XOF' check (char_length(currency) = 3),
  status         public.application_status not null default 'pending',
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (job_id, worker_id)
);

create index applications_job_idx    on public.job_applications (job_id, created_at desc);
create index applications_worker_idx on public.job_applications (worker_id, created_at desc);

create trigger job_applications_set_updated_at
  before update on public.job_applications
  for each row execute function public.set_updated_at();

-- Compteur dénormalisé de candidatures
create or replace function public.sync_applications_count()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    update public.job_requests
       set applications_count = applications_count + 1
     where id = new.job_id;
  elsif tg_op = 'DELETE' then
    update public.job_requests
       set applications_count = greatest(applications_count - 1, 0)
     where id = old.job_id;
  end if;
  return null;
end;
$$;

create trigger job_applications_count
  after insert or delete on public.job_applications
  for each row execute function public.sync_applications_count();

-- Accepter une candidature affecte l'ouvrier et rejette les autres
create or replace function public.handle_application_accepted()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'accepted' and old.status is distinct from 'accepted' then
    update public.job_requests
       set assigned_worker_id = new.worker_id,
           status = 'assigned'
     where id = new.job_id
       and status = 'open';

    update public.job_applications
       set status = 'rejected'
     where job_id = new.job_id
       and id <> new.id
       and status = 'pending';
  end if;
  return new;
end;
$$;

create trigger job_application_accepted
  after update on public.job_applications
  for each row execute function public.handle_application_accepted();

-- =====================================================================
-- FAVORIS (le client garde ses bons artisans)
-- Sert aussi à la rétention : c'est ce qui ramène le client dans l'app.
-- =====================================================================
create table public.favorites (
  client_id  uuid not null references public.profiles(id) on delete cascade,
  worker_id  uuid not null references public.worker_profiles(profile_id) on delete cascade,
  note       text check (char_length(note) <= 300),
  created_at timestamptz not null default now(),
  primary key (client_id, worker_id)
);

create index favorites_worker_idx on public.favorites (worker_id);
