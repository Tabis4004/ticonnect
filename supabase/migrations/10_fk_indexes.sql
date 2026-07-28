-- =====================================================================
-- 10_fk_indexes.sql — Index de couverture sur les clés étrangères
--
-- PostgreSQL n'indexe pas automatiquement le côté enfant d'une clé
-- étrangère. Sans ces index, chaque suppression en cascade (supprimer
-- un compte, une mission) déclenche un scan complet de la table enfant.
-- Signalé par les advisors performance de Supabase.
-- =====================================================================

create index if not exists ad_impressions_placement_idx on public.ad_impressions (placement_key);
create index if not exists blocks_blocked_idx           on public.blocks (blocked_id);
create index if not exists unlocks_ad_impression_idx    on public.contact_unlocks (ad_impression_id);
create index if not exists unlocks_job_idx              on public.contact_unlocks (job_id);
create index if not exists conversations_job_idx        on public.conversations (job_id);
create index if not exists job_trade_idx                on public.job_requests (trade_id);
create index if not exists messages_sender_idx          on public.messages (sender_id);
create index if not exists payments_subscription_idx    on public.payments (subscription_id);
create index if not exists reports_job_idx              on public.reports (job_id);
create index if not exists reports_message_idx          on public.reports (message_id);
create index if not exists reports_reporter_idx         on public.reports (reporter_id);
create index if not exists reports_resolver_idx         on public.reports (resolved_by);
create index if not exists reviews_reviewer_idx         on public.reviews (reviewer_id);
create index if not exists portfolio_trade_idx          on public.worker_portfolio (trade_id);
