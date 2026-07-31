-- =====================================================================
-- 12_ad_compliance.sql — Conformité AdMob et pilotage des placements
--
-- Contexte : le besoin exprimé était « rendre le visionnage obligatoire
-- avant la mise en relation ». Tel quel, appliqué au format `rewarded`,
-- cela déclenche la violation « Disallowed Rewarded Implementation » —
-- AdMob impose un opt-in affirmatif, publicité par publicité — et expose
-- le compte à une suspension.
--
-- Cette migration ouvre les deux voies qui atteignent le même objectif
-- sans enfreindre la règle :
--
--   1. `interstitial`      — peut être imposé, sans skip, à un point de
--                            transition entre deux écrans.
--   2. `rewarded_interstitial` — s'affiche automatiquement en transition,
--                            sans opt-in, à condition de présenter un
--                            écran d'introduction annonçant la récompense
--                            et proposant de passer.
--
-- Le format `rewarded` classique reste réservé aux endroits où il est
-- déjà conforme : le portefeuille et le boost de profil, où l'utilisateur
-- appuie lui-même sur un bouton.
-- =====================================================================

-- =====================================================================
-- RÉGLAGES APPLICATIFS PILOTÉS À DISTANCE
--
-- Même logique que `ad_placements` : ce qui doit pouvoir être arbitré
-- après le lancement, sur des chiffres réels, ne doit pas exiger une
-- republication sur le Play Store.
-- =====================================================================
create table if not exists public.app_settings (
  key         text primary key,
  value       jsonb not null,
  description text,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references public.profiles(id) on delete set null
);

comment on table public.app_settings is
  'Réglages modifiables par un administrateur sans republier l''application.';

drop trigger if exists app_settings_set_updated_at on public.app_settings;
create trigger app_settings_set_updated_at
  before update on public.app_settings
  for each row execute function public.set_updated_at();

alter table public.app_settings enable row level security;

-- Lecture ouverte : l'application a besoin de ces valeurs au démarrage.
-- Aucune donnée personnelle n'y transite.
drop policy if exists app_settings_select_all on public.app_settings;
create policy app_settings_select_all on public.app_settings
  for select to authenticated using (true);

drop policy if exists app_settings_admin_write on public.app_settings;
create policy app_settings_admin_write on public.app_settings
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Accesseur avec valeur de repli : une clé absente ne doit jamais casser
-- une requête, sinon le premier oubli de seed fait tomber la recherche.
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

grant execute on function public.app_setting(text, jsonb) to authenticated;

-- =====================================================================
-- ÉCRAN D'INTRODUCTION DES PUBLICITÉS RÉCOMPENSÉES
--
-- Le SDK gère la publicité elle-même ; l'écran qui l'annonce est à notre
-- charge. AdMob exige qu'il indique clairement la récompense et laisse
-- une porte de sortie — c'est cette porte de sortie qui rend le format
-- « automatique » légal.
-- =====================================================================
alter table public.ad_placements
  add column if not exists intro_title  text,
  add column if not exists intro_body   text,
  add column if not exists intro_cta    text,
  add column if not exists skip_label   text;

comment on column public.ad_placements.intro_title is
  'Titre de l''écran d''introduction (formats rewarded et rewarded_interstitial).';
comment on column public.ad_placements.skip_label is
  'Libellé du bouton permettant de passer. Obligatoire pour rewarded_interstitial : '
  'sans porte de sortie visible, le placement redevient une violation.';

-- =====================================================================
-- NOUVEAUX EMPLACEMENTS
--
-- Côté ouvrier : la charge publicitaire principale. C'est là que la
-- valeur est reçue, et le volume croît avec l'activité réelle de la
-- marketplace plutôt qu'avec le seul nombre d'inscrits.
--
-- Côté client : les deux emplacements demandés sont créés, mais un seul
-- s'active à la fois — voir la clé `client_job_ad_placement` plus bas.
-- =====================================================================
insert into public.ad_placements
  (key, format, ad_unit_android, is_enabled, reward_credits,
   daily_cap_per_user, min_seconds_between, description,
   intro_title, intro_body, intro_cta, skip_label)
