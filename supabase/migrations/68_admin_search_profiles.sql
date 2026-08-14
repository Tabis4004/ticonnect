-- Recherche de comptes pour la nomination d'un administrateur.
--
-- L'écran demandait de taper un pseudo exact. C'est une impasse : le
-- superadmin ne connaît pas par cœur les pseudos, et rien dans
-- l'application ne lui donne la liste. Une faute de frappe rendait
-- « aucun compte ne porte ce pseudo » sans autre recours.
--
-- La fonction est réservée au superadmin et ne rend que ce que la
-- nomination exige : identifiant, pseudo, nom, et le rôle actuel s'il en a
-- un. Aucun numéro, aucune adresse.
create or replace function public.search_profiles_for_admin(
  p_query text default '',
  p_limit int default 30
)
returns table (
  id         uuid,
  username   text,
  full_name  text,
  role       text
) language sql stable security definer set search_path = '' as $$
  select p.id, p.username, p.full_name, a.role
    from public.profiles p
    left join public.admins a on a.profile_id = p.id
   where public.is_superadmin()
     and (
       btrim(coalesce(p_query, '')) = ''
       or p.username  ilike '%' || btrim(p_query) || '%'
       or p.full_name ilike '%' || btrim(p_query) || '%'
     )
   -- Les administrateurs en tête : c'est la liste qu'on vient consulter le
   -- plus souvent, et la retrouver noyée parmi tous les comptes annulerait
   -- l'intérêt de l'écran.
   order by (a.role is null), p.username
   limit least(greatest(coalesce(p_limit, 30), 1), 100);
$$;

revoke execute on function public.search_profiles_for_admin(text, int) from anon;
