-- =====================================================================
-- 30_column_privileges.sql — Fermeture de l'écriture sur les colonnes
--                            que l'utilisateur ne doit pas s'accorder
--
-- La RLS décide QUELLES LIGNES un utilisateur peut modifier, jamais
-- QUELLES COLONNES. `worker_update_self` et `profiles_update_self`
-- autorisent donc l'écriture de toute la ligne, y compris de champs qui
-- constituent le produit lui-même :
--
--   · worker_profiles.boosted_until — un appel PostgREST direct suffisait
--     à se placer en tête des résultats pour dix ans sans regarder la
--     moindre publicité. C'est la contrepartie du modèle publicitaire qui
--     disparaît.
--   · worker_profiles.rating_avg, rating_count, jobs_completed — la
--     réputation, c'est-à-dire le seul motif de confiance du client.
--   · worker_profiles.verification — le badge vérifié, qu'un compte
--     frauduleux pouvait s'attribuer.
--   · profiles.is_suspended — un compte banni se réactivait tout seul.
--
-- Postgres ne permet pas de retirer un sous-ensemble de colonnes d'un
-- droit accordé au niveau de la table : il faut révoquer le droit global
-- puis le réaccorder colonne par colonne. C'est ce que fait ce fichier.
--
-- Les triggers (sync_worker_rating, sync_jobs_completed, set_updated_at)
-- ne sont pas concernés : ils s'exécutent avec les droits de leur
-- propriétaire, pas ceux de l'appelant.
-- =====================================================================

-- =====================================================================
-- WORKER_PROFILES
-- =====================================================================
revoke insert, update on public.worker_profiles from authenticated;

-- Ce que l'ouvrier décrit lui-même : sa prestation et sa disponibilité.
-- id_document_* reste ouvert — l'ouvrier dépose sa pièce, c'est
-- l'administrateur qui accorde ou non le statut vérifié.
grant insert (
  profile_id, headline, years_experience, rate_min, rate_max,
  currency, pricing_unit, availability, is_listed,
  id_document_url, id_document_type
) on public.worker_profiles to authenticated;

grant update (
  headline, years_experience, rate_min, rate_max,
  currency, pricing_unit, availability, is_listed,
  id_document_url, id_document_type
) on public.worker_profiles to authenticated;

-- =====================================================================
-- PROFILES
-- =====================================================================
revoke insert, update on public.profiles from authenticated;

-- `role` reste modifiable : se déclarer ouvrier est un geste utilisateur
-- normal, et le rôle ne confère aucun privilège d'administration —
-- is_admin() lit la table `admins`, pas cette colonne.
--
-- `username` et `location` sont volontairement absents des deux listes,
-- et ce n'est pas un oubli : aucun écran ne les écrit directement.
-- `username` est posé à l'inscription par le trigger `handle_new_user`,
-- `location` par la fonction `set_my_location` — toutes deux en
-- `security definer`, donc insensibles aux droits accordés ici. Les
-- ajouter rouvrirait une écriture dont personne n'a besoin, et
-- `username` est l'identifiant de connexion.
--
-- Toute colonne ajoutée plus tard à `profiles` ou `worker_profiles` sera
-- fermée par défaut : c'est le bon sens de lecture, mais il faut penser
-- à revenir ici quand un nouvel écran doit en écrire une.
grant insert (
  id, full_name, role, avatar_url, bio,
  country_code, city, neighborhood, preferred_language
) on public.profiles to authenticated;

grant update (
  full_name, role, avatar_url, bio,
  country_code, city, neighborhood, preferred_language, last_seen_at
) on public.profiles to authenticated;

-- =====================================================================
-- ACTES D'ADMINISTRATION
--
-- Les droits colonne s'appliquent aussi aux administrateurs : eux non
-- plus n'écrivent plus directement `verification` ou `is_suspended`.
-- Ces deux fonctions leur rendent la main, avec une trace explicite de
-- qui décide quoi.
-- =====================================================================
create or replace function public.admin_set_verification(
  p_profile_id uuid,
  p_status     public.verification_status
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Réservé aux administrateurs' using errcode = '42501';
  end if;

  update public.worker_profiles
     set verification = p_status,
         verified_at  = case when p_status = 'verified' then now() else null end
   where profile_id = p_profile_id;
end;
$$;

create or replace function public.admin_set_suspended(
  p_profile_id uuid,
  p_suspended  boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Réservé aux administrateurs' using errcode = '42501';
  end if;

  -- Un administrateur ne se suspend pas lui-même par mégarde : ce serait
  -- irréversible depuis l'application.
  if p_profile_id = auth.uid() then
    raise exception 'Un administrateur ne peut pas se suspendre lui-même';
  end if;

  update public.profiles
     set is_suspended = p_suspended
   where id = p_profile_id;
end;
$$;

-- Le grant PUBLIC implicite sur toute nouvelle fonction rendrait ces
-- deux-là appelables par n'importe qui via /rest/v1/rpc/. Voir 09.
revoke execute on function public.admin_set_verification(uuid, public.verification_status) from public, anon;
revoke execute on function public.admin_set_suspended(uuid, boolean)                       from public, anon;
grant  execute on function public.admin_set_verification(uuid, public.verification_status) to authenticated;
grant  execute on function public.admin_set_suspended(uuid, boolean)                       to authenticated;

comment on function public.admin_set_verification(uuid, public.verification_status) is
  'Accorde ou retire le badge vérifié. La colonne n''est plus accessible en écriture directe.';
comment on function public.admin_set_suspended(uuid, boolean) is
  'Suspend ou réactive un compte. La colonne n''est plus accessible en écriture directe.';
