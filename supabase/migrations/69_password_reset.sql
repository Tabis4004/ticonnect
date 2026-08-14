-- Réinitialisation d'un mot de passe par un administrateur.
--
-- Pourquoi ce détour plutôt qu'un « mot de passe oublié » ordinaire : les
-- comptes se connectent par pseudo, et l'adresse rattachée est fabriquée
-- (`pseudo@users.ticonnect.app`). Elle n'existe pas. Supabase ne peut donc
-- envoyer aucun lien de réinitialisation, et l'utilisateur qui oublie son
-- mot de passe n'a, aujourd'hui, aucune issue.
--
-- Ce que cette migration accorde, il faut le nommer sans détour : un
-- administrateur qui fixe le mot de passe d'un compte peut s'y connecter,
-- lire les conversations privées de cette personne, candidater ou publier
-- en son nom. Trois garde-fous, aucun décoratif :
--
--   1. Le compte est marqué. À sa connexion suivante, l'utilisateur DOIT
--      choisir un nouveau mot de passe : celui que l'administrateur
--      connaît cesse alors de fonctionner. Une prise de contrôle
--      silencieuse et durable devient impossible.
--   2. Chaque réinitialisation est journalisée, avec les deux identités.
--      Le journal n'empêche rien ; il rend les choses constatables.
--   3. Un modérateur ne peut pas réinitialiser le mot de passe d'un
--      administrateur. Sans cette règle, n'importe quel modérateur
--      prendrait le compte du superadministrateur et s'accorderait tout —
--      la hiérarchie des rôles ne vaudrait plus rien.
--
-- Le changement de mot de passe lui-même n'est pas ici : il exige la clé de
-- service, qui ne doit jamais quitter le serveur. Il vit dans l'Edge
-- Function `admin-reset-password`, qui appelle d'abord cette fonction pour
-- l'autorisation, et n'agit que si elle passe.

-- ---------------------------------------------------------------------------
-- Le marqueur.
--
-- Sur `profiles` plutôt que dans les métadonnées de `auth.users` : le reste
-- de l'application lit `profiles`, et une donnée qui décide de l'accès à
-- l'écran doit se lire là où on la cherchera.
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column if not exists must_change_password boolean not null default false;

comment on column public.profiles.must_change_password is
  'Mot de passe fixé par un administrateur. Tant que vrai, l''application '
  'n''affiche rien d''autre que le choix d''un nouveau mot de passe.';

-- La colonne ne doit pas être modifiable par son porteur : sinon il lui
-- suffirait de la remettre à faux pour garder le mot de passe temporaire —
-- celui que l'administrateur connaît. La migration `column_privileges` a
-- révoqué l'écriture générale sur `profiles` et ne rouvre que des colonnes
-- nommées ; il suffit donc de ne pas nommer celle-ci.

-- ---------------------------------------------------------------------------
-- Le journal.
-- ---------------------------------------------------------------------------
create table if not exists public.password_resets (
  id         uuid primary key default gen_random_uuid(),
  target_id  uuid not null references public.profiles(id) on delete cascade,
  by_id      uuid          references public.profiles(id) on delete set null,
  by_role    text,
  created_at timestamptz not null default now()
);

create index if not exists password_resets_target_idx
  on public.password_resets (target_id, created_at desc);

alter table public.password_resets enable row level security;

-- Lecture pour les administrateurs, écriture par personne : seule la
-- fonction ci-dessous écrit, et elle est `security definer`. Un journal que
-- son sujet peut effacer ne prouve rien.
drop policy if exists password_resets_admin_read on public.password_resets;
create policy password_resets_admin_read on public.password_resets
  for select using (public.is_admin());

-- ---------------------------------------------------------------------------
-- L'autorisation, et elle seule.
-- ---------------------------------------------------------------------------
create or replace function public.admin_prepare_password_reset(p_target uuid)
returns table (username text, full_name text)
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_me      uuid := auth.uid();
  v_my_role text;
begin
  if v_me is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  if not public.is_admin() then
    raise exception 'FORBIDDEN';
  end if;

  select a.role into v_my_role from public.admins a where a.profile_id = v_me;

  -- Se réinitialiser soi-même n'a pas de sens : on connaît son mot de passe
  -- puisqu'on est connecté. Le refuser évite surtout qu'un administrateur
  -- se marque par mégarde et se retrouve devant l'écran de changement forcé.
  if p_target = v_me then
    raise exception 'RESET_SELF';
  end if;

  if not exists (select 1 from public.profiles where id = p_target) then
    raise exception 'USER_UNKNOWN';
  end if;

  -- Le garde-fou qui compte.
  if exists (select 1 from public.admins where profile_id = p_target)
     and not public.is_superadmin() then
    raise exception 'RESET_ADMIN_FORBIDDEN';
  end if;

  update public.profiles
     set must_change_password = true
   where id = p_target;

  insert into public.password_resets (target_id, by_id, by_role)
  values (p_target, v_me, v_my_role);

  -- Rendu à l'appelant pour que le message de confirmation nomme la
  -- personne : « mot de passe de @awa réinitialisé » ne se confond pas avec
  -- la ligne d'à côté, un identifiant seul si.
  return query
    select p.username, p.full_name from public.profiles p where p.id = p_target;
end;
$$;

revoke all on function public.admin_prepare_password_reset(uuid) from public;
grant execute on function public.admin_prepare_password_reset(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Levée du marqueur, par l'intéressé lui-même.
--
-- Appelée après que l'utilisateur a effectivement changé son mot de passe
-- par `auth.updateUser`. Elle ne peut lever que son propre marqueur.
-- ---------------------------------------------------------------------------
create or replace function public.clear_must_change_password()
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  update public.profiles set must_change_password = false where id = auth.uid();
end;
$$;

revoke all on function public.clear_must_change_password() from public;
grant execute on function public.clear_must_change_password() to authenticated;

-- ---------------------------------------------------------------------------
-- Lecture du marqueur par l'intéressé.
--
-- Une fonction plutôt qu'une colonne lue directement : l'aiguillage du
-- démarrage a besoin de cette seule valeur, avant même que le profil
-- complet ne soit chargé.
-- ---------------------------------------------------------------------------
create or replace function public.password_change_required()
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select coalesce(
    (select must_change_password from public.profiles where id = auth.uid()),
    false);
$$;

revoke all on function public.password_change_required() from public;
grant execute on function public.password_change_required() to authenticated;

-- ---------------------------------------------------------------------------
-- La liste des comptes s'ouvre à tous les administrateurs.
--
-- Elle était réservée au superadministrateur, ce qui rendait la
-- réinitialisation inatteignable pour un modérateur — or c'est précisément
-- à lui qu'on veut confier le dépannage quand le superadministrateur est
-- indisponible. Le changement de NIVEAU reste, lui, superadministrateur :
-- `set_admin_role` et `revoke_admin` sont inchangées.
-- ---------------------------------------------------------------------------
create or replace function public.search_profiles_for_admin(
  p_query text default '', p_limit integer default 30)
returns table (id uuid, username text, full_name text, role text)
language sql
stable
security definer
set search_path to ''
as $$
  select p.id, p.username, p.full_name, a.role
    from public.profiles p
    left join public.admins a on a.profile_id = p.id
   where public.is_admin()
     and (
       btrim(coalesce(p_query, '')) = ''
       or p.username  ilike '%' || btrim(p_query) || '%'
       or p.full_name ilike '%' || btrim(p_query) || '%'
     )
   order by (a.role is null), p.username
   limit least(greatest(coalesce(p_limit, 30), 1), 100);
$$;
