-- =====================================================================
-- 47_settings_govern_placements.sql — Un réglage de placement doit
--                                     activer l'emplacement qu'il désigne
--
-- Deux défauts constatés en usage réel.
--
-- 1. `worker_apply_ad_placement` portait `sort_order = 100`, la valeur par
--    défaut : il tombait en dernier du groupe Publicité, sous la liste des
--    appareils de test, hors de l'écran. Il existait, il ne se voyait pas.
--
-- 2. Plus grave : choisir « avant » ou « après » côté ouvrier n'affichait
--    aucune annonce, parce que `apply_before_interstitial` et
--    `apply_after_interstitial` étaient `is_enabled = false` dans
--    `ad_placements`. Le réglage disait une chose, la table en disait une
--    autre, et `canShow()` tranchait en faveur de la table.
--
--    Le côté client ne marchait que grâce à un bout de Dart écrit à la main
--    dans l'ancienne carte d'administration, qui alignait les drapeaux
--    après coup. L'écran de réglages générique ne connaissait pas cette
--    règle, et l'éditeur SQL encore moins. Une règle métier vivant dans un
--    seul écran est une règle qui sera contournée par le deuxième.
--
-- La règle appartient donc à la donnée. `governs` déclare quel emplacement
-- chaque valeur commande ; un trigger s'en charge quel que soit le chemin
-- d'écriture.
-- =====================================================================

alter table public.app_settings
  add column if not exists governs jsonb;

comment on column public.app_settings.governs is
  'Pour un réglage `choice` pilotant des emplacements publicitaires : '
  '{"valeur": "clé_d_emplacement"}. La valeur retenue active son emplacement, '
  'toutes les autres sont désactivées.';

update public.app_settings set
  governs = '{"before": "job_post_before_interstitial",
              "after":  "job_post_after_interstitial"}'::jsonb
 where key = 'client_job_ad_placement';

update public.app_settings set
  governs = '{"before":   "apply_before_interstitial",
              "after":    "apply_after_interstitial",
              "rewarded": "apply_rewarded_interstitial"}'::jsonb,
  sort_order = 21
 where key = 'worker_apply_ad_placement';

-- Devenu sans objet : remplacé par `worker_apply_ad_placement`, qui
-- distingue en plus « imposé » de « récompensé ». Masqué plutôt que
-- supprimé — une version déjà installée peut encore le lire.
update public.app_settings
   set is_visible = false,
       description = 'Remplacé par worker_apply_ad_placement. Conservé pour '
                     'les versions déjà installées.'
 where key = 'worker_apply_ad_enabled';

-- =====================================================================
-- ALIGNEMENT AUTOMATIQUE
-- =====================================================================
create or replace function public.sync_governed_placements()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_chosen text;
begin
  if new.governs is null then
    return new;
  end if;

  -- Tout ce que ce réglage commande retombe à l'arrêt…
  update public.ad_placements
     set is_enabled = false, updated_at = now()
   where key in (select value_key
                   from jsonb_each_text(new.governs) as t(value_name, value_key));

  -- …puis on rallume le seul emplacement désigné, s'il existe. Une valeur
  -- comme « off » ne figure pas dans `governs` : tout reste éteint, ce qui
  -- est exactement le comportement voulu.
  v_chosen := new.governs ->> (new.value #>> '{}');

  if v_chosen is not null then
    update public.ad_placements
       set is_enabled = true, updated_at = now()
     where key = v_chosen;
  end if;

  return new;
end;
$$;

drop trigger if exists app_settings_sync_placements on public.app_settings;
create trigger app_settings_sync_placements
  after insert or update of value on public.app_settings
  for each row execute function public.sync_governed_placements();

-- Application immédiate de l'état courant des deux réglages.
update public.app_settings
   set value = value
 where governs is not null;
