-- Trois niveaux d'administration au lieu d'un.
--
-- Jusqu'ici `admins` n'avait qu'un drapeau `is_super`, et toutes les
-- politiques RLS d'écriture s'appuyaient sur `is_admin()` — c'est-à-dire sur
-- la simple présence dans la table. Nommer quelqu'un pour traiter les
-- signalements lui donnait du même coup les tarifs d'abonnement, les
-- réglages publicitaires et le catalogue des métiers.
--
--   superadmin  tout, y compris réglages, tarifs, catalogue, nominations
--   moderateur  les contenus : signalements, profils, missions, avis
--   lecteur     rien d'autre que la lecture
--
-- `is_admin()` ne change pas : il reste vrai pour les trois rôles et
-- continue d'ouvrir la LECTURE partout. C'est ce qui définit le lecteur —
-- il voit tout, il n'écrit rien.

alter table public.admins add column if not exists role text;

-- Les comptes existants ne perdent aucun droit.
update public.admins
   set role = case when is_super then 'superadmin' else 'moderateur' end
 where role is null;

alter table public.admins alter column role set default 'moderateur';
alter table public.admins alter column role set not null;

alter table public.admins drop constraint if exists admins_role_check;
alter table public.admins add constraint admins_role_check
  check (role in ('superadmin', 'moderateur', 'lecteur'));

-- `is_super` reste alimenté pour ne rien casser d'existant, mais il n'est
-- plus la source de vérité : le trigger le recalcule depuis `role`.
create or replace function public.admins_sync_is_super()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  new.is_super := (new.role = 'superadmin');
  return new;
end;
$$;

drop trigger if exists admins_sync_is_super on public.admins;
create trigger admins_sync_is_super
  before insert or update on public.admins
  for each row execute function public.admins_sync_is_super();

update public.admins set role = role;  -- réaligne is_super via le trigger

create or replace function public.admin_role()
returns text language sql stable security definer set search_path = '' as $$
  select a.role from public.admins a where a.profile_id = auth.uid();
$$;

create or replace function public.can_moderate()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.admins a
     where a.profile_id = auth.uid()
       and a.role in ('superadmin', 'moderateur')
  );
$$;

create or replace function public.is_superadmin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.admins a
     where a.profile_id = auth.uid() and a.role = 'superadmin'
  );
$$;

-- ── Configuration : superadmin seul ──────────────────────────────────────
-- Les leviers qui touchent à l'argent et à la structure du catalogue. Un
-- modérateur recruté pour trier des signalements n'a aucune raison de
-- pouvoir changer le prix d'un abonnement au Nigeria.
--
-- La forme `( select f() )` fait évaluer la fonction une fois par requête
-- au lieu d'une fois par ligne.

drop policy if exists ad_placements_admin_write on public.ad_placements;
create policy ad_placements_admin_write on public.ad_placements
  for all to authenticated
  using ((select public.is_superadmin())) with check ((select public.is_superadmin()));

drop policy if exists app_settings_admin_write on public.app_settings;
create policy app_settings_admin_write on public.app_settings
  for all to authenticated
  using ((select public.is_superadmin())) with check ((select public.is_superadmin()));

drop policy if exists plan_prices_admin_write on public.plan_prices;
create policy plan_prices_admin_write on public.plan_prices
  for all to authenticated
  using ((select public.is_superadmin())) with check ((select public.is_superadmin()));

drop policy if exists onboarding_steps_admin on public.onboarding_steps;
create policy onboarding_steps_admin on public.onboarding_steps
  for all to authenticated
  using ((select public.is_superadmin())) with check ((select public.is_superadmin()));

drop policy if exists categories_admin_write on public.trade_categories;
create policy categories_admin_write on public.trade_categories
  for all to authenticated
  using ((select public.is_superadmin())) with check ((select public.is_superadmin()));

drop policy if exists trades_admin_write on public.trades;
create policy trades_admin_write on public.trades
  for all to authenticated
  using ((select public.is_superadmin())) with check ((select public.is_superadmin()));

-- ── Contenus : superadmin et modérateur ──────────────────────────────────

drop policy if exists banned_contacts_admin_all on public.banned_contacts;
create policy banned_contacts_admin_all on public.banned_contacts
  for all to authenticated
  using ((select public.can_moderate())) with check ((select public.can_moderate()));

drop policy if exists jobs_admin_all on public.job_requests;
create policy jobs_admin_all on public.job_requests
  for all to authenticated
  using ((select public.can_moderate())) with check ((select public.can_moderate()));

