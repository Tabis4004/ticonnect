-- =====================================================================
-- 16_progressive_identity.sql — Identité progressive et anti-fraude
--
-- L'inscription se fait désormais par pseudo et mot de passe. C'est le
-- bon choix pour la croissance : chaque champ supplémentaire à
-- l'inscription coûte des utilisateurs, et le SMS coûtait en plus de
-- l'argent à chaque tentative.
--
-- Mais sur une plateforme où la confiance EST le produit, une inscription
-- anonyme ouvre la porte aux faux profils, aux avis complaisants et au
-- retour immédiat d'un compte banni. Et `contact_details.phone` est en
-- `not null` : le numéro doit bien être collecté quelque part.
--
-- D'où l'identité progressive : rien à l'inscription, le numéro exigé au
-- premier acte qui engage — publier un besoin, ou se déclarer ouvrier.
-- L'utilisateur a alors compris ce que l'application lui apporte, et le
-- taux de complétion n'a plus rien à voir avec celui d'un formulaire
-- d'inscription.
-- =====================================================================

-- =====================================================================
-- UNICITÉ DU NUMÉRO
--
-- Sans elle, un compte suspendu se recrée en trois minutes et le
-- bannissement ne veut plus rien dire.
-- =====================================================================
do $$
declare
  v_dupes integer;
begin
  select count(*) into v_dupes
    from (select phone from public.contact_details
           group by phone having count(*) > 1) d;

  if v_dupes > 0 then
    raise exception
      'Migration interrompue : % numéro(s) apparaissent sur plusieurs '
      'profils dans contact_details. Fusionne ou corrige ces comptes '
      'avant de rejouer cette migration — créer l''index masquerait le '
      'problème au lieu de le traiter.', v_dupes;
  end if;
end
$$;

create unique index if not exists contact_details_phone_key
  on public.contact_details (phone);

-- =====================================================================
-- NUMÉROS BANNIS
-- =====================================================================
create table if not exists public.banned_contacts (
  phone      text primary key,
  profile_id uuid references public.profiles(id) on delete set null,
  reason     text,
  created_at timestamptz not null default now()
);

comment on table public.banned_contacts is
  'Numéros rattachés à un compte suspendu. Empêche la réinscription '
  'immédiate sous un nouveau pseudo.';

alter table public.banned_contacts enable row level security;

-- Aucune politique de lecture pour les utilisateurs : la liste des
-- numéros bannis n'a pas à être consultable. Les vérifications passent
-- par des fonctions `security definer`.
drop policy if exists banned_contacts_admin_all on public.banned_contacts;
create policy banned_contacts_admin_all on public.banned_contacts
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Un compte suspendu verse son numéro à la liste.
create or replace function public.ban_contact_on_suspend()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.is_suspended and not coalesce(old.is_suspended, false) then
    insert into public.banned_contacts (phone, profile_id, reason)
    select cd.phone, new.id, 'Compte suspendu'
      from public.contact_details cd
     where cd.profile_id = new.id
    on conflict (phone) do nothing;

  elsif coalesce(old.is_suspended, false) and not new.is_suspended then
    -- Réhabilitation : on lève le bannissement, sinon la levée de
    -- suspension serait sans effet réel.
    delete from public.banned_contacts where profile_id = new.id;
  end if;

  return new;
end;
$$;

drop trigger if exists profiles_ban_contact on public.profiles;
create trigger profiles_ban_contact
  after update of is_suspended on public.profiles
  for each row execute function public.ban_contact_on_suspend();

-- Refus d'enregistrer un numéro banni.
create or replace function public.reject_banned_contact()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from public.banned_contacts b where b.phone = new.phone) then
    raise exception 'PHONE_BANNED'
      using hint = 'Ce numéro est rattaché à un compte suspendu.';
  end if;
  return new;
end;
$$;

drop trigger if exists contact_details_reject_banned on public.contact_details;
create trigger contact_details_reject_banned
  before insert or update of phone on public.contact_details
  for each row execute function public.reject_banned_contact();

-- =====================================================================
-- LE NUMÉRO EXIGÉ AU PREMIER ACTE ENGAGEANT
--
-- Le nom de la colonne portant le propriétaire varie d'une table à
-- l'autre : il est passé en argument du trigger plutôt que dupliqué en
-- deux fonctions presque identiques.
-- =====================================================================
create or replace function public.require_phone_before_engaging()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid;
begin
  v_owner := (to_jsonb(new) ->> tg_argv[0])::uuid;

  if v_owner is null then
    return new;
  end if;

  if exists (select 1 from public.profiles p
              where p.id = v_owner and p.is_suspended) then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;

  if not exists (select 1 from public.contact_details cd
                  where cd.profile_id = v_owner
                    and length(coalesce(cd.phone, '')) >= 6) then
    raise exception 'PHONE_REQUIRED'
      using hint = 'Renseigne ton numéro dans Mon compte avant de continuer.';
  end if;

  return new;
end;
$$;

drop trigger if exists job_requests_require_phone on public.job_requests;
create trigger job_requests_require_phone
  before insert on public.job_requests
  for each row execute function public.require_phone_before_engaging('client_id');

drop trigger if exists worker_profiles_require_phone on public.worker_profiles;
create trigger worker_profiles_require_phone
  before insert on public.worker_profiles
  for each row execute function public.require_phone_before_engaging('profile_id');

-- =====================================================================
-- ÉTAT DE COMPLÉTION, POUR QUE L'APPLICATION DEMANDE AU BON MOMENT
--
-- Sans cette fonction, l'application ne peut savoir qu'un numéro manque
-- qu'en tentant l'insertion et en récupérant l'erreur — c'est-à-dire
-- après que l'utilisateur a rempli tout le formulaire.
-- =====================================================================
create or replace function public.has_phone()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.contact_details cd
     where cd.profile_id = auth.uid()
       and length(coalesce(cd.phone, '')) >= 6
  );
$$;

grant execute on function public.has_phone() to authenticated;
