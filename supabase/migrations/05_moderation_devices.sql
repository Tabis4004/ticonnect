-- =====================================================================
-- 05_moderation_devices.sql — Signalements, appareils, notifications
-- =====================================================================

-- =====================================================================
-- SIGNALEMENTS
-- Indispensable dès le jour 1 : on fait entrer un inconnu chez soi.
-- =====================================================================
create table public.reports (
  id                  uuid primary key default gen_random_uuid(),
  reporter_id         uuid not null references public.profiles(id) on delete cascade,
  reported_profile_id uuid references public.profiles(id) on delete cascade,
  job_id              uuid references public.job_requests(id) on delete set null,
  message_id          uuid references public.messages(id) on delete set null,
  reason              text not null,
  details             text check (char_length(details) <= 2000),
  status              public.report_status not null default 'open',
  resolved_by         uuid references public.profiles(id) on delete set null,
  resolved_at         timestamptz,
  admin_notes         text,
  created_at          timestamptz not null default now()
);

create index reports_status_idx   on public.reports (status, created_at desc);
create index reports_reported_idx on public.reports (reported_profile_id);

-- =====================================================================
-- BLOCAGES ENTRE UTILISATEURS
-- =====================================================================
create table public.blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint block_distinct_parties check (blocker_id <> blocked_id)
);

-- =====================================================================
-- APPAREILS (notifications push FCM)
-- =====================================================================
create table public.devices (
  id             uuid primary key default gen_random_uuid(),
  profile_id     uuid not null references public.profiles(id) on delete cascade,
  fcm_token      text not null unique,
  platform       text not null check (platform in ('android', 'ios', 'web')),
  app_version    text,
  device_model   text,
  last_active_at timestamptz not null default now(),
  created_at     timestamptz not null default now()
);

create index devices_profile_idx on public.devices (profile_id);

-- =====================================================================
-- NOTIFICATIONS (historique in-app)
-- =====================================================================
create table public.notifications (
  id          uuid primary key default gen_random_uuid(),
  profile_id  uuid not null references public.profiles(id) on delete cascade,
  kind        text not null,
  title       text not null,
  body        text,
  payload     jsonb not null default '{}'::jsonb,
  read_at     timestamptz,
  created_at  timestamptz not null default now()
);

create index notifications_profile_idx on public.notifications (profile_id, created_at desc);
create index notifications_unread_idx  on public.notifications (profile_id) where read_at is null;

-- =====================================================================
-- SUSPENSION AUTOMATIQUE À PARTIR DE 3 SIGNALEMENTS RETENUS
-- =====================================================================
create or replace function public.check_report_threshold()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if new.status = 'actioned' and old.status is distinct from 'actioned'
     and new.reported_profile_id is not null then

    select count(*) into v_count
      from public.reports
     where reported_profile_id = new.reported_profile_id
       and status = 'actioned';

    if v_count >= 3 then
      update public.profiles set is_suspended = true where id = new.reported_profile_id;
      update public.worker_profiles set is_listed = false where profile_id = new.reported_profile_id;
    end if;
  end if;
  return null;
end;
$$;

create trigger reports_check_threshold
  after update on public.reports
  for each row execute function public.check_report_threshold();

-- =====================================================================
-- EXPIRATION DES DEMANDES (à brancher sur pg_cron ou une Edge Function)
-- =====================================================================
create or replace function public.expire_stale_jobs()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rows integer;
begin
  update public.job_requests
     set status = 'expired'
   where status = 'open'
     and expires_at < now();
  get diagnostics v_rows = row_count;
  return v_rows;
end;
$$;

revoke execute on function public.expire_stale_jobs() from anon, authenticated;
