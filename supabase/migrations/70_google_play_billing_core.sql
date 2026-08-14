-- Socle Google Play Billing. TRAVAIL EN SUSPENS — voir docs/play_billing.md
--
-- Appliqué en base, mais inerte : aucune ligne dans `play_products`, donc
-- `record_play_purchase` refuse tout, et aucun client ne sait encore
-- acheter. Rien n'est exposé tant que le catalogue reste vide.
--
-- Principe de sécurité, le même que pour la SSV publicitaire : le client
-- annonce un achat, il ne le valide jamais. Un appareil peut mentir. Seule
-- l'Edge Function, avec le rôle de service et après réponse de l'API Google
-- Play Developer, transforme une annonce en droit. Cette Edge Function
-- n'est pas écrite.

-- ── Catalogue ────────────────────────────────────────────────────────────
-- Le lien entre ce que vend TiConnect et ce que connaît la Play Console.
-- Les identifiants produit y sont créés à la main ; les stocker ici évite
-- de les figer dans le code, où chaque ajout d'offre exigerait une
-- republication.
--
-- Le PRIX N'Y FIGURE PAS, et c'est le renoncement principal : avec Play
-- Billing, le tarif par pays appartient à la Play Console. `plan_prices`
-- reste la source pour les prestataires locaux, jamais pour Play.
create table if not exists public.play_products (
  product_id     text primary key,
  kind           text not null check (kind in ('subscription', 'credits', 'boost')),
  plan           public.subscription_plan,
  billing_period public.billing_period,
  credits        int  not null default 0,
  boost_hours    int  not null default 0,
  label          text not null,
  sort_order     smallint not null default 0,
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),

  -- Un abonnement sans plan ni périodicité ne peut pas être activé ; un
  -- lot de crédits sans crédits ne donne rien. Le refus est ici plutôt que
  -- dans l'Edge Function, où il arriverait après le paiement.
  constraint play_products_subscription_complet check (
    kind <> 'subscription' or (plan is not null and billing_period is not null)
  ),
  constraint play_products_credits_positifs check (
    kind <> 'credits' or credits > 0
  ),
  constraint play_products_boost_positif check (
    kind <> 'boost' or boost_hours > 0
  )
);

alter table public.play_products enable row level security;

drop policy if exists play_products_read on public.play_products;
create policy play_products_read on public.play_products
  for select to anon, authenticated using (is_active);

drop policy if exists play_products_admin on public.play_products;
create policy play_products_admin on public.play_products
  for all to authenticated
  using ((select public.is_superadmin())) with check ((select public.is_superadmin()));

