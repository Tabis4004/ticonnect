# Google Play Billing — travail en suspens

Arrêté volontairement le 14 août 2026, après le socle en base.

## Où en est-on

**Fait, appliqué en base** (migrations 69 et 70)

- valeur `google_play` dans l'énumération `payment_provider`
- table `play_products` — le lien entre une offre TiConnect et un
  identifiant produit de la Play Console
- table `play_purchases` — registre des achats, clé primaire sur le jeton
  Google, ce qui rend l'application d'un achat idempotente
- `record_play_purchase()` — le client annonce un jeton, n'obtient rien
- `apply_play_purchase()` — accorde le droit, révoquée pour `anon` et
  `authenticated`
- `reject_play_purchase()` — remboursement, expiration, rejet

**Pas fait**

- l'Edge Function `verify-play-purchase` : OAuth par compte de service,
  appel à l'API Google Play Developer, accusé de réception
- l'entrée RTDN pour les renouvellements et les annulations
- le plugin `in_app_purchase` et le service Dart
- les produits dans la Play Console
- le réglage `play_billing_enabled` et le garde-fou de conformité

## Est-ce dangereux de laisser ça en l'état

Non. `play_products` est vide, donc `record_play_purchase` lève
`PRODUCT_UNKNOWN` sur tout appel. Aucun client ne sait acheter.
`subscriptions_enabled` vaut `false`. Rien n'est exposé.

La valeur d'énumération `google_play` ne peut pas être retirée — PostgreSQL
ne le permet pas — mais elle est inerte tant que rien ne l'écrit.

## Ce qui doit être vérifié avant de reprendre

**Les moyens de paiement disponibles en Côte d'Ivoire et au Togo.** Si Play
Billing n'accepte pas Orange Money, MTN MoMo et Wave, tout ce qui précède
ne vendra rien, quel que soit le prix. Cette vérification décide de la
suite et prend cinq minutes : Play Console, ou un appareil sur place face à
l'écran de paiement d'une application payante.

Ce n'est pas la commission de 15 % qui tranche. C'est ça.

## Le renoncement à peser

Avec Play Billing, **le tarif par pays appartient à la Play Console**. La
table `plan_prices` et l'écran d'administration qui la pilote cessent de
gouverner les abonnements. C'était une exigence explicite au départ — « les
conditions financières diffèrent d'un pays à l'autre » — et elle n'est pas
compatible avec ce mode de facturation.

## Le calendrier qui peut tout changer

Le programme **Billing Choice** de Google, lancé le 30 juin 2026, autorise
un système de paiement tiers à 10 % au lieu de 15 %. Il couvre les
États-Unis, le Royaume-Uni et l'EEE, s'étend à l'Australie en septembre, au
Japon et à la Corée en décembre, et au reste du monde courant 2027.

Quand il atteindra l'Afrique de l'Ouest, FedaPay redeviendra utilisable
pour les articles numériques, avec la grille par pays reprise en main.
Attendre a donc une valeur, pas seulement un coût.
