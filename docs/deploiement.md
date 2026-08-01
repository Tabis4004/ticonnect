# Mise en service

Ce qui reste à faire hors du code — chaque étape dépend d'une console
externe à laquelle seul le propriétaire du projet a accès.

L'ordre compte : les trois premières se bloquent mutuellement.

---

## 1. Appliquer les migrations

```bash
cd ~/Documents/ticonnect
supabase db push
```

Les migrations 12 à 17 sont additives et rejouables. Deux points d'attention :

**La migration 13 doit passer seule.** PostgreSQL refuse d'utiliser une
valeur d'énumération dans la transaction qui l'a créée ; `fedapay`,
`geniuspay` et le type `billing_period` sont donc isolés dans leur propre
fichier. Si `supabase db push` les regroupe, appliquer 13 puis relancer.

**La migration 16 s'interrompt volontairement** si `contact_details`
contient deux profils avec le même numéro. Le message nomme le nombre de
doublons. Les fusionner avant de rejouer — créer l'index unique en l'état
masquerait le problème plutôt que de le traiter.

---

## 2. Déployer les Edge Functions

```bash
supabase functions deploy admob-ssv       --no-verify-jwt
supabase functions deploy payment-webhook --no-verify-jwt
supabase functions deploy create-payment
```

`--no-verify-jwt` sur les deux premières : AdMob et les fournisseurs de
paiement appellent sans jeton Supabase. Leur authenticité vient de la
signature cryptographique, vérifiée avant toute écriture. `create-payment`
garde la vérification du JWT — seul un utilisateur connecté peut payer.

### Secrets

```bash
supabase secrets set \
  GENIUSPAY_API_KEY=pk_live_xxx \
  GENIUSPAY_API_SECRET=sk_live_xxx \
  GENIUSPAY_WEBHOOK_SECRET=whsec_live_xxx \
  FEDAPAY_SECRET_KEY=sk_live_xxx \
  FEDAPAY_WEBHOOK_SECRET=wh_xxx \
  FEDAPAY_ENV=live
```

Commencer en `sandbox` des deux côtés (`pk_sandbox_…`, `FEDAPAY_ENV=sandbox`)
et ne basculer qu'après un paiement de bout en bout réussi.

Le secret webhook GeniusPay n'est retourné **qu'à la création du webhook**.
S'il est perdu, il faut recréer le webhook.

---

## 3. Vérification côté serveur AdMob

Console AdMob → Applications → *Ticonnect* → Paramètres →
**Vérification côté serveur des annonces avec récompense** :

```
https://<projet>.supabase.co/functions/v1/admob-ssv
```

Sans cette URL, `AdsService.showRewarded()` attend une validation qui
n'arrive jamais et rend `null` : aucune récompense n'est accordée. C'est le
comportement voulu — mieux vaut ne rien donner que d'accorder
l'invérifiable — mais cela neutralise le format publicitaire au meilleur
rendement.

### Identifiants d'unités

Les identifiants actuels sont ceux de **test** de Google. Avant publication :

1. Créer les unités dans AdMob, dont une de type **interstitiel
   récompensé** — c'est le format des emplacements
   `apply_rewarded_interstitial` et `unlock_rewarded_interstitial`.
2. Remplacer `ad_unit_android` et `ad_unit_ios` dans `ad_placements`.
3. Mettre à jour l'identifiant d'application dans `bootstrap.sh`.
4. Compiler avec `--dart-define=ADS_TEST=false`.

Ne jamais tester avec les vrais identifiants : cliquer sur ses propres
publicités fait suspendre le compte.

---

## 4. Webhooks de paiement

**GeniusPay** — tableau de bord → Webhooks :

```
https://<projet>.supabase.co/functions/v1/payment-webhook/geniuspay
```

Événements : `payment.success`, `payment.failed`, `payment.cancelled`,
`payment.expired`.

**FedaPay** — tableau de bord → Webhooks :

```
https://<projet>.supabase.co/functions/v1/payment-webhook/fedapay
```

Événements : `transaction.approved`, `transaction.declined`,
`transaction.canceled`.

Le dernier segment de l'URL désigne le fournisseur : l'inverser ferait
échouer toutes les vérifications de signature.

FedaPay désactive un webhook après dix échecs consécutifs. Décocher
« Désactiver le webhook en cas d'erreur » le temps de la mise au point.

---

## 5. Notifications push — le seul lot non terminé

`DevicesService` sait enregistrer, rafraîchir et retirer un jeton. Ce qui
manque est l'obtention du jeton, qui exige `firebase_messaging`, qui exige
lui-même un `google-services.json` généré depuis une console Firebase
rattachée à ce projet.

La dépendance n'a pas été ajoutée : sans ce fichier, la compilation Gradle
échoue et l'application ne se lance plus du tout. Une fois la console
Firebase créée :

```yaml
# pubspec.yaml
firebase_core: ^3.6.0
firebase_messaging: ^15.1.3
```

1. Déposer `google-services.json` dans `android/app/`.
2. Ajouter le plugin Google Services au Gradle Android.
3. Dans `main.dart`, après `Supabase.initialize` :

```dart
await Firebase.initializeApp();
final token = await FirebaseMessaging.instance.getToken();
if (token != null) await DevicesService.register(token);
FirebaseMessaging.instance.onTokenRefresh.listen(DevicesService.register);
```

