-- =====================================================================
-- 70_realty.sql — Annonces immobilières : le socle
--
-- Ventes et locations : terrain, maison, appartement, chambre, local.
-- L'annonce est visible de tous ; l'adresse exacte, les photos en pleine
-- définition, le plan et le numéro du vendeur ne s'ouvrent qu'après
-- déblocage.
--
-- DEUX DÉCISIONS QUI PORTENT TOUT LE RESTE
--
-- 1. La référence foncière reste GRATUITE. La fermer reviendrait à faire
--    payer un acheteur qui ne peut rien vérifier avant de payer. Affichée,
--    elle devient l'argument du produit : on vérifie le titre d'abord, on
--    paie le contact ensuite. Elle est exigée en vente, et laissée libre
--    en location — un loueur de chambre n'a pas le titre entre les mains,
--    et l'exiger viderait la catégorie qui fera le volume.
--
-- 2. Le registre des déblocages ne dépend pas du régime. `listing_unlocks`
--    enregistre qui a ouvert quoi ; `granted_by` note seulement comment.
--    Passer de la gratuité à la publicité puis au paiement ne réécrit rien
--    et ne referme aucun déblocage acquis : ce qui est ouvert reste ouvert,
--    c'est la promesse faite à l'acheteur.
--
-- CE QUE LA RLS NE SAIT PAS FAIRE
--
-- Les politiques RLS filtrent des LIGNES, or ici la ligne est publique et
-- ce sont trois COLONNES qu'il faut fermer. Une politique n'y peut rien :
-- n'importe quel client pourrait demander `select *` et lire l'adresse et
-- le téléphone sans avoir rien débloqué. On retire donc le droit de lecture
-- sur ces colonnes — même méthode que `column_privileges` — et on les sert
-- par une fonction qui vérifie le déblocage. Masquer à l'écran ne protège
-- de rien.
-- =====================================================================

do $$ begin
  create type public.realty_deal as enum ('vente', 'location');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.realty_property as enum
    ('terrain', 'maison', 'appartement', 'chambre', 'local');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.realty_status as enum
    ('brouillon', 'publiee', 'suspendue', 'conclue', 'expiree');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- L'annonce
-- ---------------------------------------------------------------------------
create table if not exists public.listings (
  id            uuid primary key default gen_random_uuid(),
  seller_id     uuid not null references public.profiles(id) on delete cascade,

  deal          public.realty_deal     not null,
  property      public.realty_property not null,

  title         text not null,
  description   text,

  country_code  text not null,
  city          text not null,
  neighborhood  text,

  -- Fermées. Voir l'en-tête : ce sont elles qui se paient.
  address_exact text,
  contact_phone text,

  price         numeric(12,0) not null check (price >= 0),
  currency      text not null default 'XOF',
  -- Renseignée pour une location, nulle pour une vente. La contrainte plus
  -- bas l'impose : « 25 000 » sans période ne veut rien dire sur une
  -- location, et « par mois » sur une vente est une faute de saisie.
  price_period  text check (price_period in ('jour', 'mois', 'an')),

  surface_m2    numeric(10,2) check (surface_m2 is null or surface_m2 > 0),
  rooms         smallint      check (rooms is null or rooms between 0 and 50),

  -- Numéro d'identification du bien au registre foncier du pays. Au Togo,
  -- le NUP. Ailleurs, ce que le pays délivre. Le format n'est pas contraint
  -- au-delà d'une longueur minimale : un masque par pays serait faux le
  -- jour où un pays change le sien, et refuserait des annonces valables.
  land_reference text,

  status        public.realty_status not null default 'brouillon',
  views_count   integer not null default 0,
  unlocks_count integer not null default 0,

  expires_at    timestamptz not null default now() + interval '60 days',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  constraint listings_terrain_vente_only
    check (property <> 'terrain' or deal = 'vente'),

  constraint listings_period_matches_deal
    check ((deal = 'location') = (price_period is not null)),

  -- La règle qui a été arbitrée : exigée en vente, libre en location.
  constraint listings_reference_required_on_sale
    check (deal <> 'vente'
           or (land_reference is not null and length(btrim(land_reference)) >= 4))
);

comment on column public.listings.land_reference is
  'Numéro d''identification au registre foncier du pays. Obligatoire en '
  'vente. Affiché librement : il sert à vérifier le titre AVANT de payer.';
comment on column public.listings.address_exact is
  'Fermée. Le droit de lecture est retiré à anon et authenticated ; elle se '
  'lit par listing_private(), qui vérifie le déblocage.';

create index if not exists listings_browse_idx
  on public.listings (country_code, deal, property, status, created_at desc);
