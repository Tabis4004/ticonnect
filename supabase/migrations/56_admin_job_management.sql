-- =====================================================================
-- 56_admin_job_management.sql — Gestion des demandes depuis l'admin
--
-- Trois besoins, trois niveaux de risque : créer une demande de test est
-- anodin, en supprimer une l'est presque, tout vider ne l'est pas. Le
-- niveau superadministrateur est introduit ici plutôt que de laisser un
-- geste irréversible derrière le même contrôle que la création d'un jeu
-- d'essai.
-- =====================================================================
alter table public.admins
  add column if not exists is_super boolean not null default false;

comment on column public.admins.is_super is
  'Autorise les gestes irréversibles : purge des demandes.';

update public.admins
   set is_super = true
 where profile_id = (select profile_id from public.admins order by profile_id limit 1)
   and not exists (select 1 from public.admins where is_super);

create or replace function public.is_superadmin()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.admins a
                  where a.profile_id = auth.uid() and a.is_super);
$$;

revoke execute on function public.is_superadmin() from public, anon;
grant  execute on function public.is_superadmin() to authenticated;

-- Le client déclaré n'est pas l'appelant : aucune politique RLS ne
-- l'autorise, et c'est justement l'intérêt — fabriquer une demande au nom
-- d'un compte de test sans se connecter avec.
create or replace function public.admin_create_job(
  p_client_id uuid default null, p_trade_id smallint default null,
  p_title text default 'Demande de test', p_city text default 'Abidjan')
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_client uuid; v_trade smallint; v_id uuid;
begin
  if not public.is_admin() then
    raise exception 'Réservé aux administrateurs' using errcode = '42501';
  end if;
  v_client := coalesce(p_client_id,
    (select id from public.profiles where not is_suspended order by created_at limit 1));
  v_trade := coalesce(p_trade_id,
    (select id from public.trades where is_active order by id limit 1));
  if v_client is null or v_trade is null then
    raise exception 'Aucun profil ou métier disponible pour créer la demande';
  end if;
  insert into public.job_requests
    (client_id, trade_id, title, description, city, country_code, status)
  values (v_client, v_trade, p_title,
    'Demande créée depuis le tableau de bord d''administration, à des fins de test.',
    p_city, 'CI', 'open')
  returning id into v_id;
  return v_id;
end;
$$;

revoke execute on function public.admin_create_job(uuid, smallint, text, text) from public, anon;
grant  execute on function public.admin_create_job(uuid, smallint, text, text) to authenticated;

create or replace function public.admin_delete_job(p_job_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Réservé aux administrateurs' using errcode = '42501';
  end if;
  delete from public.job_requests where id = p_job_id;
end;
$$;

revoke execute on function public.admin_delete_job(uuid) from public, anon;
grant  execute on function public.admin_delete_job(uuid) to authenticated;

-- `p_confirm` doit valoir exactement 'VIDER' : une purge accidentelle
-- effacerait tout l'historique, candidatures et conversations comprises.
create or replace function public.admin_purge_jobs(p_confirm text)
returns integer language plpgsql security definer set search_path = ''
as $$
declare v_n integer;
begin
  if not public.is_superadmin() then
    raise exception 'Réservé au superadministrateur' using errcode = '42501';
  end if;
  if p_confirm is distinct from 'VIDER' then
    raise exception 'Confirmation manquante';
  end if;
  select count(*) into v_n from public.job_requests;
  delete from public.job_requests;
  return v_n;
end;
$$;

revoke execute on function public.admin_purge_jobs(text) from public, anon;
grant  execute on function public.admin_purge_jobs(text) to authenticated;
