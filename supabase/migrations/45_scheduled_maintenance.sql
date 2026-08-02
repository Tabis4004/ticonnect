-- =====================================================================
-- 45_scheduled_maintenance.sql — Tâches planifiées
--
-- Trois fonctions de maintenance existaient sans que rien ne les appelle :
-- `expire_stale_jobs()` depuis la migration 05, `expire_subscriptions()`
-- et `refresh_response_stats()` depuis les récentes. Écrites, jamais
-- exécutées. `pg_cron` n'était même pas installé.
--
-- Le recalcul de réactivité ne peut pas se contenter du trigger sur les
-- messages : une conversation qui franchit la fenêtre de maturité sans
-- réponse change le dénominateur alors qu'aucun message n'a été envoyé.
-- Sans passage périodique, un silence ne serait jamais compté — et le taux
-- de réponse resterait bloqué à 100 % pour tout le monde.
--
-- L'heure décalée (17e minute) évite de tomber sur la même seconde que les
-- autres tâches planifiées du projet.
-- =====================================================================

create extension if not exists pg_cron;

-- `cron.schedule` remplace une tâche du même nom : rejouer ce fichier ne
-- crée pas de doublon.
select cron.schedule(
  'ticonnect-response-stats', '17 * * * *',
  $$ select public.refresh_response_stats(); $$
);

select cron.schedule(
  'ticonnect-nightly', '0 3 * * *',
  $$ select public.expire_stale_jobs(); select public.expire_subscriptions(); $$
);

-- Pour vérifier ce qui tourne :
--   select jobname, schedule, active from cron.job;
--   select jobname, status, start_time, return_message
--     from cron.job_run_details order by start_time desc limit 20;