create index if not exists listings_city_idx
  on public.listings (country_code, city, status);
create index if not exists listings_seller_idx
  on public.listings (seller_id, created_at desc);

drop trigger if exists listings_touch on public.listings;
create trigger listings_touch before update on public.listings
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Les images
--
-- `storage_path` désigne l'original, dans un bucket privé, jamais servi
-- directement. `preview_path` désigne l'aperçu flouté et léger, celui que
-- tout le monde voit. La copie filigranée au nom de l'acheteur n'est pas
-- ici : elle appartient au déblocage, pas au média.
-- ---------------------------------------------------------------------------
create table if not exists public.listing_media (
  id           uuid primary key default gen_random_uuid(),
  listing_id   uuid not null references public.listings(id) on delete cascade,
  kind         text not null check (kind in ('photo', 'plan')),
  storage_path text not null,
  preview_path text,
  sort_order   smallint not null default 0,
  created_at   timestamptz not null default now()
);

create index if not exists listing_media_listing_idx
  on public.listing_media (listing_id, kind, sort_order);

-- ---------------------------------------------------------------------------
-- Le registre des déblocages
--
-- Une ligne par couple (annonce, acheteur), et une seule : on paie une
-- fois, on revient autant qu'on veut.
-- ---------------------------------------------------------------------------
create table if not exists public.listing_unlocks (
  id               uuid primary key default gen_random_uuid(),
  listing_id       uuid not null references public.listings(id) on delete cascade,
  buyer_id         uuid not null references public.profiles(id) on delete cascade,

  granted_by       text not null
                   check (granted_by in ('free', 'ad', 'payment', 'seller', 'admin')),
  ad_impression_id uuid references public.ad_impressions(id) on delete set null,
  payment_id       uuid references public.payments(id) on delete set null,

  -- Rempli par la chaîne d'images : le plan filigrané au nom de cet
  -- acheteur. Nul tant qu'il n'a pas été fabriqué.
  watermarked_path text,

  created_at       timestamptz not null default now(),

  unique (listing_id, buyer_id)
);

create index if not exists listing_unlocks_buyer_idx
  on public.listing_unlocks (buyer_id, created_at desc);

-- =====================================================================
-- FERMETURE DES COLONNES PAYANTES
--
-- PostgreSQL ne sait pas retirer la lecture d'une seule colonne : il faut
-- tout retirer, puis rendre les colonnes libres une par une. Toute colonne
-- ajoutée plus tard à `listings` devra donc être nommée ici, sinon elle
-- restera invisible — désagrément assumé, il va dans le bon sens : on
-- oublie d'ouvrir, on n'oublie pas de fermer.
-- =====================================================================
revoke all on public.listings      from anon, authenticated;
revoke all on public.listing_media from anon, authenticated;

grant select (id, seller_id, deal, property, title, description,
              country_code, city, neighborhood,
              price, currency, price_period, surface_m2, rooms,
              land_reference, status, views_count, unlocks_count,
              expires_at, created_at, updated_at)
  on public.listings to anon, authenticated;

-- L'écriture reste entière : le vendeur saisit son adresse et son numéro.
-- Il ne peut simplement pas les relire par une requête directe — il passe,
-- comme l'acheteur, par listing_private().
grant insert, update, delete on public.listings to authenticated;

grant select (id, listing_id, kind, preview_path, sort_order, created_at)
  on public.listing_media to anon, authenticated;
grant insert, update, delete on public.listing_media to authenticated;

grant select, insert, update, delete on public.listing_unlocks to authenticated;

-- =====================================================================
-- POLITIQUES
-- =====================================================================
alter table public.listings       enable row level security;
alter table public.listing_media  enable row level security;
alter table public.listing_unlocks enable row level security;

drop policy if exists listings_read on public.listings;
create policy listings_read on public.listings
  for select using (
    status = 'publiee'
    or seller_id = auth.uid()
    or public.is_admin()
  );

drop policy if exists listings_write_own on public.listings;
create policy listings_write_own on public.listings
  for insert to authenticated with check (seller_id = auth.uid());

drop policy if exists listings_update_own on public.listings;
create policy listings_update_own on public.listings
  for update to authenticated
  using (seller_id = auth.uid() or public.is_admin())
  with check (seller_id = auth.uid() or public.is_admin());

drop policy if exists listings_delete_own on public.listings;
create policy listings_delete_own on public.listings
  for delete to authenticated
  using (seller_id = auth.uid() or public.is_admin());

