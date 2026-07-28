-- =====================================================================
-- 06_rls.sql — Row Level Security
--
-- Règle d'or : tout ce qui touche à l'argent (portefeuille, transactions,
-- paiements, déverrouillages) est en lecture seule côté client. Les
-- écritures passent par des fonctions SECURITY DEFINER ou le service_role.
-- =====================================================================

alter table public.profiles              enable row level security;
alter table public.contact_details       enable row level security;
alter table public.admins                enable row level security;
alter table public.trade_categories      enable row level security;
alter table public.trades                enable row level security;
alter table public.worker_profiles       enable row level security;
alter table public.worker_trades         enable row level security;
alter table public.worker_service_areas  enable row level security;
alter table public.worker_portfolio      enable row level security;
alter table public.job_requests          enable row level security;
alter table public.job_applications      enable row level security;
alter table public.favorites             enable row level security;
alter table public.conversations         enable row level security;
alter table public.messages              enable row level security;
alter table public.reviews               enable row level security;
alter table public.credit_wallets        enable row level security;
alter table public.credit_transactions   enable row level security;
alter table public.ad_placements         enable row level security;
alter table public.ad_impressions        enable row level security;
alter table public.contact_unlocks       enable row level security;
alter table public.subscriptions         enable row level security;
alter table public.payments              enable row level security;
alter table public.reports               enable row level security;
alter table public.blocks                enable row level security;
alter table public.devices               enable row level security;
alter table public.notifications         enable row level security;

-- =====================================================================
-- FONCTION UTILITAIRE : participant d'une conversation
-- =====================================================================
create or replace function public.is_conversation_participant(p_conversation_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.conversations c
     where c.id = p_conversation_id
       and (select auth.uid()) in (c.client_id, c.worker_id)
  );
$$;

grant execute on function public.is_conversation_participant(uuid) to authenticated;

-- =====================================================================
-- HELPERS ANTI-RÉCURSION
--
-- job_requests et job_applications se référencent mutuellement dans
-- leurs politiques. Sans ces fonctions SECURITY DEFINER (qui contournent
-- la RLS de la table interrogée), PostgreSQL lève
-- « infinite recursion detected in policy for relation ».
-- =====================================================================
create or replace function public.owns_job(p_job_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.job_requests jr
     where jr.id = p_job_id and jr.client_id = (select auth.uid())
  );
$$;

create or replace function public.has_applied_to_job(p_job_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.job_applications ja
     where ja.job_id = p_job_id and ja.worker_id = (select auth.uid())
  );
$$;

create or replace function public.job_is_open(p_job_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.job_requests jr
     where jr.id = p_job_id
       and jr.status = 'open'
       and jr.expires_at > now()
       and jr.client_id <> (select auth.uid())
  );
$$;

create or replace function public.can_review_job(p_job_id uuid, p_reviewee uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.job_requests jr
     where jr.id = p_job_id
       and jr.status = 'completed'
       and (select auth.uid()) in (jr.client_id, jr.assigned_worker_id)
       and p_reviewee in (jr.client_id, jr.assigned_worker_id)
       and p_reviewee <> (select auth.uid())
  );
$$;

grant execute on function public.owns_job(uuid)            to authenticated;
grant execute on function public.has_applied_to_job(uuid)  to authenticated;
grant execute on function public.job_is_open(uuid)         to authenticated;
grant execute on function public.can_review_job(uuid, uuid) to authenticated;

-- =====================================================================
-- PROFILS
-- =====================================================================
create policy profiles_select_all on public.profiles
  for select to authenticated using (true);

create policy profiles_insert_self on public.profiles
  for insert to authenticated with check (id = (select auth.uid()));

create policy profiles_update_self on public.profiles
  for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy profiles_admin_all on public.profiles
  for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

-- =====================================================================
-- CONTACT_DETAILS — la barrière payante
-- =====================================================================
create policy contact_select_own_or_unlocked on public.contact_details
  for select to authenticated
  using (
    profile_id = (select auth.uid())
    or (select public.has_unlocked(profile_id))
    or (select public.is_admin())
  );

create policy contact_insert_own on public.contact_details
  for insert to authenticated with check (profile_id = (select auth.uid()));

