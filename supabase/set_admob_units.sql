-- =====================================================================
-- Bascule des identifiants AdMob de test vers les vrais
--
-- À exécuter dans le SQL Editor une fois les blocs d'annonces créés dans
-- AdMob. Aucune republication de l'application n'est nécessaire : les
-- identifiants sont lus depuis cette table au démarrage.
--
-- Rappel : lancer l'app avec --dart-define=ADS_TEST=false pour que ces
-- valeurs soient réellement utilisées. En mode test, le code force les
-- identifiants de démonstration de Google, quoi qu'il y ait ici.
-- =====================================================================

update public.ad_placements set ad_unit_android = 'ca-app-pub-XXXXXXXXXXXXXXXX/1111111111'
 where key = 'unlock_contact_rewarded';   -- format: rewarded

update public.ad_placements set ad_unit_android = 'ca-app-pub-XXXXXXXXXXXXXXXX/2222222222'
 where key = 'boost_profile_rewarded';    -- format: rewarded

update public.ad_placements set ad_unit_android = 'ca-app-pub-XXXXXXXXXXXXXXXX/3333333333'
 where key = 'job_list_banner';           -- format: banner

update public.ad_placements set ad_unit_android = 'ca-app-pub-XXXXXXXXXXXXXXXX/4444444444'
 where key = 'profile_view_interstitial'; -- format: interstitial

update public.ad_placements set ad_unit_android = 'ca-app-pub-XXXXXXXXXXXXXXXX/5555555555'
 where key = 'app_open';                  -- format: app_open, désactivé par défaut

-- Contrôle : aucun emplacement actif ne doit rester sans identifiant
select key, format, is_enabled, ad_unit_android
  from public.ad_placements
 order by key;