drop policy if exists listing_media_read on public.listing_media;
create policy listing_media_read on public.listing_media
  for select using (
    exists (select 1 from public.listings l
             where l.id = listing_id
               and (l.status = 'publiee' or l.seller_id = auth.uid()
                    or public.is_admin()))
  );

drop policy if exists listing_media_write_own on public.listing_media;
create policy listing_media_write_own on public.listing_media
  for all to authenticated
  using (exists (select 1 from public.listings l
                  where l.id = listing_id
                    and (l.seller_id = auth.uid() or public.is_admin())))
  with check (exists (select 1 from public.listings l
                       where l.id = listing_id
                         and (l.seller_id = auth.uid() or public.is_admin())));

-- Le déblocage se lit par son acheteur, par le vendeur concerné (il a le
-- droit de savoir combien de personnes ont ouvert son annonce, et
-- lesquelles), et par l'administration. Il ne s'écrit par personne :
-- `unlock_listing()` est la seule porte, et elle est `security definer`.
drop policy if exists listing_unlocks_read on public.listing_unlocks;
create policy listing_unlocks_read on public.listing_unlocks
  for select using (
    buyer_id = auth.uid()
    or public.is_admin()
    or exists (select 1 from public.listings l
                where l.id = listing_id and l.seller_id = auth.uid())
  );

-- =====================================================================
-- RÉGLAGES
-- =====================================================================
insert into public.app_settings (key, value, description, control, label,
                                 group_name, sort_order, is_visible)
values
  ('realty_enabled', 'false'::jsonb,
   'Affiche le module immobilier dans l''application. Laisser éteint tant '
   'que les annonces de départ ne sont pas en place : une rubrique vide '
   'donne l''impression d''un produit mort.',
   'switch', 'Module immobilier', 'Immobilier', 10, true),

  ('realty_unlock_mode', '"gratuit"'::jsonb,
   'Comment un acheteur ouvre une annonce. Gratuit : d''un geste. Vidéo : '
   'contre le visionnage d''une publicité récompensée. Payant : non '
   'branché — le canal de paiement doit être choisi avant.',
   'choice', 'Régime de déblocage', 'Immobilier', 20, true),

  ('realty_unlock_price', '200'::jsonb,
   'Prix d''un déblocage en régime payant, dans la monnaie du pays. Sans '
   'effet dans les deux autres régimes.',
   'number', 'Prix d''un déblocage', 'Immobilier', 30, true),

  ('realty_listing_days', '60'::jsonb,
   'Durée de vie d''une annonce avant expiration.',
   'number', 'Durée d''une annonce', 'Immobilier', 40, true)
on conflict (key) do nothing;

update public.app_settings set
  choices = '[{"value":"gratuit","label":"Gratuit"},
              {"value":"video","label":"Contre une vidéo"},
              {"value":"payant","label":"Payant"}]'::jsonb
 where key = 'realty_unlock_mode';

update public.app_settings set min_value = 0,   max_value = 100000, step = 50,
                               suffix = 'XOF'   where key = 'realty_unlock_price';
update public.app_settings set min_value = 7,   max_value = 365,    step = 1,
                               suffix = 'jours' where key = 'realty_listing_days';

-- L'emplacement publicitaire du régime « vidéo », éteint tant que le régime
-- n'est pas choisi. Son unité AdMob reste à créer ; sans elle, rien ne se
-- charge et `unlock_listing` refusera proprement.
insert into public.ad_placements (key, format, is_enabled, description,
                                  intro_title, intro_body, intro_cta, skip_label)
values ('realty_unlock_rewarded', 'rewarded', false,
        'Ouvre une annonce immobilière contre le visionnage d''une vidéo.',
        'Ouvrir cette annonce',
        'Regarde une courte vidéo pour voir le plan, l''adresse exacte et '
        'le numéro du vendeur. L''annonce restera ouverte pour toi.',
        'Regarder', 'Plus tard')
on conflict (key) do nothing;

