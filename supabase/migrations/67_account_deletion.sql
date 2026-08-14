-- Suppression de compte à la demande de l'utilisateur.
--
-- Exigence Google Play applicable depuis le 15 avril 2026 : toute
-- application permettant de créer un compte doit permettre d'en demander la
-- suppression depuis l'application ET depuis une page web accessible sans
-- connexion. La page web est `web/suppression-compte.html` ; ce fichier
-- fournit la moitié applicative.
--
-- Le problème que résout ce code n'est pas de supprimer — toutes les clés
-- étrangères vers `profiles` sont en ON DELETE CASCADE, un simple
-- `delete from auth.users` effacerait tout. C'est qu'il effacerait TROP :
-- les conversations disparaîtraient aussi du côté de l'interlocuteur, qui
-- n'a rien demandé, et avec elles la seule trace d'une mission en cas de
-- litige. Un client mécontent pourrait effacer les preuves en fermant son
-- compte.
--
-- On rattache donc l'historique partagé — conversations, messages, demandes,
-- avis — à un profil anonyme créé pour l'occasion, avant de supprimer le
-- compte réel. L'interlocuteur garde son fil, désormais face à
-- « Compte supprimé ». Rien de la personne ne subsiste : ni nom, ni pseudo,
-- ni numéro, ni position.
--
-- Un profil anonyme par suppression, et non un profil unique partagé :
-- `conversations_unique_idx` porte sur (client_id, worker_id, job_id) et
-- `reviews_job_id_reviewer_id_key` sur (job_id, reviewer_id). Deux comptes
-- supprimés ayant écrit au même ouvrier, ou noté la même mission, entreraient
-- en collision sur un profil commun — et la suppression échouerait, pour le
-- second seulement, des mois plus tard.

-- ---------------------------------------------------------------------------
-- Journal des suppressions.
--
-- Aucune donnée personnelle : seulement le fait qu'un compte a été supprimé,
-- et quel profil anonyme porte désormais son historique. Sert à répondre à
-- « qu'est devenu ce compte ? » sans conserver qui il était.
-- ---------------------------------------------------------------------------
create table if not exists public.account_deletions (
  id           uuid primary key default gen_random_uuid(),
  tombstone_id uuid not null,
  role         text,
  country_code text,
  account_age_days int,
  deleted_at   timestamptz not null default now()
);

alter table public.account_deletions enable row level security;

drop policy if exists account_deletions_admin_read on public.account_deletions;
create policy account_deletions_admin_read on public.account_deletions
  for select using (public.is_admin());

-- ---------------------------------------------------------------------------
-- delete_my_account()
--
-- Rend l'identifiant du profil anonyme. `security definer` : l'utilisateur
-- n'a par construction aucun droit sur `auth.users`, et ne doit pas en avoir.
-- ---------------------------------------------------------------------------
create or replace function public.delete_my_account()
returns uuid
language plpgsql
security definer
set search_path to 'public', 'auth', 'extensions'
as $$
declare
  v_uid     uuid := auth.uid();
  v_tomb    uuid := gen_random_uuid();
  v_country text;
  v_role    text;
  v_age     int;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select country_code, role::text, greatest(0, (now()::date - created_at::date))
    into v_country, v_role, v_age
    from public.profiles where id = v_uid;

  if not found then
    raise exception 'PROFILE_NOT_FOUND';
  end if;

  -- Le dernier superadministrateur ne peut pas se supprimer : plus personne
  -- ne pourrait nommer d'administrateur, ni modifier un réglage, sans passer
  -- par l'éditeur SQL de Supabase. Même garde-fou que `admin_set_role`.
  if exists (select 1 from public.admins where profile_id = v_uid and is_super)
     and (select count(*) from public.admins where is_super) <= 1 then
    raise exception 'LAST_SUPERADMIN';
  end if;

  -- Le profil anonyme. L'insertion dans `auth.users` déclenche
  -- `handle_new_user`, qui crée la ligne `profiles` correspondante ; on la
  -- reprend ensuite pour la marquer suspendue — personne ne doit tomber
  -- dessus dans l'annuaire ni pouvoir lui écrire.
  insert into auth.users (
    instance_id, id, aud, role, email,
    encrypted_password, email_confirmed_at,
    created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data
  ) values (
    '00000000-0000-0000-0000-000000000000', v_tomb, 'authenticated', 'authenticated',
    -- Adresse inutilisable : le domaine .invalid est réservé par la RFC 2606
    -- et ne peut pas exister. Aucune connexion n'est possible, il n'y a pas
    -- de mot de passe.
    'supprime-' || replace(v_tomb::text, '-', '') || '@ticonnect.invalid',
    null, now(), now(), now(),
    '{"provider":"deleted","providers":["deleted"]}'::jsonb,
    jsonb_build_object(
      'full_name', 'Compte supprimé',
      'role', coalesce(v_role, 'client'),
      'country_code', coalesce(v_country, 'CI'))
  );

  update public.profiles
     set is_suspended = true,
         username = null,
         bio = null,
         city = null,
         neighborhood = null,
         avatar_url = null
   where id = v_tomb;

  -- Historique partagé : ce qui appartient autant à l'autre partie qu'à
  -- l'utilisateur qui s'en va.
  update public.conversations set client_id = v_tomb where client_id = v_uid;
  update public.conversations set worker_id = v_tomb where worker_id = v_uid;
  update public.messages      set sender_id = v_tomb where sender_id = v_uid;
  update public.job_requests  set client_id = v_tomb where client_id = v_uid;
  update public.reviews       set reviewer_id = v_tomb where reviewer_id = v_uid;
  update public.reviews       set reviewee_id = v_tomb where reviewee_id = v_uid;

  -- `banned_contacts.profile_id` est en SET NULL : le numéro d'un compte
  -- suspendu reste bloqué après la suppression. C'est voulu — sinon la
  -- suppression de compte deviendrait le moyen le plus simple de contourner
  -- une suspension.

  insert into public.account_deletions (tombstone_id, role, country_code, account_age_days)
  values (v_tomb, v_role, v_country, v_age);

  -- Tout le reste part en cascade : profil, coordonnées, fiche ouvrier,
  -- métiers, zones, portfolio, candidatures, favoris, notifications,
  -- appareils, parrainages, signalements, portefeuille, impressions.
  delete from auth.users where id = v_uid;

  return v_tomb;
end;
$$;

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;

comment on function public.delete_my_account() is
  'Supprime le compte de l''appelant. L''historique partagé est réattribué à '
  'un profil anonyme. Exigence Google Play du 15 avril 2026.';
