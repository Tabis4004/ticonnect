-- =====================================================================
-- 48_app_settings_anon_read.sql — Lisible avant la connexion
--
-- `AdsService.init()` s'exécute dans `main()`, avant tout écran de
-- connexion. À cet instant, le client Supabase est `anon`.
--
-- `ad_placements` était déjà lisible par `anon` — d'où des annonces qui se
-- chargeaient normalement. `app_settings` ne l'était pas :
-- `SettingsService.load()` rendait une liste vide, `setTestDevices([])`
-- sortait immédiatement sans rien faire, et l'appareil n'était jamais
-- enrôlé. Le SDK continuait donc d'écrire dans les journaux
-- « Use RequestConfiguration…setTestDeviceIds(…) » alors que l'identifiant
-- était correctement enregistré en base — deux vérités contradictoires qui
-- ont coûté une soirée.
--
-- Même cause, conséquence plus discrète, sur les placements : avant
-- connexion, `client_job_ad_placement` retombait sur sa valeur par défaut
-- au lieu de celle choisie dans l'administration.
--
-- La table ne contient que des paramètres d'exploitation — aucune donnée
-- personnelle, aucun secret. L'ouvrir en lecture à `anon` l'aligne sur
-- `ad_placements`, qui porte déjà les identifiants d'unités publicitaires.
-- L'écriture reste réservée aux administrateurs par
-- `app_settings_admin_write`.
-- =====================================================================

drop policy if exists app_settings_select_all on public.app_settings;
create policy app_settings_select_all on public.app_settings
  for select to authenticated, anon using (true);
