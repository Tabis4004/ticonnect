-- =====================================================================
-- 09_harden_function_grants.sql — Correctif de sécurité
--
-- PostgreSQL accorde EXECUTE à PUBLIC par défaut sur toute nouvelle
-- fonction. Un « revoke ... from anon, authenticated » ne suffit donc
-- pas : le grant PUBLIC subsiste et la fonction reste appelable via
-- /rest/v1/rpc/.
--
-- Sans ce fichier, n'importe qui pouvait appeler adjust_credits() et se
-- créditer un solde illimité. Détecté par les advisors Supabase.
-- =====================================================================

-- 1) Fonctions internes et fonctions de trigger : jamais exposées à l'API
revoke execute on function public.adjust_credits(uuid, integer, public.credit_txn_type, text, uuid, text) from public, anon, authenticated;
revoke execute on function public.expire_stale_jobs()             from public, anon, authenticated;
revoke execute on function public.set_updated_at()                from public, anon, authenticated;
revoke execute on function public.handle_new_user()               from public, anon, authenticated;
revoke execute on function public.create_wallet_for_profile()     from public, anon, authenticated;
revoke execute on function public.sync_applications_count()       from public, anon, authenticated;
revoke execute on function public.handle_application_accepted()   from public, anon, authenticated;
revoke execute on function public.flag_contact_in_message()       from public, anon, authenticated;
revoke execute on function public.sync_conversation_on_message()  from public, anon, authenticated;
revoke execute on function public.sync_worker_rating()            from public, anon, authenticated;
revoke execute on function public.sync_jobs_completed()           from public, anon, authenticated;
revoke execute on function public.check_report_threshold()        from public, anon, authenticated;

-- 2) Fonctions applicatives : retrait du grant PUBLIC implicite,
--    puis grant ciblé aux seuls comptes authentifiés (jamais anon).
revoke execute on function public.unlock_contact(uuid, uuid, uuid)  from public, anon;
revoke execute on function public.has_unlocked(uuid)                from public, anon;
revoke execute on function public.is_admin()                        from public, anon;
revoke execute on function public.is_conversation_participant(uuid) from public, anon;
revoke execute on function public.owns_job(uuid)                    from public, anon;
revoke execute on function public.has_applied_to_job(uuid)          from public, anon;
revoke execute on function public.job_is_open(uuid)                 from public, anon;
revoke execute on function public.can_review_job(uuid, uuid)        from public, anon;
revoke execute on function public.search_workers(smallint, text, text, double precision, double precision, numeric, text, integer, integer) from public, anon;
revoke execute on function public.search_jobs(smallint[], text, text, public.urgency_level, integer, integer) from public, anon;

grant execute on function public.unlock_contact(uuid, uuid, uuid)   to authenticated;
grant execute on function public.has_unlocked(uuid)                 to authenticated;
grant execute on function public.is_admin()                         to authenticated;
grant execute on function public.is_conversation_participant(uuid)  to authenticated;
grant execute on function public.owns_job(uuid)                     to authenticated;
grant execute on function public.has_applied_to_job(uuid)           to authenticated;
grant execute on function public.job_is_open(uuid)                  to authenticated;
grant execute on function public.can_review_job(uuid, uuid)         to authenticated;
grant execute on function public.search_workers(smallint, text, text, double precision, double precision, numeric, text, integer, integer) to authenticated;
grant execute on function public.search_jobs(smallint[], text, text, public.urgency_level, integer, integer) to authenticated;

-- Contrôle
select p.proname,
       has_function_privilege('anon', p.oid, 'EXECUTE')          as anon_peut,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_peut
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
 order by p.proname;
