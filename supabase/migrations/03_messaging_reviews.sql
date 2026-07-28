-- =====================================================================
-- 03_messaging_reviews.sql — Messagerie et système d'avis
-- =====================================================================

-- =====================================================================
-- CONVERSATIONS
-- =====================================================================
create table public.conversations (
  id              uuid primary key default gen_random_uuid(),
  job_id          uuid references public.job_requests(id) on delete set null,
  client_id       uuid not null references public.profiles(id) on delete cascade,
  worker_id       uuid not null references public.profiles(id) on delete cascade,
  last_message_at timestamptz,
  client_unread   smallint not null default 0,
  worker_unread   smallint not null default 0,
  is_archived     boolean not null default false,
  created_at      timestamptz not null default now(),
  constraint conversation_distinct_parties check (client_id <> worker_id)
);

-- Une seule conversation par trio (client, ouvrier, mission).
-- coalesce sur un UUID nul pour gérer les conversations hors mission.
create unique index conversations_unique_idx
  on public.conversations (client_id, worker_id, coalesce(job_id, '00000000-0000-0000-0000-000000000000'::uuid));
create index conversations_client_idx on public.conversations (client_id, last_message_at desc);
create index conversations_worker_idx on public.conversations (worker_id, last_message_at desc);

-- =====================================================================
-- MESSAGES
-- =====================================================================
create table public.messages (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id       uuid not null references public.profiles(id) on delete cascade,
  body            text check (char_length(body) <= 4000),
  attachment_url  text,
  -- Anti-désintermédiation : détecte les numéros échangés en clair.
  -- Sert à mesurer la fuite hors plateforme, pas à censurer.
  contains_contact boolean not null default false,
  read_at         timestamptz,
  created_at      timestamptz not null default now(),
  constraint message_has_content check (body is not null or attachment_url is not null)
);

create index messages_conversation_idx on public.messages (conversation_id, created_at desc);
create index messages_leak_idx on public.messages (created_at desc) where contains_contact;

-- Détection de numéros de téléphone / identifiants de messagerie
create or replace function public.flag_contact_in_message()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.body is not null and (
       -- 7 chiffres ou plus, avec séparateurs éventuels
       new.body ~ '(\+?\d[\d\s\.\-]{6,}\d)'
       or new.body ~* '(whatsapp|whats app|wattsap|telegram|appelle[- ]moi|mon num)'
     ) then
    new.contains_contact := true;
  end if;
  return new;
end;
$$;

create trigger messages_flag_contact
  before insert on public.messages
  for each row execute function public.flag_contact_in_message();

-- Mise à jour de la conversation + compteurs de non-lus
create or replace function public.sync_conversation_on_message()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_client uuid;
begin
  select c.client_id into v_client
    from public.conversations c
   where c.id = new.conversation_id;

  update public.conversations
     set last_message_at = new.created_at,
         is_archived = false,
         client_unread = case when new.sender_id = v_client then client_unread else client_unread + 1 end,
         worker_unread = case when new.sender_id = v_client then worker_unread + 1 else worker_unread end
   where id = new.conversation_id;

  return null;
end;
$$;

create trigger messages_sync_conversation
  after insert on public.messages
  for each row execute function public.sync_conversation_on_message();

-- =====================================================================
-- AVIS
-- La note est ce qui donne de la valeur à l'app pour l'ouvrier :
-- sa réputation vit ici, pas dans son carnet d'adresses.
-- =====================================================================
create table public.reviews (
  id                 uuid primary key default gen_random_uuid(),
  job_id             uuid not null references public.job_requests(id) on delete cascade,
  reviewer_id        uuid not null references public.profiles(id) on delete cascade,
  reviewee_id        uuid not null references public.profiles(id) on delete cascade,
  rating             smallint not null check (rating between 1 and 5),
  quality_rating     smallint check (quality_rating between 1 and 5),
  punctuality_rating smallint check (punctuality_rating between 1 and 5),
  price_rating       smallint check (price_rating between 1 and 5),
  comment            text check (char_length(comment) <= 1500),
  is_hidden          boolean not null default false,
  created_at         timestamptz not null default now(),
  unique (job_id, reviewer_id),
  constraint review_distinct_parties check (reviewer_id <> reviewee_id)
);

create index reviews_reviewee_idx on public.reviews (reviewee_id, created_at desc) where not is_hidden;

-- Agrégation de la note sur le profil ouvrier
create or replace function public.sync_worker_rating()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_target uuid := coalesce(new.reviewee_id, old.reviewee_id);
begin
  update public.worker_profiles wp
     set rating_avg = coalesce(agg.avg_rating, 0),
         rating_count = coalesce(agg.cnt, 0)
    from (
      select round(avg(r.rating)::numeric, 2) as avg_rating, count(*) as cnt
        from public.reviews r
       where r.reviewee_id = v_target
         and not r.is_hidden
    ) agg
   where wp.profile_id = v_target;

  return null;
end;
$$;

create trigger reviews_sync_rating
  after insert or update or delete on public.reviews
  for each row execute function public.sync_worker_rating();

-- Incrémente le compteur de missions terminées
create or replace function public.sync_jobs_completed()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'completed' and old.status is distinct from 'completed'
     and new.assigned_worker_id is not null then
    update public.worker_profiles
       set jobs_completed = jobs_completed + 1
     where profile_id = new.assigned_worker_id;

    new.completed_at := coalesce(new.completed_at, now());
  end if;
  return new;
end;
$$;

create trigger job_requests_completed
  before update on public.job_requests
  for each row execute function public.sync_jobs_completed();
