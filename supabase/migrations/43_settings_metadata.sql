-- =====================================================================
-- 43_settings_metadata.sql — De quoi générer l'interface des réglages
--
-- `app_settings` stocke des valeurs jsonb, sans rien dire de la façon de
-- les présenter. Résultat : douze réglages en base, un seul avec un
-- contrôle dans l'application — les onze autres ne se modifient que depuis
-- l'éditeur SQL. La promesse « pilotable sans republier » n'était donc
-- tenue que pour un douzième du chemin.
--
-- Plutôt qu'un écran codé en dur, qu'il faudrait rouvrir à chaque nouveau
-- réglage, on décrit ici COMMENT afficher chaque valeur. L'application lit
-- ces métadonnées et fabrique le contrôle adapté. Tout réglage ajouté plus
-- tard obtient son interface sans une ligne de Dart.
--
-- C'est aussi ce qui permet de borner : un ratio de places sponsorisées à
-- 1, ou une note plancher à 5, casserait la recherche. Les bornes vivent
-- donc à côté de la valeur, pas dans la tête de celui qui édite.
-- =====================================================================

alter table public.app_settings
  add column if not exists control    text
    check (control in ('switch', 'number', 'choice', 'list', 'text')),
  add column if not exists label      text,
  add column if not exists group_name text,
  add column if not exists min_value  numeric,
  add column if not exists max_value  numeric,
  add column if not exists step       numeric,
  add column if not exists choices    jsonb,
  add column if not exists suffix     text,
  add column if not exists sort_order smallint not null default 100,
  add column if not exists is_visible boolean  not null default true;

comment on column public.app_settings.control is
  'Type de contrôle à afficher. NULL = réglage non éditable depuis l''app.';
comment on column public.app_settings.choices is
  'Pour `choice` : tableau [{"value":"after","label":"Après"}, …].';
comment on column public.app_settings.is_visible is
  'Un réglage peut exister sans être exposé — le temps d''une expérience, '
  'ou parce qu''il est trop dangereux pour une modification depuis un '
  'téléphone.';

-- =====================================================================
-- DESCRIPTION DES RÉGLAGES EXISTANTS
--
-- Les bornes ne sont pas décoratives. `sponsored_slot_ratio` en dessous de
-- 2 signifierait « tout est sponsorisé » et désactiverait le plafond
-- lui-même ; `sponsored_min_rating` est la seule protection de la qualité
-- de la recherche depuis que la monétisation repose sur le boost.
-- =====================================================================
update public.app_settings s set
  control    = v.control,
  label      = v.label,
  group_name = v.group_name,
  min_value  = v.min_value,
  max_value  = v.max_value,
  step       = v.step,
  choices    = v.choices,
  suffix     = v.suffix,
  sort_order = v.sort_order
from (values
  -- ------------------------------------------------------------ Boost
  ('boost_duration_hours', 'number', 'Durée d''un boost',
   'Boost', 1, 24, 1, null::jsonb, 'heures', 10),
  ('boost_max_hours', 'number', 'Cumul maximum',
   'Boost', 1, 168, 1, null::jsonb, 'heures', 11),

  -- ------------------------------------------------------- Publicité
  ('client_job_ad_placement', 'choice', 'Publicité côté client',
   'Publicité', null, null, null,
   '[{"value":"before","label":"Avant la saisie"},
     {"value":"after","label":"Après validation"},
     {"value":"off","label":"Aucune"}]'::jsonb, null, 20),
  ('worker_apply_ad_enabled', 'switch', 'Publicité à la candidature',
   'Publicité', null, null, null, null::jsonb, null, 21),
  ('ad_min_seconds_between_any', 'number', 'Délai entre deux pleins écrans',
   'Publicité', 0, 600, 5, null::jsonb, 'secondes', 22),
  ('ad_test_device_ids', 'list', 'Appareils de test',
   'Publicité', null, null, null, null::jsonb, null, 23),

  -- ------------------------------------------------------- Recherche
  ('sponsored_slot_ratio', 'number', 'Un sponsorisé toutes les N places',
   'Recherche', 2, 20, 1, null::jsonb, 'places', 30),
  ('sponsored_min_rating', 'number', 'Note plancher pour être sponsorisé',
   'Recherche', 0, 5, 0.5, null::jsonb, 'étoiles', 31),

  -- ------------------------------------------------------ Parrainage
  ('referral_enabled', 'switch', 'Parrainage de clients',
   'Parrainage', null, null, null, null::jsonb, null, 40),
  ('referral_monthly_cap_days', 'number', 'Plafond mensuel',
   'Parrainage', 0, 90, 1, null::jsonb, 'jours / 30 j', 41),
  ('referral_claim_window_days', 'number', 'Délai pour saisir un code',
   'Parrainage', 1, 365, 1, null::jsonb, 'jours', 42),
  ('referral_boost_days', 'list', 'Jours gagnés, du 1er filleul au suivant',
   'Parrainage', null, null, null, null::jsonb, null, 43)
) as v(key, control, label, group_name, min_value, max_value, step,
       choices, suffix, sort_order)