-- ── Registre des achats ──────────────────────────────────────────────────
-- Clé primaire = jeton d'achat Google. C'est ce qui rend l'opération
-- idempotente : un même achat rejoué — reprise après coupure, restauration
-- sur un nouvel appareil, notification temps réel doublée — ne peut pas
-- accorder deux fois le droit.
create table if not exists public.play_purchases (
  purchase_token text primary key,
  profile_id     uuid not null references public.profiles(id) on delete cascade,
  product_id     text not null,
  order_id       text,
  state          text not null default 'pending'
                 check (state in ('pending', 'verified', 'rejected', 'expired', 'refunded')),
  acknowledged   boolean not null default false,
  expiry_at      timestamptz,
  auto_renewing  boolean,
  failure        text,
  raw            jsonb not null default '{}'::jsonb,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create index if not exists play_purchases_profile_idx
  on public.play_purchases (profile_id, created_at desc);
create index if not exists play_purchases_state_idx
  on public.play_purchases (state) where state = 'pending';

alter table public.play_purchases enable row level security;

-- Lecture de ses propres achats : l'écran d'abonnement doit pouvoir dire
-- « vérification en cours » plutôt que de rester muet.
drop policy if exists play_purchases_select_own on public.play_purchases;
create policy play_purchases_select_own on public.play_purchases
  for select to authenticated using (profile_id = (select auth.uid()));

drop policy if exists play_purchases_admin_read on public.play_purchases;
create policy play_purchases_admin_read on public.play_purchases
  for select to authenticated using ((select public.is_admin()));

-- Aucune politique d'écriture, volontairement. Le client passe par
-- `record_play_purchase`, l'Edge Function par le rôle de service — qui
-- contourne RLS. Une politique d'insertion ouverte au client suffirait à
-- rendre tout le dispositif décoratif.

-- ── Annonce d'achat par le client ────────────────────────────────────────
-- N'accorde rien. Enregistre un jeton à vérifier, et rend l'état courant
-- pour que l'application sache quoi afficher.
create or replace function public.record_play_purchase(
  p_token      text,
  p_product_id text,
  p_order_id   text default null
)
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_state text;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  if coalesce(btrim(p_token), '') = '' then
    raise exception 'TOKEN_REQUIRED';
  end if;
  if not exists (
    select 1 from public.play_products p
     where p.product_id = p_product_id and p.is_active
  ) then
    raise exception 'PRODUCT_UNKNOWN';
  end if;

  insert into public.play_purchases (purchase_token, profile_id, product_id, order_id)
  values (btrim(p_token), auth.uid(), p_product_id, p_order_id)
  on conflict (purchase_token) do update
    set order_id   = coalesce(excluded.order_id, public.play_purchases.order_id),
        updated_at = now()
  returning state into v_state;

  return v_state;
end;
$$;

revoke execute on function public.record_play_purchase(text, text, text) from anon;

-- ── Application d'un achat vérifié ───────────────────────────────────────
-- Réservée au rôle de service. Appelée par l'Edge Function une fois que
-- Google a confirmé l'achat.
create or replace function public.apply_play_purchase(
  p_token     text,
  p_expiry    timestamptz default null,
  p_auto      boolean default null,
  p_raw       jsonb default '{}'::jsonb
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_purchase public.play_purchases;
  v_product  public.play_products;
  v_payment  uuid;
begin
  select * into v_purchase from public.play_purchases
   where purchase_token = p_token for update;
  if not found then
    raise exception 'PURCHASE_UNKNOWN';
  end if;

  -- Rejouer un achat déjà appliqué ne doit rien accorder de plus. Les
  -- notifications temps réel de Google arrivent parfois en double, et une
  -- restauration d'achat rejoue le même jeton.
  if v_purchase.state = 'verified' then
    return jsonb_build_object('state', 'verified', 'already', true);
  end if;

  select * into v_product from public.play_products
   where product_id = v_purchase.product_id;
  if not found then
    update public.play_purchases
       set state = 'rejected', failure = 'PRODUCT_UNKNOWN', updated_at = now()
     where purchase_token = p_token;
    raise exception 'PRODUCT_UNKNOWN';
  end if;

  -- La trace comptable. `amount` reste à zéro : le montant réellement
  -- encaissé appartient à Google, et l'inventer ici donnerait un chiffre
  -- d'affaires faux dans le tableau de bord.
  insert into public.payments (
    profile_id, provider, provider_ref, amount, currency,
    purpose, status, credits_granted, metadata
  )
  values (
    v_purchase.profile_id, 'google_play', p_token, 0, 'USD',
    case v_product.kind
      when 'subscription' then 'subscription'::public.payment_purpose
      when 'credits'      then 'credits'::public.payment_purpose
      else 'boost'::public.payment_purpose
    end,
    'success',
    v_product.credits,
    jsonb_build_object('product_id', v_product.product_id,
                       'order_id',   v_purchase.order_id)
  )
  returning id into v_payment;

  if v_product.kind = 'subscription' then
    perform public.activate_subscription(
      v_purchase.profile_id, v_product.plan, v_product.billing_period,
      0, 'USD', null, v_payment
    );
    -- Google fait autorité sur la date de fin : elle bouge à chaque
    -- renouvellement, et un calcul local dériverait à la première
    -- prolongation de grâce ou au premier report de paiement.
    if p_expiry is not null then
      update public.subscriptions
         set expires_at = p_expiry,
             auto_renew = coalesce(p_auto, auto_renew),
             updated_at = now()
       where profile_id = v_purchase.profile_id and status = 'active';
    end if;

  elsif v_product.kind = 'credits' then
    perform public.grant_credits(
      v_purchase.profile_id, v_product.credits, 'Achat Google Play');

  elsif v_product.kind = 'boost' then
    update public.worker_profiles
       set boosted_until = greatest(
             coalesce(boosted_until, now()), now()
           ) + make_interval(hours => v_product.boost_hours),
           updated_at = now()
     where profile_id = v_purchase.profile_id;
  end if;

  update public.play_purchases
     set state = 'verified',
         expiry_at = coalesce(p_expiry, expiry_at),
         auto_renewing = coalesce(p_auto, auto_renewing),
         raw = p_raw,
         failure = null,
         updated_at = now()
   where purchase_token = p_token;

  return jsonb_build_object('state', 'verified', 'kind', v_product.kind,
                            'payment_id', v_payment);
end;
$$;

revoke execute on function public.apply_play_purchase(text, timestamptz, boolean, jsonb)
  from anon, authenticated;

create or replace function public.reject_play_purchase(p_token text, p_raison text)
returns void language sql security definer set search_path = '' as $$
  update public.play_purchases
     set state = case when p_raison = 'REFUNDED' then 'refunded'
                      when p_raison = 'EXPIRED'  then 'expired'
                      else 'rejected' end,
         failure = p_raison,
         updated_at = now()
   where purchase_token = p_token;
$$;

revoke execute on function public.reject_play_purchase(text, text) from anon, authenticated;
