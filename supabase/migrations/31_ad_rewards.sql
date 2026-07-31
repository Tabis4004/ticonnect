-- =====================================================================
-- 31_ad_rewards.sql — Récompenses publicitaires vérifiées et boost de
--                     profil gagné par visionnage
--
-- L'Edge Function `admob-ssv` sait désormais attester qu'une publicité a
-- été vue : elle vérifie la signature de Google et pose `ssv_verified`.
-- Mais rien ne transforme encore cette attestation en mise en avant —
-- `boost_profile_rewarded` existe en base, son écran d'introduction est
-- rédigé, le classement de `15_premium_search` puis `19_sponsored_priority` sait l'exploiter, et
-- `AdKeys.boostRewarded` n'est appelé nulle part.
--
-- Ce fichier ferme la chaîne : `grant_boost` échange une impression
-- vérifiée contre une durée de mise en avant.
--
-- Le téléphone n'accorde jamais rien, il demande. Un client modifié peut
-- appeler cette fonction autant qu'il veut : sans impression signée par
-- Google, il n'obtiendra rien.
-- =====================================================================

-- =====================================================================
-- DÉPENDANCE : RÉGLAGES APPLICATIFS
--
-- `app_settings` et `app_setting()` sont définis par `ad_compliance`.
-- Cette migration-là n'était pas appliquée sur la base au moment d'écrire
-- ces lignes — le dépôt local et la base ont divergé — et `grant_boost`
-- ne peut pas s'en passer.
--
-- Tout est donc recréé ici sous garde : `if not exists` et `or replace`,
-- avec exactement les mêmes définitions. Appliquer `ad_compliance` avant
-- ou après ne change rien, l'un des deux sera un non-événement.
-- =====================================================================
create table if not exists public.app_settings (
  key         text primary key,
  value       jsonb not null,
  description text,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references public.profiles(id) on delete set null
);

drop trigger if exists app_settings_set_updated_at on public.app_settings;
create trigger app_settings_set_updated_at
  before update on public.app_settings
  for each row execute function public.set_updated_at();

alter table public.app_settings enable row level security;

drop policy if exists app_settings_select_all on public.app_settings;
create policy app_settings_select_all on public.app_settings
  for select to authenticated using (true);

drop policy if exists app_settings_admin_write on public.app_settings;
create policy app_settings_admin_write on public.app_settings
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Une clé absente ne doit jamais casser une requête : le premier oubli de
-- seed ferait tomber la recherche.
create or replace function public.app_setting(p_key text, p_default jsonb)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select s.value from public.app_settings s where s.key = p_key),
    p_default
  );
$$;

revoke execute on function public.app_setting(text, jsonb) from public, anon;
grant  execute on function public.app_setting(text, jsonb) to authenticated;

-- =====================================================================
-- CONSOMMATION D'UNE IMPRESSION
--
-- Une impression vérifiée ne doit financer qu'une seule récompense.
-- `credit_transactions` ne peut pas servir de registre ici : sa
-- contrainte `amount <> 0` interdit d'y inscrire un mouvement nul, et le
-- boost ne coûte aucun crédit. D'où cette colonne, qui rend la
-- consommation lisible sur l'impression elle-même.
-- =====================================================================
alter table public.ad_impressions
  add column if not exists consumed_at timestamptz;

comment on column public.ad_impressions.consumed_at is
  'Date à laquelle cette impression a été échangée contre une récompense '
  '(mise en avant). Non nulle = déjà utilisée, le rejeu est refusé.';

create index if not exists ad_impressions_unconsumed_idx
  on public.ad_impressions (profile_id)
  where ssv_verified and consumed_at is null;

-- =====================================================================
-- RÉGLAGES DU BOOST
-- =====================================================================
insert into public.app_settings (key, value, description) values
  ('boost_duration_hours', '6'::jsonb,
   'Durée de mise en avant accordée par vidéo regardée.'),

  ('boost_max_hours', '24'::jsonb,
   'Plafond de mise en avant cumulable. Sans plafond, un ouvrier très '
   'assidu accumulerait des semaines d''avance et occuperait les créneaux '
   'sponsorisés en permanence, au détriment des autres et de la '
   'pertinence du classement.')
