# Fichiers à commiter

Travail réalisé : conformité AdMob, placements publicitaires repensés,
abonnements mensuels et annuels (FedaPay, GeniusPay), visibilité premium
plafonnée, identité progressive, parrainage de clients.

Les fichiers que tu as écrits en parallèle — `30_column_privileges.sql`,
`31_ad_rewards.sql`, `32_ad_revenue_reporting.sql`, `supabase/tests/`,
`brand_mark.dart`, les icônes — ne sont pas dans cette liste. À toi de
décider si tu les commites dans le même lot.

---

## Nouveaux fichiers (18)

### Migrations SQL (8)

```
supabase/migrations/12_ad_compliance.sql
supabase/migrations/13_payment_enums.sql
supabase/migrations/14_plan_prices.sql
supabase/migrations/15_premium_search.sql
supabase/migrations/16_progressive_identity.sql
supabase/migrations/17_storage_buckets.sql
supabase/migrations/40_referrals.sql
supabase/migrations/41_sponsored_priority.sql
```

Numérotées 40 et 41 pour les deux dernières : tu avançais sur 30 à 32, et
des numéros en double rendent l'ordre d'application dépendant du tri
alphabétique. `41_sponsored_priority.sql` doit rester le **dernier** fichier
à redéfinir `search_workers`.

### Edge Functions (4)

```
supabase/functions/_shared/providers.ts
supabase/functions/admob-ssv/index.ts
supabase/functions/create-payment/index.ts
supabase/functions/payment-webhook/index.ts
```

### Dart (5)

```
lib/services/settings_service.dart
lib/services/billing_service.dart
lib/services/referral_service.dart
lib/services/devices_service.dart
lib/widgets/ad_intro.dart
lib/features/profile/subscription_page.dart
lib/features/profile/referral_page.dart
```

### Documentation (2)

```
docs/deploiement.md
docs/a_commiter.md
```

---

## Fichiers modifiés (12)

```
lib/core/supabase.dart                 traduction des erreurs métier
lib/models/models.dart                 AdPlacement (intro), Profile (referral_code)
lib/services/session.dart              plan actif, présence du numéro
lib/services/ads_service.dart          interstitiel récompensé, garde-fou global
lib/services/ads/ads_backend.dart      contrat showRewardedInterstitial
lib/services/ads/ads_backend_mobile.dart
lib/services/ads/ads_backend_stub.dart
lib/features/jobs/job_create_page.dart placement client avant/après
lib/features/worker/job_detail_page.dart pub à la candidature
lib/features/profile/profile_page.dart abonnement + parrainage
lib/features/profile/admin_page.dart   bascule de placement, taux de fuite
lib/widgets/common.dart                mention « SPONSORISÉ »
pubspec.yaml                           package_info_plus déclaré
README.md
```

---

## Commande

```bash
cd ~/Documents/ticonnect

git add \
  supabase/migrations/1[2-7]_*.sql \
  supabase/migrations/4[01]_*.sql \
  supabase/functions/ \
  lib/services/settings_service.dart \
  lib/services/billing_service.dart \
  lib/services/referral_service.dart \
  lib/services/devices_service.dart \
  lib/widgets/ad_intro.dart \
  lib/features/profile/subscription_page.dart \
  lib/features/profile/referral_page.dart \
  docs/ \
  lib/core/supabase.dart \
  lib/models/models.dart \
  lib/services/session.dart \
  lib/services/ads_service.dart \
  lib/services/ads/ \
  lib/features/jobs/job_create_page.dart \
  lib/features/worker/job_detail_page.dart \
  lib/features/profile/profile_page.dart \
  lib/features/profile/admin_page.dart \
  lib/widgets/common.dart \
  pubspec.yaml \
  README.md

git status --short   # relire avant de valider
```

Message de commit proposé :

```
Monétisation : conformité AdMob, abonnements, parrainage clients

Publicité — remplace le visionnage forcé par l'interstitiel récompensé,
seul format qu'AdMob autorise à lancer sans opt-in, précédé de son écran
d'introduction. Déplace la charge principale côté ouvrier, à la
candidature. Côté client, les deux placements coexistent et se basculent
depuis le tableau de bord admin.

Abonnements — grille tarifaire par pays, mensuel et annuel, FedaPay et
GeniusPay. Le prix est relu en base par l'Edge Function ; l'activation
passe exclusivement par le webhook signé.

Visibilité premium — plafonne les places sponsorisées à une sur quatre,
sous note plancher, dans la limite de ce que le vivier organique permet
d'espacer. Les abonnés premium y ont priorité.

Identité progressive — numéro exigé au premier acte engageant, unicité,
bannissement des numéros de comptes suspendus.

Parrainage — un ouvrier invite ses clients. Qualifié sur une mission
ayant reçu une candidature d'un tiers, récompensé en jours de mise en
avant, avec rendements décroissants et plafond mensuel.
```

---

## Avant de pousser

1. `flutter pub get` — `package_info_plus` est passé en dépendance directe.
2. `flutter analyze` — le code n'a jamais été compilé, c'est là que les
   écarts d'API apparaîtront.
3. `supabase db push` — la migration 13 doit passer seule (une valeur
   d'énumération ne s'utilise pas dans la transaction qui la crée), et la 16
   s'interrompt volontairement si deux profils partagent un numéro.

## Reste ouvert

`username_available`, `set_my_location` et `get_my_location` sont appelées
par l'application et versionnées nulle part. Récupère leur définition
exacte depuis l'éditeur SQL avant d'en faire une migration — les réécrire
de mémoire risquerait d'écraser des fonctions qui marchent :

```sql
select pg_get_functiondef(p.oid) || E'\n'
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.prokind = 'f'
order by p.proname;
```
