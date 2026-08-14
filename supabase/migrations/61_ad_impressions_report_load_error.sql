-- =====================================================================
-- 61_ad_impressions_report_load_error.sql
--
-- `ad_impressions` n'avait aucune politique UPDATE : le téléphone pouvait
-- créer une impression mais jamais la compléter. L'écriture de
-- `load_error` échouait en silence — elle est enveloppée dans un
-- try/catch, puisqu'un diagnostic qui casse le parcours serait pire que
-- l'absence de diagnostic.
--
-- Deux verrous : la politique interdit de toucher une impression déjà
-- vérifiée, et le droit colonne limite l'écriture à `load_error`.
-- =====================================================================
drop policy if exists ad_impressions_update_own_error on public.ad_impressions;
create policy ad_impressions_update_own_error on public.ad_impressions
  for update to authenticated
  using (profile_id = (select auth.uid()) and not ssv_verified)
  with check (profile_id = (select auth.uid()) and not ssv_verified);

revoke update on public.ad_impressions from authenticated;
grant  update (load_error) on public.ad_impressions to authenticated;
