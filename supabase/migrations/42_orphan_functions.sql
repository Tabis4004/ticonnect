-- =====================================================================
-- 42_orphan_functions.sql — Fonctions appliquées en base mais jamais
--                           versionnées
--
-- `username_available`, `set_my_location` et `get_my_location` étaient
-- appelées par l'application sans exister nulle part dans ce dépôt. Elles
-- venaient de trois migrations passées directement sur `Ticonnect 1.0` —
-- `12_username_auth_and_worker_dispatch`, `13_user_location_and_email` et
-- `14_trades_english_names` — dont les fichiers n'ont jamais été écrits.
--
-- Rejouer le schéma sur un nouvel environnement aurait donc produit une
-- application cassée à la connexion : `username_available` est appelée dès
-- l'écran d'inscription.
--
-- Les définitions ci-dessous sont extraites telles quelles via
-- `pg_get_functiondef()`, sans réécriture. Ce fichier ne modifie donc rien
-- sur la base actuelle ; il existe pour que le dépôt cesse de mentir sur
-- ce que contient le schéma.
--
-- Note : les autres objets de ces trois migrations (colonnes, seeds de
-- métiers en anglais, dispatch ouvrier) restent non versionnés. La même
-- requête, sans filtre sur `proname`, révélerait le reste de la dérive.
-- =====================================================================

create or replace function public.username_available(p_username text)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select not exists (
    select 1 from public.profiles p
     where lower(p.username) = lower(trim(p_username))
  );
$function$;

create or replace function public.set_my_location(
  p_lat double precision,
  p_lon double precision
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if auth.uid() is null then
    raise exception 'Authentification requise';
  end if;

  if p_lat is null or p_lon is null then
    update public.profiles set location = null where id = auth.uid();
    return;
  end if;

  if p_lat < -90 or p_lat > 90 or p_lon < -180 or p_lon > 180 then
    raise exception 'Coordonnees hors bornes';
  end if;

  update public.profiles
     set location = extensions.st_setsrid(
                      extensions.st_makepoint(p_lon, p_lat), 4326
                    )::extensions.geography
   where id = auth.uid();
end;
$function$;

create or replace function public.get_my_location()
returns table(lat double precision, lon double precision)
language sql
stable
security definer
set search_path to ''
as $function$
  select extensions.st_y(p.location::extensions.geometry),
         extensions.st_x(p.location::extensions.geometry)
    from public.profiles p
   where p.id = auth.uid() and p.location is not null;
$function$;