drop policy if exists profiles_admin_all on public.profiles;
create policy profiles_admin_all on public.profiles
  for all to authenticated
  using ((select public.can_moderate())) with check ((select public.can_moderate()));

drop policy if exists referrals_admin_all on public.referrals;
create policy referrals_admin_all on public.referrals
  for all to authenticated
  using ((select public.can_moderate())) with check ((select public.can_moderate()));

drop policy if exists reports_admin_write on public.reports;
create policy reports_admin_write on public.reports
  for all to authenticated
  using ((select public.can_moderate())) with check ((select public.can_moderate()));

drop policy if exists reviews_admin_all on public.reviews;
create policy reviews_admin_all on public.reviews
  for all to authenticated
  using ((select public.can_moderate())) with check ((select public.can_moderate()));

drop policy if exists worker_admin_all on public.worker_profiles;
create policy worker_admin_all on public.worker_profiles
  for all to authenticated
  using ((select public.can_moderate())) with check ((select public.can_moderate()));

-- ── La table des administrateurs elle-même ───────────────────────────────
-- Elle n'avait aucune politique d'écriture : nommer un administrateur
-- exigeait l'éditeur SQL de Supabase. Le superadmin peut désormais le faire
-- depuis l'application — et lui seul, sans quoi un modérateur se
-- promouvrait superadmin en une ligne.

drop policy if exists admins_super_write on public.admins;
create policy admins_super_write on public.admins
  for all to authenticated
  using ((select public.is_superadmin())) with check ((select public.is_superadmin()));

-- Se retirer soi-même le dernier superadmin verrouille définitivement les
-- réglages, les tarifs et la nomination : plus personne ne peut écrire, et
-- la seule issue serait l'éditeur SQL. Le refus est en base, pas dans
-- l'écran, pour qu'aucun chemin ne le contourne.
create or replace function public.admins_guard_last_super()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_restants int;
begin
  select count(*) into v_restants
    from public.admins a
   where a.role = 'superadmin' and a.profile_id <> old.profile_id;

  if tg_op = 'DELETE' then
    if old.role = 'superadmin' and v_restants = 0 then
      raise exception 'LAST_SUPERADMIN';
    end if;
    return old;
  end if;

  if old.role = 'superadmin' and new.role <> 'superadmin' and v_restants = 0 then
    raise exception 'LAST_SUPERADMIN';
  end if;
  return new;
end;
$$;

drop trigger if exists admins_guard_last_super on public.admins;
create trigger admins_guard_last_super
  before update or delete on public.admins
  for each row execute function public.admins_guard_last_super();

-- Nomination par pseudo : l'écran admin manipule des pseudos, jamais des
-- UUID, et faire recopier un identifiant technique serait une source
-- d'erreur pour un geste déjà sensible.
create or replace function public.set_admin_role(p_username text, p_role text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  if not public.is_superadmin() then
    raise exception 'FORBIDDEN';
  end if;
  if p_role not in ('superadmin', 'moderateur', 'lecteur') then
    raise exception 'ROLE_UNKNOWN';
  end if;

  select p.id into v_id
    from public.profiles p
   where lower(p.username) = lower(btrim(p_username));

  if v_id is null then
    raise exception 'USER_UNKNOWN';
  end if;

  insert into public.admins (profile_id, role)
  values (v_id, p_role)
  on conflict (profile_id) do update set role = excluded.role;
end;
$$;

create or replace function public.revoke_admin(p_username text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  if not public.is_superadmin() then
    raise exception 'FORBIDDEN';
  end if;

  select p.id into v_id
    from public.profiles p
   where lower(p.username) = lower(btrim(p_username));

  if v_id is null then
    raise exception 'USER_UNKNOWN';
  end if;

  delete from public.admins a where a.profile_id = v_id;
end;
$$;

-- Ouvert aux trois rôles : savoir qui détient quel droit fait partie de ce
-- qu'un lecteur doit pouvoir vérifier.
create or replace function public.list_admins()
returns table (
  profile_id uuid,
  username   text,
  full_name  text,
  role       text,
  created_at timestamptz
) language sql stable security definer set search_path = '' as $$
  select a.profile_id, p.username, p.full_name, a.role, a.created_at
    from public.admins a
    join public.profiles p on p.id = a.profile_id
   where public.is_admin()
   order by case a.role
              when 'superadmin' then 0
              when 'moderateur' then 1
              else 2
            end,
            p.username;
$$;

revoke execute on function public.set_admin_role(text, text) from anon;
revoke execute on function public.revoke_admin(text) from anon;
revoke execute on function public.list_admins() from anon;