Appeler `DevicesService.unregister(token)` à la déconnexion : le partage
d'un téléphone entre plusieurs personnes est la norme sur ce marché, pas
l'exception.

Sans push, un ouvrier ne sait pas qu'une mission de son métier vient
d'être publiée — c'est le cœur de la proposition de valeur.

---

## 6. Expiration des abonnements

`expire_subscriptions()` marque comme expirés les abonnements échus. À
brancher sur `pg_cron`, avec `expire_stale_jobs()` :

```sql
select cron.schedule(
  'ticonnect-nightly', '0 3 * * *',
  $$ select public.expire_stale_jobs(); select public.expire_subscriptions(); $$
);
```

Ce n'est pas critique pour la justesse : `active_plan()` et `my_plan()`
comparent la date d'expiration à l'instant présent, jamais le seul statut.
Un retard de tâche planifiée n'offre donc de premium à personne — la
fonction ne fait que garder les statuts propres pour les statistiques.

---

## 7. Parrainage

Un ouvrier invite ses **clients**, jamais d'autres ouvriers : amener des
ouvriers ajoute de l'offre à une marketplace qui manque de demande, ce qui
la rend pire. La récompense est du temps de mise en avant, pas un score —
elle passe donc par le plafond de la recherche.

Une invitation ne compte que lorsque le filleul **publie une mission qui
reçoit une première candidature d'un tiers**. Un fraudeur doit donc
contrôler deux comptes avec deux numéros distincts pour gagner un seul jour
de boost, et le bannissement du filleul reprend les jours accordés.

| Clé | Défaut | Effet |
|---|---|---|
| `referral_enabled` | `true` | Active le dispositif |
| `referral_boost_days` | `[7,5,3,1]` | Jours gagnés, du 1ᵉʳ filleul au suivant |
| `referral_monthly_cap_days` | `20` | Plafond sur 30 jours glissants — 8 parrainages |
| `referral_claim_window_days` | `30` | Délai pour saisir un code après inscription |

Les abonnés Premium ont priorité sur les places sponsorisées : sans cet
arbitrage, les boosts gratuits évinceraient les abonnements payants et l'on
cannibaliserait ce que l'on vend.

Un contrôle « même appareil » est en place mais dormant : il s'appuie sur
la table `devices`, encore vide tant que les notifications push ne sont pas
branchées. Il s'activera de lui-même.

---

## 8. Réglages à surveiller après le lancement

**Administration → icône réglages.** L'écran est généré depuis
`app_settings` : chaque ligne y déclare son type de contrôle, ses bornes et
son libellé, et l'application fabrique l'interface correspondante. Un
réglage ajouté en base demain apparaît sans une ligne de Dart.

Les bornes sont appliquées par le trigger `app_settings_clamp`, donc quel
que soit le chemin d'écriture — écran, éditeur SQL, appel direct. Une
valeur hors limites est ramenée à la plus proche ; un type incohérent est
refusé.

| Groupe | Réglage | Défaut | Ce qu'il arbitre |
|---|---|---|---|
| Monétisation | `subscriptions_enabled` | `false` | Abonnements payants. À faux, le modèle repose sur le boost gagné par visionnage — le code reste en place |
| Boost | `boost_duration_hours` | `6` | Durée gagnée par vidéo |
| Boost | `boost_max_hours` | `24` | Cumul maximum |
| Publicité | `client_job_ad_placement` | `after` | Publicité client avant ou après la saisie du besoin |
| Publicité | `worker_apply_ad_enabled` | `true` | Publicité à la candidature |
| Publicité | `ad_min_seconds_between_any` | `45` | Délai global entre deux pleins écrans |
| Publicité | `ad_test_device_ids` | `[]` | Appareils recevant des pubs de test en production |
| Recherche | `sponsored_slot_ratio` | `4` | Un résultat sponsorisé toutes les N positions |
| Recherche | `sponsored_min_rating` | `3.5` | Note plancher pour occuper une place sponsorisée |
| Parrainage | `referral_enabled` | `true` | Parrainage de clients par les ouvriers |
| Parrainage | `referral_monthly_cap_days` | `20` | Plafond sur 30 jours glissants |
| Parrainage | `referral_claim_window_days` | `30` | Délai pour saisir un code |
| Parrainage | `referral_boost_days` | `[7,5,3,1]` | Jours gagnés, du 1ᵉʳ filleul au suivant |

**Les deux curseurs qui comptent le plus** sont désormais
`boost_duration_hours` et `boost_max_hours` : dans un modèle qui repose
entièrement sur le boost gagné par visionnage, ce sont eux qui décident de
la rareté de la mise en avant. Trop longs, tout le monde est boosté et
personne ne l'est.

Et `sponsored_min_rating` devient la **seule** protection de la qualité de
la recherche. Ne la descendez pas sous 3,5.

L'indicateur à regarder en premier est le **taux de fuite hors plateforme**,
affiché sur le tableau de bord admin. Au-delà de 60 %, une commission sur
prestation ne serait jamais collectable : l'abonnement reste le seul modèle
tenable. En dessous, la question pourra se rouvrir — mais seulement après
avoir construit l'encaissement, le séquestre et la garantie.
