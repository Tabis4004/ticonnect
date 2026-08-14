-- =====================================================================
-- 60_ad_impressions_load_error.sql — Cause d'échec rapportée par le SDK
--
-- Trois séances de diagnostic pour distinguer « aucune annonce à servir »
-- de « l'utilisateur n'a pas regardé jusqu'au bout » : les deux se
-- manifestaient par un ssv_verified resté faux. Le code d'erreur du SDK
-- tranche en une ligne — le code 3 signale un « no fill ».
-- =====================================================================
alter table public.ad_impressions
  add column if not exists load_error text;

comment on column public.ad_impressions.load_error is
  'Message du SDK quand l''annonce n''a pu être ni chargée ni affichée. '
  'Nul si l''annonce s''est affichée, quoi qu''il soit advenu ensuite.';
