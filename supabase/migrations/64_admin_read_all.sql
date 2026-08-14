-- =====================================================================
-- 64_admin_read_all.sql — Lecture administrateur sur toutes les tables
--
-- Seize tables n'avaient aucune politique admin : conversations,
-- messages, candidatures, coordonnées, portefeuilles, appareils,
-- paiements. L'administrateur ne pouvait ni modérer un échange, ni
-- comprendre un litige, ni vérifier une transaction.
--
-- LECTURE SEULE, délibérément. Ouvrir l'écriture sur `messages` ou
-- `reviews` permettrait de réécrire l'historique d'une conversation ou
-- une note — exactement ce qu'une modération ne doit jamais pouvoir
-- faire, sous peine de ne plus valoir preuve en cas de contestation.
--
-- SUR LA VIE PRIVÉE. Cet accès aux conversations privées et aux numéros
-- doit figurer dans la politique de confidentialité et dans le
-- formulaire de sécurité des données de la Play Console.
-- =====================================================================
do $$
declare
  t text;
  tables text[] := array[
    'ad_impressions', 'blocks', 'contact_details', 'contact_unlocks',
    'conversations', 'credit_transactions', 'credit_wallets', 'devices',
    'favorites', 'job_applications', 'messages', 'notifications',
    'payments', 'subscriptions', 'worker_portfolio', 'worker_service_areas',
    'worker_trades'];
begin
  foreach t in array tables loop
    if to_regclass('public.' || t) is not null then
      execute format('drop policy if exists %I on public.%I', t || '_admin_read', t);
      execute format(
        'create policy %I on public.%I for select to authenticated '
        'using ((select public.is_admin()))', t || '_admin_read', t);
    end if;
  end loop;
end
$$;