values
  ('apply_rewarded_interstitial', 'rewarded_interstitial',
    'ca-app-pub-3940256099942544/5354046379',
    true, 0, 6, 90,
    'Ouvrier, juste avant l''envoi de la candidature. Format automatique mais '
    'précédé d''un écran annonçant la récompense et proposant de passer.',
    'Une pub avant d''envoyer',
    'Regarde une courte vidéo : elle finance l''application et permet de garder '
    'les candidatures gratuites pour tout le monde.',
    'Regarder la vidéo',
    'Envoyer sans regarder'),

  ('job_post_before_interstitial', 'interstitial',
    'ca-app-pub-3940256099942544/1033173712',
    false, 0, 3, 300,
    'Client, AVANT la saisie du besoin. Désactivé par défaut : la friction '
    'tombe au moment où le client est le moins engagé. Activable via '
    'app_settings.client_job_ad_placement = "before".',
    null, null, null, null),

  ('job_post_after_interstitial', 'interstitial',
    'ca-app-pub-3940256099942544/1033173712',
    true, 0, 3, 300,
    'Client, APRÈS validation du besoin, sur l''écran de confirmation. '
    'Même inventaire publicitaire, mais l''engagement est acquis.',
    null, null, null, null),

  ('unlock_rewarded_interstitial', 'rewarded_interstitial',
    'ca-app-pub-3940256099942544/5354046379',
    false, 1, 8, 60,
    'Variante automatique du déverrouillage de contact, pour le jour où '
    'unlock_cost repasse au-dessus de zéro. Désactivé tant que le contact '
    'est gratuit.',
    'Débloquer ce contact',
    'Regarde une courte vidéo pour obtenir un crédit et accéder au numéro.',
    'Regarder la vidéo',
    'Plus tard')
on conflict (key) do nothing;

-- L'emplacement historique reste en opt-in strict : il est déclenché par
-- un bouton du portefeuille, ce qui est conforme. On documente seulement.
update public.ad_placements
   set intro_title = coalesce(intro_title, 'Gagner un crédit'),
       intro_body  = coalesce(intro_body,
         'Regarde une courte vidéo jusqu''au bout pour gagner un crédit.'),
       intro_cta   = coalesce(intro_cta, 'Regarder la vidéo'),
       skip_label  = coalesce(skip_label, 'Annuler')
 where key in ('unlock_contact_rewarded', 'boost_profile_rewarded');

-- =====================================================================
-- RÉGLAGES PAR DÉFAUT
-- =====================================================================
insert into public.app_settings (key, value, description) values
  ('client_job_ad_placement', '"after"'::jsonb,
    'Où afficher l''interstitiel côté client : "before" (avant la saisie du '
    'besoin), "after" (après validation, recommandé) ou "off". Bascule '
    'réversible depuis le tableau de bord admin, sans republier.'),

  ('worker_apply_ad_enabled', 'true'::jsonb,
    'Publicité récompensée automatique avant l''envoi d''une candidature.'),

  ('sponsored_slot_ratio', '4'::jsonb,
    'Au maximum un résultat sponsorisé toutes les N positions de recherche. '
    'Un classement intégralement payant détruirait la confiance dans la '
    'recherche, donc le produit lui-même.'),

  ('sponsored_min_rating', '3.5'::jsonb,
    'Note minimale pour qu''un profil sponsorisé occupe une position mise en '
    'avant. En dessous, il retombe dans le classement organique.'),

  ('ad_min_seconds_between_any', '45'::jsonb,
    'Délai minimum entre deux interstitiels, quel que soit l''emplacement. '
    'Garde-fou global : AdMob sanctionne l''affichage à chaque action.')
on conflict (key) do nothing;
