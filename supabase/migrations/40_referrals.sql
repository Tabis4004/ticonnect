-- =====================================================================
-- 18_referrals.sql — Parrainage de CLIENTS par les ouvriers
--
-- Un ouvrier qui amène dix ouvriers dilue son propre fil de missions : on
-- ajoute de l'offre à une marketplace qui manque de demande, ce qui la rend
-- pire. Un ouvrier qui amène un client apporte du travail dont il profite le
-- premier. Le parrainage est donc réservé aux clients — et l'incitation
-- s'aligne d'elle-même, sans qu'on ait à l'expliquer.
--
-- La récompense n'est PAS un score de classement. C'est du temps de mise en
-- avant (`boosted_until`), qui passe par le plafond posé en migration 15 :
-- au plus un sponsorisé sur N, jamais sous la note plancher, jamais plus que
-- le vivier organique ne peut espacer. Un score séparé serait non borné et
-- entrerait en concurrence avec la note dans l'ordonnancement — exactement
-- le défaut qu'on vient de corriger.
--
-- Le risque à contenir : l'inscription se fait désormais par pseudo et mot
-- de passe, sans SMS. C'est précisément ce qui rendait la fraude au
-- parrainage coûteuse. Un compte se crée maintenant en trente secondes, donc
-- récompenser l'inscription reviendrait à payer pour du vent. D'où le choix
-- de ne compter qu'un acte économique vérifiable : le filleul publie une
-- mission, et cette mission reçoit au moins une candidature d'un tiers.
-- =====================================================================

do $$
begin
  if not exists (select 1 from pg_type where typname = 'referral_status') then
    create type public.referral_status as enum ('pending', 'qualified', 'revoked');
  end if;
end
$$;

-- =====================================================================
-- CODE DE PARRAINAGE
-- =====================================================================
alter table public.profiles
  add column if not exists referral_code text;

create unique index if not exists profiles_referral_code_key
  on public.profiles (referral_code)
  where referral_code is not null;

-- Alphabet sans 0/O ni 1/I/L : ces codes se dictent au téléphone et se
-- recopient à la main. Une confusion de caractère fait perdre un parrainage,
-- et l'utilisateur n'a aucun moyen de comprendre pourquoi.
create or replace function public.new_referral_code()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_code text;
  v_try  integer := 0;
begin
  loop
    v_code := '';
    for i in 1..6 loop
      v_code := v_code || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1);
    end loop;

    exit when not exists (
      select 1 from public.profiles p where p.referral_code = v_code
    );

    v_try := v_try + 1;
    if v_try > 50 then
      raise exception 'Impossible de générer un code de parrainage unique.';
    end if;
  end loop;
  return v_code;
end;
$$;

create or replace function public.assign_referral_code()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.referral_code is null then
    new.referral_code := public.new_referral_code();
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_assign_referral_code on public.profiles;
create trigger profiles_assign_referral_code
  before insert on public.profiles
  for each row execute function public.assign_referral_code();

-- Rattrapage des profils existants.
update public.profiles
   set referral_code = public.new_referral_code()
 where referral_code is null;

-- =====================================================================
-- PARRAINAGES
-- =====================================================================
create table if not exists public.referrals (
  id                uuid primary key default gen_random_uuid(),
  referrer_id       uuid not null references public.profiles(id) on delete cascade,
  referee_id        uuid not null references public.profiles(id) on delete cascade,
  code              text not null,
  status            public.referral_status not null default 'pending',
  qualifying_job_id uuid references public.job_requests(id) on delete set null,
  boost_days        smallint not null default 0 check (boost_days >= 0),
  qualified_at      timestamptz,
  revoked_reason    text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint referral_distinct_parties check (referrer_id <> referee_id)
);

-- Un filleul n'a qu'un parrain, définitivement. Sans cette contrainte, un
-- même compte se ferait « reparrainer » à chaque nouveau code.
create unique index if not exists referrals_referee_key
  on public.referrals (referee_id);
create index if not exists referrals_referrer_idx
  on public.referrals (referrer_id, status, created_at desc);

drop trigger if exists referrals_set_updated_at on public.referrals;
create trigger referrals_set_updated_at
  before update on public.referrals
  for each row execute function public.set_updated_at();

alter table public.referrals enable row level security;

-- Chacun voit les parrainages où il figure. Les écritures passent
-- exclusivement par les fonctions ci-dessous : laisser le client insérer
-- lui-même reviendrait à lui laisser fabriquer ses propres filleuls.
drop policy if exists referrals_select_involved on public.referrals;
create policy referrals_select_involved on public.referrals
  for select to authenticated
  using (referrer_id = (select auth.uid()) or referee_id = (select auth.uid()));