create policy contact_update_own on public.contact_details
  for update to authenticated
  using (profile_id = (select auth.uid())) with check (profile_id = (select auth.uid()));

-- =====================================================================
-- ADMINS
-- =====================================================================
create policy admins_select_admin on public.admins
  for select to authenticated using ((select public.is_admin()));

-- =====================================================================
-- RÉFÉRENTIEL (lecture publique, écriture admin)
-- =====================================================================
create policy categories_select_all on public.trade_categories
  for select to anon, authenticated using (true);
create policy categories_admin_write on public.trade_categories
  for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

create policy trades_select_all on public.trades
  for select to anon, authenticated using (true);
create policy trades_admin_write on public.trades
  for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

-- =====================================================================
-- PROFIL OUVRIER
-- =====================================================================
create policy worker_select_listed on public.worker_profiles
  for select to authenticated
  using (is_listed or profile_id = (select auth.uid()) or (select public.is_admin()));

create policy worker_insert_self on public.worker_profiles
  for insert to authenticated with check (profile_id = (select auth.uid()));

create policy worker_update_self on public.worker_profiles
  for update to authenticated
  using (profile_id = (select auth.uid())) with check (profile_id = (select auth.uid()));

create policy worker_admin_all on public.worker_profiles
  for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

-- Métiers, zones, portfolio : lecture publique, écriture par le propriétaire
create policy worker_trades_select on public.worker_trades
  for select to authenticated using (true);
create policy worker_trades_write on public.worker_trades
  for all to authenticated
  using (worker_id = (select auth.uid())) with check (worker_id = (select auth.uid()));

create policy service_areas_select on public.worker_service_areas
  for select to authenticated using (true);
create policy service_areas_write on public.worker_service_areas
  for all to authenticated
  using (worker_id = (select auth.uid())) with check (worker_id = (select auth.uid()));

create policy portfolio_select on public.worker_portfolio
  for select to authenticated using (true);
create policy portfolio_write on public.worker_portfolio
  for all to authenticated
  using (worker_id = (select auth.uid())) with check (worker_id = (select auth.uid()));

-- =====================================================================
-- DEMANDES DE SERVICE
-- =====================================================================
create policy jobs_select_visible on public.job_requests
  for select to authenticated
  using (
    status = 'open'
    or client_id = (select auth.uid())
    or assigned_worker_id = (select auth.uid())
    or public.has_applied_to_job(id)
    or (select public.is_admin())
  );

create policy jobs_insert_own on public.job_requests
  for insert to authenticated with check (client_id = (select auth.uid()));

create policy jobs_update_own on public.job_requests
  for update to authenticated
  using (client_id = (select auth.uid())) with check (client_id = (select auth.uid()));

create policy jobs_delete_own on public.job_requests
  for delete to authenticated using (client_id = (select auth.uid()));

create policy jobs_admin_all on public.job_requests
  for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

-- =====================================================================
-- CANDIDATURES
-- =====================================================================
create policy applications_select_involved on public.job_applications
  for select to authenticated
  using (
    worker_id = (select auth.uid())
    or public.owns_job(job_id)
    or (select public.is_admin())
  );

create policy applications_insert_worker on public.job_applications
  for insert to authenticated
  with check (
    worker_id = (select auth.uid())
    and public.job_is_open(job_id)
  );

create policy applications_update_involved on public.job_applications
  for update to authenticated
  using (worker_id = (select auth.uid()) or public.owns_job(job_id))
  with check (worker_id = (select auth.uid()) or public.owns_job(job_id));

-- =====================================================================
-- FAVORIS
-- =====================================================================
create policy favorites_own on public.favorites
  for all to authenticated
  using (client_id = (select auth.uid())) with check (client_id = (select auth.uid()));

-- =====================================================================
-- MESSAGERIE
-- =====================================================================
create policy conversations_select_participant on public.conversations
  for select to authenticated
  using ((select auth.uid()) in (client_id, worker_id) or (select public.is_admin()));

create policy conversations_insert_participant on public.conversations
  for insert to authenticated
  with check ((select auth.uid()) in (client_id, worker_id));