-- =====================================================================
-- LECTURE DES CHAMPS FERMÉS
-- =====================================================================
create or replace function public.listing_is_unlocked(p_listing uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select auth.uid() is not null and (
    exists (select 1 from public.listing_unlocks u
             where u.listing_id = p_listing and u.buyer_id = auth.uid())
    or exists (select 1 from public.listings l
                where l.id = p_listing and l.seller_id = auth.uid())
    or public.is_admin()
  );
$$;

-- Ce que le déblocage achète, et rien d'autre.
create or replace function public.listing_private(p_listing uuid)
returns table (
  address_exact    text,
  contact_phone    text,
  contact_whatsapp text,
  plan_path        text,
  watermarked_path text
)
language plpgsql
stable
security definer
set search_path to 'public'
as $$
begin
  if not public.listing_is_unlocked(p_listing) then
    raise exception 'LOCKED';
  end if;

  return query
    select
      l.address_exact,
      -- Le numéro porté par l'annonce prime : un vendeur peut confier la
      -- visite à un tiers sans exposer sa ligne personnelle.
      coalesce(l.contact_phone, cd.phone),
      cd.whatsapp,
      (select m.storage_path from public.listing_media m
        where m.listing_id = l.id and m.kind = 'plan'
        order by m.sort_order limit 1),
      (select u.watermarked_path from public.listing_unlocks u
        where u.listing_id = l.id and u.buyer_id = auth.uid())
      from public.listings l
      left join public.contact_details cd on cd.profile_id = l.seller_id
     where l.id = p_listing;
end;
$$;

revoke all on function public.listing_is_unlocked(uuid) from public;
revoke all on function public.listing_private(uuid) from public;
grant execute on function public.listing_is_unlocked(uuid) to authenticated;
grant execute on function public.listing_private(uuid) to authenticated;

-- =====================================================================
-- LE DÉBLOCAGE
-- =====================================================================
create or replace function public.unlock_listing(
  p_listing uuid,
  p_ad_impression_id uuid default null)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_me     uuid := auth.uid();
  v_mode   text;
  v_seller uuid;
  v_status public.realty_status;
  v_id     uuid;
begin
  if v_me is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select seller_id, status into v_seller, v_status
    from public.listings where id = p_listing;

  if not found then
    raise exception 'LISTING_UNKNOWN';
  end if;
  if v_seller = v_me then
    raise exception 'LISTING_OWN';
  end if;
  if v_status <> 'publiee' then
    raise exception 'LISTING_CLOSED';
  end if;

  -- Déjà ouverte : on rend le déblocage existant sans rien consommer. Un
  -- double appui, une reconnexion, un retour en arrière ne doivent jamais
  -- coûter deux fois.
  select id into v_id from public.listing_unlocks
   where listing_id = p_listing and buyer_id = v_me;
  if found then
    return v_id;
  end if;

  -- `#>> '{}'` extrait la chaîne d'un jsonb sans ses guillemets. Un
  -- `::text` les garderait, et la comparaison avec 'gratuit' serait
  -- toujours fausse — le régime retomberait sur UNLOCK_MODE_UNKNOWN.
  v_mode := coalesce(
    public.app_setting('realty_unlock_mode', '"gratuit"'::jsonb) #>> '{}',
    'gratuit');

  if v_mode = 'gratuit' then
    insert into public.listing_unlocks (listing_id, buyer_id, granted_by)
    values (p_listing, v_me, 'free')
    returning id into v_id;

  elsif v_mode = 'video' then
    if p_ad_impression_id is null then
      raise exception 'AD_REQUIRED';
    end if;
    -- Même exigence que `grant_boost` : visionnage vérifié par le serveur
    -- de Google, et pas encore consommé. Sans quoi un APK modifié
    -- s'ouvrirait le catalogue entier.
    perform 1 from public.ad_impressions ai
      where ai.id = p_ad_impression_id
        and ai.profile_id = v_me
        and ai.ssv_verified
        and ai.placement_key = 'realty_unlock_rewarded'
        and ai.consumed_at is null;
    if not found then
      raise exception 'AD_NOT_VERIFIED';
    end if;

    insert into public.listing_unlocks (listing_id, buyer_id, granted_by,
                                        ad_impression_id)
    values (p_listing, v_me, 'ad', p_ad_impression_id)
    returning id into v_id;

    update public.ad_impressions set consumed_at = now()
     where id = p_ad_impression_id;

  elsif v_mode = 'payant' then
    -- Volontairement non branché. Le canal de paiement n'est pas choisi :
    -- vendre l'ouverture d'un contenu à l'intérieur de l'application relève
    -- de la facturation Google Play, et cet arbitrage n'est pas rendu. Une
    -- erreur claire vaut mieux qu'une porte entrouverte.
    raise exception 'PAYMENT_NOT_CONFIGURED';

  else
    raise exception 'UNLOCK_MODE_UNKNOWN';
  end if;

  update public.listings
     set unlocks_count = unlocks_count + 1
   where id = p_listing;

  return v_id;
end;
$$;

revoke all on function public.unlock_listing(uuid, uuid) from public;
grant execute on function public.unlock_listing(uuid, uuid) to authenticated;

comment on function public.unlock_listing(uuid, uuid) is
  'Ouvre une annonce pour l''appelant selon le régime en vigueur. '
  'Idempotente : un déblocage déjà acquis est rendu tel quel.';
