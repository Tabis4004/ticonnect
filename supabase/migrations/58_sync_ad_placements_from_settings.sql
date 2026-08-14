-- =====================================================================
-- 58_sync_ad_placements_from_settings.sql
--
-- Deux réglages désignent lequel de plusieurs emplacements doit être
-- actif. L'alignement se faisait dans le code Dart, au moment de la
-- bascule. L'éditeur de réglages générique contourne ce chemin : il écrit
-- dans `app_settings` et rien d'autre. Le réglage aurait annoncé
-- « before » pendant que l'emplacement restait désactivé, sans message.
--
-- Placer la règle en base la rend valable quel que soit le chemin
-- d'écriture : éditeur générique, RPC dédiée, ou SQL à la main.
-- =====================================================================
create or replace function public.sync_ad_placements_from_settings()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare v_mode text := new.value #>> '{}';
begin
  if new.key = 'worker_apply_ad_placement' then
    update public.ad_placements set is_enabled = (v_mode = 'before')
     where key = 'apply_before_interstitial';
    update public.ad_placements set is_enabled = (v_mode = 'after')
     where key = 'apply_after_interstitial';
    update public.ad_placements set is_enabled = (v_mode = 'rewarded')
     where key = 'apply_rewarded_interstitial';
  elsif new.key = 'client_job_ad_placement' then
    update public.ad_placements set is_enabled = (v_mode = 'before')
     where key = 'job_post_before_interstitial';
    update public.ad_placements set is_enabled = (v_mode = 'after')
     where key = 'job_post_after_interstitial';
  end if;
  return new;
end;
$$;

revoke execute on function public.sync_ad_placements_from_settings()
  from public, anon, authenticated;

drop trigger if exists app_settings_sync_placements on public.app_settings;
create trigger app_settings_sync_placements
  after insert or update of value on public.app_settings
  for each row execute function public.sync_ad_placements_from_settings();

update public.app_settings set value = value
 where key in ('worker_apply_ad_placement', 'client_job_ad_placement');