where s.key = v.key;

-- =====================================================================
-- BASCULE DES ABONNEMENTS
--
-- Le modèle économique se recentre sur le boost gagné par visionnage :
-- plus rien de payant. L'infrastructure d'abonnement (tables, tarifs par
-- pays, Edge Functions, écran de souscription) reste en place mais
-- inerte — c'est la même logique que `unlock_cost = 0` : un interrupteur,
-- pas une réécriture. Si les chiffres AdMob racontent autre chose dans un
-- an, c'est un réglage, pas une semaine de travail.
-- =====================================================================
insert into public.app_settings
  (key, value, description, control, label, group_name, sort_order)
values
  ('subscriptions_enabled', 'false'::jsonb,
   'Abonnements Pro et Premium. Désactivés : le modèle repose sur le boost '
   'gagné par visionnage de publicité. Tout le code reste en place.',
   'switch', 'Abonnements payants', 'Monétisation', 1)
on conflict (key) do nothing;

-- =====================================================================
-- LECTURE DES RÉGLAGES ÉDITABLES
--
-- `app_settings` est déjà lisible par tout compte authentifié, mais un
-- écran d'administration a besoin des métadonnées dans un ordre stable et
-- sans les lignes masquées.
-- =====================================================================
create or replace function public.editable_settings()
returns table (
  key         text,
  value       jsonb,
  control     text,
  label       text,
  description text,
  group_name  text,
  min_value   numeric,
  max_value   numeric,
  step        numeric,
  choices     jsonb,
  suffix      text
)
language sql
stable
security definer
set search_path = ''
as $$
  select s.key, s.value, s.control, s.label, s.description, s.group_name,
         s.min_value, s.max_value, s.step, s.choices, s.suffix
    from public.app_settings s
   where s.control is not null
     and s.is_visible
     and public.is_admin()
   order by s.group_name nulls last, s.sort_order, s.key;
$$;

grant execute on function public.editable_settings() to authenticated;

-- =====================================================================
-- ÉCRITURE BORNÉE
--
-- La politique RLS `app_settings_admin_write` empêche un non-administrateur
-- d'écrire, mais rien n'empêchait un administrateur de poser une valeur
-- absurde depuis un téléphone — un ratio à 1, une note plancher à 5, un
-- boost de 10 000 heures. Ce trigger applique les bornes déclarées
-- au-dessus, à la source, quel que soit le chemin d'écriture.
-- =====================================================================
create or replace function public.clamp_setting_value()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_num numeric;
begin
  if new.control = 'number'
     and jsonb_typeof(new.value) = 'number' then
    v_num := new.value::text::numeric;

    if new.min_value is not null then
      v_num := greatest(v_num, new.min_value);
    end if;
    if new.max_value is not null then
      v_num := least(v_num, new.max_value);
    end if;

    new.value := to_jsonb(v_num);

  elsif new.control = 'switch'
        and jsonb_typeof(new.value) <> 'boolean' then
    raise exception 'SETTING_TYPE_MISMATCH'
      using hint = 'Ce réglage attend un booléen.';

  elsif new.control = 'choice' and new.choices is not null then
    if not exists (
      select 1 from jsonb_array_elements(new.choices) c
       where c ->> 'value' = (new.value #>> '{}')
    ) then
      raise exception 'SETTING_CHOICE_INVALID'
        using hint = 'Valeur hors de la liste autorisée.';
    end if;

  elsif new.control = 'list'
        and jsonb_typeof(new.value) <> 'array' then
    raise exception 'SETTING_TYPE_MISMATCH'
      using hint = 'Ce réglage attend une liste.';
  end if;

  return new;
end;
$$;

drop trigger if exists app_settings_clamp on public.app_settings;
create trigger app_settings_clamp
  before insert or update of value on public.app_settings
  for each row execute function public.clamp_setting_value();
