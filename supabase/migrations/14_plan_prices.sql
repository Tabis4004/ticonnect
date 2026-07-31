-- =====================================================================
-- 14_plan_prices.sql — Grille tarifaire par pays, abonnements mensuels
--                      et annuels
--
-- Les conditions économiques diffèrent trop d'un pays à l'autre pour
-- qu'un prix figé dans le code ait un sens : un montant acceptable à
-- Abidjan ne l'est pas à Lagos, et l'inflation ne suit pas le rythme des
-- publications sur le Play Store. La grille vit donc en base.
--
-- Deux principes de tarification, tirés du benchmark régional :
--
--   · Le mensuel reste la porte d'entrée. Le mobile money d'Afrique de
--     l'Ouest est une culture de petits montants fréquents ; demander une
--     année d'avance à un artisan du secteur informel écarte la majorité
--     de la cible.
--   · L'annuel se vend par la remise, pas par l'obligation : dix mois
--     payés pour douze.
--
-- Les montants ci-dessous sont des points de départ, pas des références.
-- Ils s'ajustent depuis le tableau de bord admin.
-- =====================================================================

create table if not exists public.plan_prices (
  id             uuid primary key default gen_random_uuid(),
  country_code   text not null check (char_length(country_code) = 2),
  plan           public.subscription_plan not null,
  billing_period public.billing_period not null,
  amount         numeric(12,2) not null check (amount >= 0),
  currency       text not null check (char_length(currency) = 3),
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (country_code, plan, billing_period)
);

comment on table public.plan_prices is
  'Grille tarifaire par pays. Le pays fictif "XX" sert de repli pour tout '
  'pays non renseigné : une absence de ligne ne doit jamais empêcher '
  'd''afficher un prix.';

drop trigger if exists plan_prices_set_updated_at on public.plan_prices;
create trigger plan_prices_set_updated_at
  before update on public.plan_prices
  for each row execute function public.set_updated_at();

create index if not exists plan_prices_lookup_idx
  on public.plan_prices (country_code, plan, billing_period)
  where is_active;

alter table public.plan_prices enable row level security;

drop policy if exists plan_prices_select_all on public.plan_prices;
create policy plan_prices_select_all on public.plan_prices
  for select to authenticated using (is_active or public.is_admin());

drop policy if exists plan_prices_admin_write on public.plan_prices;
create policy plan_prices_admin_write on public.plan_prices
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- =====================================================================
-- SEED — montants indicatifs, à recalibrer par marché
--
-- Repères qui ont guidé la zone XOF : l'abonnement Pro de sMaxSell est à
-- 5 000 FCFA/mois, et un ouvrier qui passe par une plateforme à
-- commission verse déjà l'équivalent sur un seul chantier. Se placer à
-- 2 000 FCFA laisse un écart lisible en phase de conquête.
-- =====================================================================
with zones(country_code, currency, pro_m, pro_y, prem_m, prem_y) as (
  values
    -- Zone franc CFA Ouest (UEMOA)
    ('XX', 'XOF',  2000,  20000,  5000,  50000),   -- repli par défaut
    ('CI', 'XOF',  2000,  20000,  5000,  50000),
    ('SN', 'XOF',  2000,  20000,  5000,  50000),
    ('ML', 'XOF',  1500,  15000,  4000,  40000),
    ('BF', 'XOF',  1500,  15000,  4000,  40000),
    ('BJ', 'XOF',  2000,  20000,  5000,  50000),
    ('TG', 'XOF',  1500,  15000,  4000,  40000),
    ('NE', 'XOF',  1500,  15000,  4000,  40000),
    ('GW', 'XOF',  1500,  15000,  4000,  40000),
    -- Zone franc CFA Centrale (CEMAC) — parité avec le XOF
    ('CM', 'XAF',  2000,  20000,  5000,  50000),
    ('GA', 'XAF',  2500,  25000,  6000,  60000),
    ('CG', 'XAF',  2000,  20000,  5000,  50000),
    ('TD', 'XAF',  1500,  15000,  4000,  40000),
    ('CF', 'XAF',  1500,  15000,  4000,  40000),
    ('GQ', 'XAF',  2500,  25000,  6000,  60000),
    -- Hors zone franc
    ('GH', 'GHS',    25,    250,    60,    600),
    ('NG', 'NGN',  3000,  30000,  7500,  75000),
    ('GN', 'GNF', 30000, 300000, 75000, 750000),
    ('MA', 'MAD',    35,    350,    90,    900),
    ('CD', 'CDF',  9000,  90000, 22000, 220000)
)
insert into public.plan_prices (country_code, plan, billing_period, amount, currency)
select country_code, 'pro'::public.subscription_plan,
       'monthly'::public.billing_period, pro_m, currency from zones
union all
select country_code, 'pro', 'annual',  pro_y,  currency from zones
union all
select country_code, 'premium', 'monthly', prem_m, currency from zones
union all
select country_code, 'premium', 'annual',  prem_y, currency from zones
on conflict (country_code, plan, billing_period) do nothing;