drop policy if exists referrals_admin_all on public.referrals;
create policy referrals_admin_all on public.referrals
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- =====================================================================
-- RÉGLAGES
-- =====================================================================
insert into public.app_settings (key, value, description) values
  ('referral_enabled', 'true'::jsonb,
    'Parrainage de clients par les ouvriers.'),

  ('referral_boost_days', '[7, 5, 3, 1]'::jsonb,
    'Jours de mise en avant par parrainage qualifié, du premier au suivant. '
    'La dernière valeur s''applique à tous les parrainages au-delà. Les '
    'rendements décroissants évitent qu''un seul ouvrier très actif '
    'monopolise les places sponsorisées.'),

  ('referral_monthly_cap_days', '20'::jsonb,
    'Plafond de jours de boost gagnés par parrainage sur 30 jours glissants.'),

  ('referral_claim_window_days', '30'::jsonb,
    'Un code ne peut être réclamé que dans les N jours suivant la création du '
    'compte. Au-delà, il ne s''agit plus d''acquisition.')
on conflict (key) do nothing;

-- =====================================================================
-- RÉCLAMATION D'UN CODE
--
-- Appelée par le filleul, une seule fois, peu après son inscription.
-- =====================================================================
create or replace function public.claim_referral(p_code text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me       uuid := auth.uid();
  v_referrer uuid;
  v_created  timestamptz;
  v_window   integer;
begin
  if v_me is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  if coalesce((public.app_setting('referral_enabled', 'true'::jsonb))::text::boolean, true) = false then
    raise exception 'REFERRAL_DISABLED';
  end if;

  select p.id into v_referrer
    from public.profiles p
   where p.referral_code = upper(trim(p_code));

  if v_referrer is null then
    raise exception 'REFERRAL_CODE_UNKNOWN';
  end if;

  if v_referrer = v_me then
    raise exception 'REFERRAL_SELF';
  end if;

  if exists (select 1 from public.referrals r where r.referee_id = v_me) then
    raise exception 'REFERRAL_ALREADY_CLAIMED';
  end if;

  -- Un parrain suspendu ne recrute pas.
  if exists (select 1 from public.profiles p
              where p.id = v_referrer and p.is_suspended) then
    raise exception 'REFERRAL_CODE_UNKNOWN';
  end if;

  select p.created_at into v_created from public.profiles p where p.id = v_me;
  v_window := coalesce(
    (public.app_setting('referral_claim_window_days', '30'::jsonb))::text::int, 30);

  if v_created < now() - make_interval(days => v_window) then
    raise exception 'REFERRAL_WINDOW_CLOSED';
  end if;

  -- Même appareil : signal de fraude le plus simple à obtenir. La table
  -- `devices` est encore vide tant que les notifications push ne sont pas
  -- branchées ; ce contrôle s'activera de lui-même à ce moment-là.
  if exists (
    select 1
      from public.devices d1
      join public.devices d2 on d2.fcm_token = d1.fcm_token
     where d1.profile_id = v_me and d2.profile_id = v_referrer
  ) then
    raise exception 'REFERRAL_SAME_DEVICE';
  end if;

  insert into public.referrals (referrer_id, referee_id, code)
  values (v_referrer, v_me, upper(trim(p_code)));

  return 'pending';
end;
$$;

grant execute on function public.claim_referral(text) to authenticated;

-- =====================================================================
-- QUALIFICATION
--
-- Déclenchée par l'arrivée d'une candidature sur une mission. C'est
-- l'événement le moins falsifiable de la chaîne : il suppose un client qui
-- a renseigné son numéro (migration 16), publié une mission réelle, et un
-- ouvrier TIERS qui y a répondu. Un fraudeur devrait donc contrôler trois
-- comptes avec trois numéros distincts pour gagner un jour de boost.
-- =====================================================================
create or replace function public.qualify_referral_on_application()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_client   uuid;
  v_ref      public.referrals%rowtype;
  v_rank     integer;
  v_ladder   jsonb;
  v_days     integer;
  v_used     integer;
  v_cap      integer;
begin
  select jr.client_id into v_client
    from public.job_requests jr where jr.id = new.job_id;

  if v_client is null then
    return null;
  end if;

  select * into v_ref
    from public.referrals r
   where r.referee_id = v_client and r.status = 'pending'
   limit 1;

  if v_ref.id is null then
    return null;
  end if;

  -- Le parrain ne peut pas être l'ouvrier qui candidate : sinon il lui
  -- suffit de créer un faux client, de publier une mission et d'y répondre
  -- lui-même.
  if new.worker_id = v_ref.referrer_id then
    return null;
  end if;

  -- Parrain suspendu entre-temps : on qualifie sans récompenser, pour que
  -- la ligne cesse d'être en attente.
  if exists (select 1 from public.profiles p
              where p.id = v_ref.referrer_id and p.is_suspended) then
    update public.referrals
       set status = 'revoked', revoked_reason = 'Parrain suspendu',
           updated_at = now()
     where id = v_ref.id;
    return null;
  end if;

  -- Position dans l'échelle des rendements décroissants.
  select count(*) into v_rank
    from public.referrals r
   where r.referrer_id = v_ref.referrer_id and r.status = 'qualified';

  v_ladder := public.app_setting('referral_boost_days', '[7, 5, 3, 1]'::jsonb);
  v_days := coalesce(
    (v_ladder -> least(v_rank, jsonb_array_length(v_ladder) - 1))::text::int, 1);

  -- Plafond glissant sur 30 jours.
  select coalesce(sum(r.boost_days), 0) into v_used
    from public.referrals r
   where r.referrer_id = v_ref.referrer_id
     and r.status = 'qualified'
     and r.qualified_at > now() - interval '30 days';

  v_cap := coalesce(
    (public.app_setting('referral_monthly_cap_days', '20'::jsonb))::text::int, 20);
  v_days := greatest(least(v_days, v_cap - v_used), 0);

  update public.referrals
     set status = 'qualified',
         qualifying_job_id = new.job_id,
         boost_days = v_days,
         qualified_at = now(),
         updated_at = now()
   where id = v_ref.id;

  if v_days > 0 then
    -- Prolongement, pas remplacement : un boost en cours ne doit pas être
    -- écrasé par un parrainage qui arrive au mauvais moment.
    --
    -- L'écriture sur `boosted_until` reste possible ici alors que le droit
    -- a été retiré à `authenticated` (30_column_privileges) : cette fonction est
    -- `security definer` et s'exécute avec les droits de son propriétaire.
    -- C'est voulu — la colonne ne doit se modifier que par ce chemin et
    -- par `grant_boost()`, jamais par un appel PostgREST direct.
    update public.worker_profiles wp
       set boosted_until = greatest(coalesce(wp.boosted_until, now()), now())
                           + make_interval(days => v_days),
           updated_at = now()
     where wp.profile_id = v_ref.referrer_id;

    insert into public.notifications (profile_id, kind, title, body, payload)
    values (
      v_ref.referrer_id, 'referral',
      'Parrainage validé',
      'Un client que tu as invité vient de publier une mission. '
        || v_days || ' jour(s) de mise en avant ajoutés à ton profil.',
      jsonb_build_object('referral_id', v_ref.id, 'boost_days', v_days)
    );
  end if;

  return null;
end;
$$;

drop trigger if exists job_applications_qualify_referral on public.job_applications;
create trigger job_applications_qualify_referral
  after insert on public.job_applications
  for each row execute function public.qualify_referral_on_application();

-- =====================================================================
-- RÉVOCATION
--
-- Un numéro banni annule le parrainage qu'il a servi à obtenir, et reprend
-- les jours accordés. Sans cette reprise, la fraude resterait rentable :
-- créer un faux client, encaisser le boost, se faire bannir, garder le boost.
-- =====================================================================
create or replace function public.revoke_referrals_for_banned()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile uuid;
  v_ref     public.referrals%rowtype;
begin
  select cd.profile_id into v_profile
    from public.contact_details cd where cd.phone = new.phone;

  if v_profile is null then
    return new;
  end if;

  for v_ref in
    select * from public.referrals r
     where r.referee_id = v_profile and r.status = 'qualified'
  loop
    if v_ref.boost_days > 0 then
      update public.worker_profiles wp
         set boosted_until = greatest(
               now(),
               coalesce(wp.boosted_until, now())
                 - make_interval(days => v_ref.boost_days)),
             updated_at = now()
       where wp.profile_id = v_ref.referrer_id;
    end if;

    update public.referrals
       set status = 'revoked',
           revoked_reason = 'Filleul banni',
           boost_days = 0,
           updated_at = now()
     where id = v_ref.id;
  end loop;

  return new;
end;
$$;

drop trigger if exists banned_contacts_revoke_referrals on public.banned_contacts;
create trigger banned_contacts_revoke_referrals
  after insert on public.banned_contacts
  for each row execute function public.revoke_referrals_for_banned();

-- =====================================================================
-- TABLEAU DE BORD DU PARRAIN
-- =====================================================================
create or replace function public.my_referral_stats()
returns table (
  code             text,
  pending_count    integer,
  qualified_count  integer,
  revoked_count    integer,
  boost_days_total integer,
  boost_days_30d   integer,
  monthly_cap      integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    (select p.referral_code from public.profiles p where p.id = auth.uid()),
    count(*) filter (where r.status = 'pending')::int,
    count(*) filter (where r.status = 'qualified')::int,
    count(*) filter (where r.status = 'revoked')::int,
    coalesce(sum(r.boost_days), 0)::int,
    coalesce(sum(r.boost_days) filter (
      where r.qualified_at > now() - interval '30 days'), 0)::int,
    coalesce((public.app_setting('referral_monthly_cap_days', '20'::jsonb))::text::int, 20)
  from public.referrals r
  where r.referrer_id = auth.uid();
$$;

grant execute on function public.my_referral_stats() to authenticated;
