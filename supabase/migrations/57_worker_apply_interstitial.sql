-- =====================================================================
-- 57_worker_apply_interstitial.sql — Interstitiel imposé à la candidature
--
-- Le format récompensé exige un consentement explicite à chaque vidéo :
-- le rendre obligatoire déclenche « Disallowed Rewarded Implementation ».
-- L'interstitiel simple s'impose légalement à un point de transition, et
-- Google y place lui-même un bouton de fermeture après quelques secondes
-- sur les créatifs vidéo — le comportement recherché, sans que le délai
-- soit à notre main.
--
-- Deux emplacements, un seul actif. Le débat « avant ou après l'envoi »
-- se tranche sur le nombre de candidatures observé : avant l'envoi,
-- chaque abandon pendant la vidéo est une candidature perdue.
-- =====================================================================
insert into public.ad_placements
  (key, format, ad_unit_android, is_enabled, reward_credits,
   daily_cap_per_user, min_seconds_between, description)
values
  ('apply_before_interstitial', 'interstitial',
   'ca-app-pub-3940256099942544/1033173712', false, 0, 8, 60,
   'Ouvrier, AVANT l''envoi de la candidature. Garantit l''impression, '
   'mais expose à l''abandon au pire moment. Désactivé par défaut.'),
  ('apply_after_interstitial', 'interstitial',
   'ca-app-pub-3940256099942544/1033173712', false, 0, 8, 60,
   'Ouvrier, APRÈS l''envoi, sur l''écran de confirmation. Même volume '
   'd''impressions, aucune candidature perdue. Recommandé.')
on conflict (key) do nothing;

insert into public.app_settings (key, value, description) values
  ('worker_apply_ad_placement', '"rewarded"'::jsonb,
   'Publicité à la candidature : "before", "after", "rewarded" ou "off".')
on conflict (key) do nothing;

create or replace function public.set_worker_apply_placement(p_mode text)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Réservé aux administrateurs' using errcode = '42501';
  end if;
  if p_mode not in ('before', 'after', 'rewarded', 'off') then
    raise exception 'Mode inconnu : %', p_mode;
  end if;
  update public.app_settings
     set value = to_jsonb(p_mode), updated_by = auth.uid()
   where key = 'worker_apply_ad_placement';
  update public.ad_placements set is_enabled = (p_mode = 'before')
   where key = 'apply_before_interstitial';
  update public.ad_placements set is_enabled = (p_mode = 'after')
   where key = 'apply_after_interstitial';
  update public.ad_placements set is_enabled = (p_mode = 'rewarded')
   where key = 'apply_rewarded_interstitial';
end;
$$;

revoke execute on function public.set_worker_apply_placement(text) from public, anon;
grant  execute on function public.set_worker_apply_placement(text) to authenticated;
