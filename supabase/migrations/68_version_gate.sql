-- =====================================================================
-- 68_version_gate.sql — Proposer, ou imposer, une mise à jour
--
-- Le parc installé ne se met pas à jour tout seul : la mise à jour
-- automatique du Play Store est un réglage de l'appareil, souvent coupé
-- ici pour économiser les données. Une version en circulation qui appelle
-- une fonction supprimée, ou qui affiche un prix faux, y reste des mois.
--
-- Trois réglages plutôt qu'un, parce que « proposer » et « imposer » ne se
-- décident pas en même temps :
--
--   min_supported_version — plancher bloquant. En dessous, l'application
--     ne s'ouvre plus. À ne remonter que pour une version cassée : c'est
--     le seul outil qui retire une version défectueuse des mains des
--     utilisateurs sans attendre qu'ils veuillent bien mettre à jour.
--
--   recommended_version — simple invitation, refusable, montrée une fois
--     par ouverture de l'application.
--
--   store_url — l'adresse ouverte par le bouton. En base et non codée en
--     dur : le jour où l'application existe ailleurs qu'au Play Store, ou
--     si l'identifiant du paquet change, rien à republier.
--
-- Un plancher mal renseigné bloque tout le monde, y compris ceux qui
-- viennent d'installer. La comparaison côté application est donc
-- volontairement tolérante : une valeur illisible n'entraîne aucun
-- blocage.
-- =====================================================================

insert into public.app_settings (key, value, description, control, label, group_name, sort_order, is_visible)
values
  ('min_supported_version', '"0.0.0"'::jsonb,
   'Version minimale acceptée. En dessous, l''application affiche un écran '
   'bloquant. Laisser 0.0.0 tant qu''aucune version n''est à retirer.',
   'text', 'Version minimale (bloquante)', 'Version', 70, true),

  ('recommended_version', '"0.0.0"'::jsonb,
   'Version conseillée. En dessous, une invitation refusable est proposée '
   'une fois par ouverture.',
   'text', 'Version conseillée', 'Version', 71, true),

  ('store_url', '"https://play.google.com/store/apps/details?id=com.ticonnect.app"'::jsonb,
   'Adresse ouverte par le bouton « Mettre à jour ».',
   'text', 'Adresse de la fiche', 'Version', 72, true)
on conflict (key) do update set
  description = excluded.description,
  control     = excluded.control,
  label       = excluded.label,
  group_name  = excluded.group_name,
  sort_order  = excluded.sort_order,
  is_visible  = excluded.is_visible;
-- `value` volontairement absent du DO UPDATE : rejouer la migration ne
-- doit pas réinitialiser un plancher que l'administrateur a remonté.
