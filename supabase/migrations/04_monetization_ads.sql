-- =====================================================================
-- 04_monetization_ads.sql — Crédits, déverrouillages, publicité, paiements
--
-- Principe : le demandeur est 100 % gratuit. L'ouvrier accède aux
-- coordonnées en dépensant un crédit, obtenu de trois façons :
--   1. quota offert à l'inscription
--   2. visionnage volontaire d'une pub récompensée  (revenu AdMob)
--   3. achat en mobile money, ou abonnement illimité (revenu direct)
-- =====================================================================

-- =====================================================================
-- PORTEFEUILLE DE CRÉDITS
-- =====================================================================
create table public.credit_wallets (
  profile_id      uuid primary key references public.profiles(id) on delete cascade,
  balance         integer not null default 0 check (balance >= 0),
  lifetime_earned integer not null default 0,
  lifetime_spent  integer not null default 0,
  updated_at      timestamptz not null default now()
);

create trigger credit_wallets_set_updated_at
  before update on public.credit_wallets
  for each row execute function public.set_updated_at();

-- =====================================================================
-- GRAND LIVRE DES CRÉDITS (immuable — jamais de UPDATE/DELETE)
-- =====================================================================
create table public.credit_transactions (
  id             uuid primary key default gen_random_uuid(),
  profile_id     uuid not null references public.profiles(id) on delete cascade,
  type           public.credit_txn_type not null,
  amount         integer not null check (amount <> 0),
  balance_after  integer not null check (balance_after >= 0),
  reference_type text,
  reference_id   uuid,
  description    text,
  created_at     timestamptz not null default now()
);
comment on column public.credit_transactions.amount is
  'Signé : positif = crédit gagné/acheté, négatif = crédit dépensé.';

create index credit_txn_profile_idx on public.credit_transactions (profile_id, created_at desc);

-- =====================================================================
-- CONFIGURATION DES EMPLACEMENTS PUBLICITAIRES
-- Table de config pilotée à distance : tu ajustes la fréquence des pubs
-- sans republier l'app sur le Play Store.
-- =====================================================================
create table public.ad_placements (
  key                  text primary key,
  format               public.ad_format not null,
  ad_unit_android      text,
  ad_unit_ios          text,
  is_enabled           boolean not null default true,
  reward_credits       smallint not null default 0 check (reward_credits >= 0),
  daily_cap_per_user   smallint check (daily_cap_per_user > 0),
  min_seconds_between  integer not null default 60 check (min_seconds_between >= 0),
  description          text,
  updated_at           timestamptz not null default now()
);
comment on table public.ad_placements is
  'Règles AdMob : les formats rewarded exigent un opt-in explicite, ad par ad. '
  'Les interstitiels ne doivent jamais s''afficher au lancement ni pendant une action.';

create trigger ad_placements_set_updated_at
  before update on public.ad_placements
  for each row execute function public.set_updated_at();

-- =====================================================================
-- IMPRESSIONS / RÉCOMPENSES PUBLICITAIRES
-- ssv_transaction_id vient de la Server-Side Verification AdMob :
-- c'est la seule preuve fiable qu'une pub a bien été vue jusqu'au bout.
-- Sans elle, un client modifié peut réclamer des crédits à l'infini.
-- =====================================================================
create table public.ad_impressions (
  id                 uuid primary key default gen_random_uuid(),
  profile_id         uuid not null references public.profiles(id) on delete cascade,
  placement_key      text references public.ad_placements(key) on delete set null,
  format             public.ad_format not null,
  reward_credits     smallint not null default 0,
  ssv_verified       boolean not null default false,
  ssv_transaction_id text unique,
  ad_network         text,
  estimated_revenue  numeric(12,6),
  currency           text default 'USD',
  country_code       text,
  created_at         timestamptz not null default now()
);
comment on column public.ad_impressions.ssv_transaction_id is
  'Identifiant unique fourni par AdMob SSV. La contrainte UNIQUE bloque le rejeu.';

create index ad_impressions_profile_idx on public.ad_impressions (profile_id, created_at desc);
create index ad_impressions_revenue_idx on public.ad_impressions (created_at desc, country_code);

