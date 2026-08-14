-- =====================================================================
-- 51_fix_job_country_data.sql — Missions étiquetées « CI » par défaut
--
-- `AppConfig.defaultCountry` était une constante figée à « CI », utilisée
-- à l'enregistrement des missions. Six demandes publiées depuis Lomé et
-- Porto-Novo étaient donc ivoiriennes en base — invisibles pour les
-- ouvriers de leur propre ville, et proposées à des ouvriers d'Abidjan.
--
-- On réaligne sur le pays du client. C'est une approximation, mais la
-- bonne : ces missions datent d'avant que le pays du chantier ne soit
-- saisissable, et la ville confirme dans chaque cas.
--
-- Appliquée sous le nom `fix_job_country_data` (20260806080126).
-- =====================================================================

update public.job_requests j
   set country_code = p.country_code, updated_at = now()
  from public.profiles p
 where p.id = j.client_id
   and j.country_code is distinct from p.country_code;