create policy conversations_update_participant on public.conversations
  for update to authenticated
  using ((select auth.uid()) in (client_id, worker_id))
  with check ((select auth.uid()) in (client_id, worker_id));

create policy messages_select_participant on public.messages
  for select to authenticated
  using ((select public.is_conversation_participant(conversation_id)) or (select public.is_admin()));

create policy messages_insert_participant on public.messages
  for insert to authenticated
  with check (
    sender_id = (select auth.uid())
    and (select public.is_conversation_participant(conversation_id))
  );

create policy messages_update_participant on public.messages
  for update to authenticated
  using ((select public.is_conversation_participant(conversation_id)))
  with check ((select public.is_conversation_participant(conversation_id)));

-- =====================================================================
-- AVIS
-- =====================================================================
create policy reviews_select_visible on public.reviews
  for select to authenticated
  using (not is_hidden or reviewer_id = (select auth.uid()) or (select public.is_admin()));

create policy reviews_insert_participant on public.reviews
  for insert to authenticated
  with check (
    reviewer_id = (select auth.uid())
    and public.can_review_job(job_id, reviewee_id)
  );

create policy reviews_update_own on public.reviews
  for update to authenticated
  using (reviewer_id = (select auth.uid())) with check (reviewer_id = (select auth.uid()));

create policy reviews_admin_all on public.reviews
  for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

-- =====================================================================
-- ARGENT — lecture seule côté client
-- =====================================================================
create policy wallet_select_own on public.credit_wallets
  for select to authenticated
  using (profile_id = (select auth.uid()) or (select public.is_admin()));

create policy credit_txn_select_own on public.credit_transactions
  for select to authenticated
  using (profile_id = (select auth.uid()) or (select public.is_admin()));

create policy unlocks_select_own on public.contact_unlocks
  for select to authenticated
  using (
    unlocker_id = (select auth.uid())
    or target_profile_id = (select auth.uid())
    or (select public.is_admin())
  );

create policy subscriptions_select_own on public.subscriptions
  for select to authenticated
  using (profile_id = (select auth.uid()) or (select public.is_admin()));

create policy payments_select_own on public.payments
  for select to authenticated
  using (profile_id = (select auth.uid()) or (select public.is_admin()));

-- =====================================================================
-- PUBLICITÉ
-- =====================================================================
-- Config lisible par l'app : c'est ce qui permet d'ajuster la fréquence
-- des pubs sans republier sur le Play Store.
create policy ad_placements_select on public.ad_placements
  for select to anon, authenticated using (true);
create policy ad_placements_admin_write on public.ad_placements
  for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

create policy ad_impressions_select_own on public.ad_impressions
  for select to authenticated
  using (profile_id = (select auth.uid()) or (select public.is_admin()));

-- Le client peut journaliser une impression, mais JAMAIS la marquer
-- comme vérifiée ni s'attribuer des crédits : seule la callback SSV
-- d'AdMob (service_role) peut le faire.
create policy ad_impressions_insert_own on public.ad_impressions
  for insert to authenticated
  with check (
    profile_id = (select auth.uid())
    and ssv_verified = false
    and reward_credits = 0
  );

-- =====================================================================
-- MODÉRATION
-- =====================================================================
create policy reports_insert_own on public.reports
  for insert to authenticated with check (reporter_id = (select auth.uid()));

create policy reports_select_own on public.reports
  for select to authenticated
  using (reporter_id = (select auth.uid()) or (select public.is_admin()));

create policy reports_admin_write on public.reports
  for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

create policy blocks_own on public.blocks
  for all to authenticated
  using (blocker_id = (select auth.uid())) with check (blocker_id = (select auth.uid()));

-- =====================================================================
-- APPAREILS ET NOTIFICATIONS
-- =====================================================================
create policy devices_own on public.devices
  for all to authenticated
  using (profile_id = (select auth.uid())) with check (profile_id = (select auth.uid()));

create policy notifications_select_own on public.notifications
  for select to authenticated using (profile_id = (select auth.uid()));

create policy notifications_update_own on public.notifications
  for update to authenticated
  using (profile_id = (select auth.uid())) with check (profile_id = (select auth.uid()));