-- =====================================================================
-- CONSULTATION DU TARIF
-- =====================================================================
create or replace function public.plan_price(
  p_country text,
  p_plan    public.subscription_plan,
  p_period  public.billing_period
)
returns table (amount numeric, currency text)
language sql
stable
security definer
set search_path = ''
as $$
  -- Le tri explicite n'est pas décoratif : un LIMIT posé sur un UNION ALL
  -- ne garantit pas laquelle des deux branches sort en premier. Sans lui,
  -- le tarif de repli « XX » pourrait masquer le tarif du pays réel, au
  -- gré du plan d'exécution.
  select pp.amount, pp.currency
    from public.plan_prices pp
   where pp.plan = p_plan
     and pp.billing_period = p_period
     and pp.is_active
     and pp.country_code in (upper(coalesce(p_country, 'XX')), 'XX')
   order by case
              when pp.country_code = upper(coalesce(p_country, 'XX')) then 0
              else 1
            end
   limit 1;
$$;

grant execute on function public.plan_price(text, public.subscription_plan, public.billing_period)
  to authenticated;

-- =====================================================================
-- ABONNEMENTS — périodicité et montant payé
--
-- On fige le montant sur la ligne d'abonnement plutôt que de le relire
-- dans la grille : un changement de tarif ne doit pas réécrire l'histoire
-- de ce qu'un utilisateur a réellement payé.
-- =====================================================================
alter table public.subscriptions
  add column if not exists billing_period public.billing_period not null default 'monthly',
  add column if not exists amount_paid    numeric(12,2),
  add column if not exists currency       text,
  add column if not exists country_code   text,
  add column if not exists cancelled_at   timestamptz;

comment on column public.subscriptions.amount_paid is
  'Montant réellement réglé, figé au moment du paiement.';

-- =====================================================================
-- PLAN ACTIF D'UN PROFIL
--
-- Un abonnement expiré n'est pas nécessairement marqué comme tel : la
-- date fait foi, pas le statut, sinon toute panne de tâche planifiée
-- offrirait du premium à vie.
-- =====================================================================
create or replace function public.active_plan(p_profile uuid)
returns public.subscription_plan
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select s.plan
       from public.subscriptions s
      where s.profile_id = p_profile
        and s.status = 'active'
        and (s.expires_at is null or s.expires_at > now())
      order by case s.plan when 'premium' then 2 when 'pro' then 1 else 0 end desc
      limit 1),
    'free'::public.subscription_plan
  );
$$;

grant execute on function public.active_plan(uuid) to authenticated;

create or replace function public.my_plan()
returns public.subscription_plan
language sql
stable
security definer
set search_path = ''
as $$
  select public.active_plan(auth.uid());
$$;

grant execute on function public.my_plan() to authenticated;

-- =====================================================================
-- ACTIVATION D'UN ABONNEMENT
--
-- Appelée exclusivement par l'Edge Function de callback paiement, avec la
-- clé `service_role`. L'exécution est révoquée pour les clients : sans
-- cela, n'importe quel APK modifié s'offrirait un abonnement premium.
--
-- Le prolongement part de la date d'expiration en cours quand elle est
-- encore valide — renouveler avant l'échéance ne doit pas faire perdre
-- les jours restants.
-- =====================================================================
create or replace function public.activate_subscription(
  p_profile     uuid,
  p_plan        public.subscription_plan,
  p_period      public.billing_period,
  p_amount      numeric default null,
  p_currency    text default null,
  p_country     text default null,
  p_payment_id  uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id      uuid;
  v_from    timestamptz;
  v_until   timestamptz;
  v_current timestamptz;
begin
  if p_plan = 'free' then
    raise exception 'Le plan gratuit ne se souscrit pas.';
  end if;

  select s.expires_at into v_current
    from public.subscriptions s
   where s.profile_id = p_profile
     and s.status = 'active'
     and (s.expires_at is null or s.expires_at > now())
   limit 1;

  v_from  := greatest(coalesce(v_current, now()), now());
  v_until := case p_period
               when 'annual' then v_from + interval '1 year'
               else               v_from + interval '1 month'
             end;

  -- Un seul abonnement actif par profil : l'index unique partiel
  -- `subscriptions_active_idx` l'impose, on solde donc l'existant.
  update public.subscriptions
     set status = 'expired', updated_at = now()
   where profile_id = p_profile and status = 'active';

  insert into public.subscriptions
    (profile_id, plan, status, billing_period, started_at, expires_at,
     amount_paid, currency, country_code)
  values
    (p_profile, p_plan, 'active', p_period, now(), v_until,
     p_amount, p_currency, upper(p_country))
  returning id into v_id;

  if p_payment_id is not null then
    update public.payments
       set subscription_id = v_id, updated_at = now()
     where id = p_payment_id;
  end if;

  return v_id;
end;
$$;

revoke execute on function public.activate_subscription(
  uuid, public.subscription_plan, public.billing_period,
  numeric, text, text, uuid) from public, anon, authenticated;

-- =====================================================================
-- EXPIRATION
--
-- À brancher sur pg_cron, ou à appeler depuis la même tâche planifiée que
-- `expire_stale_jobs()`.
-- =====================================================================
create or replace function public.expire_subscriptions()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  update public.subscriptions
     set status = 'expired', updated_at = now()
   where status = 'active'
     and expires_at is not null
     and expires_at <= now();
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function public.expire_subscriptions() from public, anon, authenticated;