-- =====================================================================
-- DÉVERROUILLAGES DE CONTACT
-- =====================================================================
create table public.contact_unlocks (
  id                uuid primary key default gen_random_uuid(),
  unlocker_id       uuid not null references public.profiles(id) on delete cascade,
  target_profile_id uuid not null references public.profiles(id) on delete cascade,
  job_id            uuid references public.job_requests(id) on delete set null,
  method            public.unlock_method not null,
  credits_spent     smallint not null default 0 check (credits_spent >= 0),
  ad_impression_id  uuid references public.ad_impressions(id) on delete set null,
  created_at        timestamptz not null default now(),
  constraint unlock_distinct_parties check (unlocker_id <> target_profile_id)
);

-- Un déverrouillage par paire : on ne fait pas payer deux fois le même contact.
create unique index contact_unlocks_pair_idx
  on public.contact_unlocks (unlocker_id, target_profile_id);
create index contact_unlocks_target_idx on public.contact_unlocks (target_profile_id);

-- =====================================================================
-- ABONNEMENTS
-- =====================================================================
create table public.subscriptions (
  id          uuid primary key default gen_random_uuid(),
  profile_id  uuid not null references public.profiles(id) on delete cascade,
  plan        public.subscription_plan not null default 'free',
  status      public.subscription_status not null default 'pending',
  started_at  timestamptz,
  expires_at  timestamptz,
  auto_renew  boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create unique index subscriptions_active_idx
  on public.subscriptions (profile_id) where status = 'active';
create index subscriptions_expiry_idx
  on public.subscriptions (expires_at) where status = 'active';

create trigger subscriptions_set_updated_at
  before update on public.subscriptions
  for each row execute function public.set_updated_at();

-- =====================================================================
-- PAIEMENTS MOBILE MONEY
-- =====================================================================
create table public.payments (
  id              uuid primary key default gen_random_uuid(),
  profile_id      uuid not null references public.profiles(id) on delete cascade,
  provider        public.payment_provider not null,
  provider_ref    text not null,
  amount          numeric(12,2) not null check (amount > 0),
  currency        text not null default 'XOF' check (char_length(currency) = 3),
  purpose         public.payment_purpose not null,
  status          public.payment_status not null default 'pending',
  credits_granted integer not null default 0,
  subscription_id uuid references public.subscriptions(id) on delete set null,
  metadata        jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (provider, provider_ref)
);

create index payments_profile_idx on public.payments (profile_id, created_at desc);
create index payments_status_idx  on public.payments (status, created_at desc);

create trigger payments_set_updated_at
  before update on public.payments
  for each row execute function public.set_updated_at();

-- =====================================================================
-- PORTEFEUILLE CRÉÉ AVEC LE PROFIL
-- =====================================================================
create or replace function public.create_wallet_for_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.credit_wallets (profile_id, balance)
  values (new.id, 0)
  on conflict (profile_id) do nothing;
  return null;
end;
$$;

create trigger profiles_create_wallet
  after insert on public.profiles
  for each row execute function public.create_wallet_for_profile();

-- =====================================================================
-- MOUVEMENT DE CRÉDITS — atomique, avec verrou de ligne
-- =====================================================================
create or replace function public.adjust_credits(
  p_profile_id     uuid,
  p_amount         integer,
  p_type           public.credit_txn_type,
  p_reference_type text default null,
  p_reference_id   uuid default null,
  p_description    text default null
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_balance integer;
begin
  if p_amount = 0 then
    raise exception 'Le montant doit être différent de zéro';
  end if;

  insert into public.credit_wallets (profile_id, balance)
  values (p_profile_id, 0)
  on conflict (profile_id) do nothing;

  select balance into v_balance
    from public.credit_wallets
   where profile_id = p_profile_id
   for update;

  v_balance := v_balance + p_amount;

  if v_balance < 0 then
    raise exception 'Crédits insuffisants' using errcode = 'P0001';
  end if;

  update public.credit_wallets
     set balance = v_balance,
         lifetime_earned = lifetime_earned + greatest(p_amount, 0),
         lifetime_spent  = lifetime_spent  + greatest(-p_amount, 0)
   where profile_id = p_profile_id;

  insert into public.credit_transactions
    (profile_id, type, amount, balance_after, reference_type, reference_id, description)
  values
    (p_profile_id, p_type, p_amount, v_balance, p_reference_type, p_reference_id, p_description);

  return v_balance;
end;
$$;

revoke execute on function public.adjust_credits(uuid, integer, public.credit_txn_type, text, uuid, text) from anon, authenticated;

-- =====================================================================
-- DÉVERROUILLER UN CONTACT — le geste central du produit
-- Appelée depuis l'app : rpc('unlock_contact', {...})
-- =====================================================================
create or replace function public.unlock_contact(
  p_target_profile_id uuid,
  p_job_id            uuid default null,
  p_ad_impression_id  uuid default null
)
returns public.contact_unlocks
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me       uuid := auth.uid();
  v_cost     smallint := 1;
  v_method   public.unlock_method;
  v_existing public.contact_unlocks;
  v_result   public.contact_unlocks;
  v_free     smallint;
  v_has_sub  boolean;
begin
  if v_me is null then
    raise exception 'Authentification requise';
  end if;
  if v_me = p_target_profile_id then
    raise exception 'Déverrouillage inutile sur son propre profil';
  end if;

  -- Déjà déverrouillé : on renvoie l'existant sans refacturer
  select * into v_existing
    from public.contact_unlocks
   where unlocker_id = v_me and target_profile_id = p_target_profile_id;
  if found then
    return v_existing;
  end if;

  -- RÈGLE CENTRALE : le demandeur ne paie jamais.
  -- p_job_id renseigné  => un ouvrier accède au contact d'un client : payant.
  -- p_job_id absent     => un client accède au contact d'un ouvrier : gratuit.
  if p_job_id is null then
    insert into public.contact_unlocks
      (unlocker_id, target_profile_id, job_id, method, credits_spent)
    values (v_me, p_target_profile_id, null, 'free_quota', 0)
    returning * into v_result;
    return v_result;
  end if;

  select unlock_cost into v_cost from public.job_requests where id = p_job_id;
  v_cost := coalesce(v_cost, 1);

  select exists (
    select 1 from public.subscriptions s
     where s.profile_id = v_me
       and s.status = 'active'
       and s.plan <> 'free'
       and (s.expires_at is null or s.expires_at > now())
  ) into v_has_sub;

  if v_has_sub then
    v_method := 'subscription';
    v_cost := 0;

  elsif p_ad_impression_id is not null then
    -- Récompense publicitaire : uniquement si AdMob a confirmé la vue (SSV)
    -- et si cette impression n'a pas déjà servi.
    perform 1
       from public.ad_impressions ai
      where ai.id = p_ad_impression_id
        and ai.profile_id = v_me
        and ai.ssv_verified
        and not exists (
          select 1 from public.contact_unlocks cu where cu.ad_impression_id = ai.id
        );
    if not found then
      raise exception 'Récompense publicitaire invalide ou déjà utilisée';
    end if;
    v_method := 'rewarded_ad';
    v_cost := 0;

  else
    select free_unlocks_left into v_free
      from public.worker_profiles
     where profile_id = v_me
     for update;

    if coalesce(v_free, 0) > 0 then
      update public.worker_profiles
         set free_unlocks_left = free_unlocks_left - 1
       where profile_id = v_me;
      v_method := 'free_quota';
      v_cost := 0;
    else
      perform public.adjust_credits(
        v_me, -v_cost, 'spend_unlock', 'job_request', p_job_id, 'Déverrouillage de contact'
      );
      v_method := 'credits';
    end if;
  end if;

  insert into public.contact_unlocks
    (unlocker_id, target_profile_id, job_id, method, credits_spent, ad_impression_id)
  values
    (v_me, p_target_profile_id, p_job_id, v_method, v_cost, p_ad_impression_id)
  returning * into v_result;

  return v_result;
end;
$$;

grant execute on function public.unlock_contact(uuid, uuid, uuid) to authenticated;

-- =====================================================================
-- A-T-ON DÉVERROUILLÉ CE PROFIL ? — utilisée par les politiques RLS
-- =====================================================================
create or replace function public.has_unlocked(p_target uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.contact_unlocks cu
     where cu.unlocker_id = auth.uid()
       and cu.target_profile_id = p_target
  );
$$;

grant execute on function public.has_unlocked(uuid) to authenticated;