on conflict (key) do nothing;

-- =====================================================================
-- EMPLACEMENT CÔTÉ CLIENT
--
-- Le parcours du demandeur ne portera jamais le revenu : il ouvre
-- l'application quand il a un besoin, pas tous les jours. Mais la fiche
-- d'un ouvrier est le seul écran où il s'attarde — il compare, il lit les
-- avis. Une bannière en bas de page y a un volume réel, sans recouvrir
-- aucune action ni peser sur la décision de contacter.
-- =====================================================================
insert into public.ad_placements
  (key, format, ad_unit_android, is_enabled, reward_credits,
   daily_cap_per_user, min_seconds_between, description)
values
  ('worker_detail_banner', 'banner', 'ca-app-pub-3940256099942544/6300978111',
   true, 0, null, 0,
   'Client, bas de la fiche ouvrier. eCPM faible mais c''est le seul écran '
   'où le demandeur passe du temps.')
on conflict (key) do nothing;

-- L'emplacement `app_open` reste désactivé, comme au premier jour : c'est
-- le format le plus rentable sur des sessions rares, et le plus intrusif.
-- Le code sait maintenant l'afficher (jamais au premier lancement, comme
-- l'exige AdMob) ; l'activer se décide sur des chiffres réels, depuis
-- `ad_placements.is_enabled`, sans republier.

-- =====================================================================
-- BOOST DE PROFIL CONTRE VISIONNAGE
--
-- L'ouvrier appelle cette fonction avec l'identifiant de l'impression
-- que lui a rendu AdsService.showRewarded(). Tous les contrôles portent
-- sur des données que le client ne peut pas fabriquer.
-- =====================================================================
create or replace function public.grant_boost(p_ad_impression_id uuid)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me       uuid := auth.uid();
  v_hours    numeric;
  v_max      numeric;
  v_current  timestamptz;
  v_new      timestamptz;
begin
  if v_me is null then
    raise exception 'Authentification requise';
  end if;

  -- L'impression doit exister, appartenir à l'appelant, avoir été
  -- vérifiée par Google, provenir d'un emplacement de boost, et n'avoir
  -- jamais servi. Le tout en une seule condition : impossible d'en
  -- satisfaire une partie seulement.
  perform 1
     from public.ad_impressions ai
     join public.ad_placements  pl on pl.key = ai.placement_key
    where ai.id = p_ad_impression_id
      and ai.profile_id = v_me
      and ai.ssv_verified
      and pl.key = 'boost_profile_rewarded'
      and ai.consumed_at is null;

  if not found then
    raise exception 'Visionnage non vérifié ou déjà utilisé'
      using errcode = 'P0001';
  end if;

  select coalesce((public.app_setting('boost_duration_hours', '6'::jsonb))::text::numeric, 6)
    into v_hours;
  select coalesce((public.app_setting('boost_max_hours', '24'::jsonb))::text::numeric, 24)
    into v_max;

  select boosted_until into v_current
    from public.worker_profiles
   where profile_id = v_me
   for update;

  if not found then
    raise exception 'Profil ouvrier introuvable : complète ton profil avant de te mettre en avant';
  end if;

  -- Les visionnages s'additionnent au lieu de se remplacer — sinon
  -- regarder une seconde vidéo pendant qu'un boost court le raccourcit,
  -- ce que l'ouvrier vivrait comme une tromperie. Le cumul reste borné.
  v_new := greatest(coalesce(v_current, now()), now()) + make_interval(hours => v_hours::int);
  v_new := least(v_new, now() + make_interval(hours => v_max::int));

  update public.worker_profiles
     set boosted_until = v_new
   where profile_id = v_me;

  -- L'impression est brûlée : elle ne pourra plus être échangée.
  update public.ad_impressions
     set consumed_at = now()
   where id = p_ad_impression_id;

  return v_new;
end;
$$;

revoke execute on function public.grant_boost(uuid) from public, anon;
grant  execute on function public.grant_boost(uuid) to authenticated;

comment on function public.grant_boost(uuid) is
  'Transforme une impression publicitaire vérifiée en mise en avant. '
  'Renvoie la nouvelle date de fin de boost.';
