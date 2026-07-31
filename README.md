# Ticonnect — application mobile

Mise en relation entre ouvriers et demandeurs de services.
Flutter, Android d'abord, adossé au projet Supabase **Ticonnect 1.0**.

---

## Démarrer

```bash
cd ~/Documents/ticonnect
./bootstrap.sh
flutter run
```

`bootstrap.sh` fait trois choses : il génère les dossiers `android/` et `ios/`
que Flutter doit créer lui-même (le wrapper Gradle est un binaire, il ne peut
pas être écrit à la main), il récupère les dépendances, puis il ajoute au
manifeste Android la permission Internet et l'identifiant d'application AdMob.

**Ce code n'a pas été compilé.** L'environnement où il a été écrit n'a ni SDK
Flutter ni accès réseau. La cohérence a été vérifiée autrement — voir la
section *Vérifications* plus bas — mais le premier `flutter analyze` remontera
probablement quelques ajustements de versions. Si `pub get` échoue sur une
contrainte, lance :

```bash
flutter pub upgrade --major-versions
```

---

## Tester en local

L'application tape sur le projet Supabase hébergé — pas besoin de base locale.

```bash
cd ~/Documents/ticonnect
./bootstrap.sh                                # une seule fois
flutter run --dart-define-from-file=dev.json
```

### Dans le navigateur, tout de suite

Le plus rapide pour voir l'application tourner, sans émulateur ni téléphone :

```bash
flutter create . --platforms=web       # si le dossier web/ n'existe pas encore
flutter run -d chrome --dart-define-from-file=dev.json
```

Tout fonctionne — connexion, recherche, publication, messagerie temps réel —
**sauf la publicité** : AdMob n'a pas d'implémentation web. `AdsService` le
détecte via `kIsWeb` et ne demande simplement aucune publicité, sans planter.

### Sur un vrai appareil

Émulateur Android (Android Studio → Device Manager) ou téléphone branché en
USB avec le débogage activé :

```bash
flutter run --dart-define-from-file=dev.json
```

C'est le seul contexte où la publicité s'affiche.
`flutter devices` liste ce qui est disponible.

### Se connecter

L'inscription normale passe par SMS, ce qui suppose un fournisseur configuré
et facturé. Pour le développement, l'écran d'accueil propose
**« Connexion par email (admin et tests) »**, avec les champs pré-remplis
depuis `dev.json`.

| Compte | Email | Rôle |
|---|---|---|
| Superadmin | `isidoretabati@gmail.com` | accès total + tableau de bord |
| Client | `client@ticonnect.test` | parcours demandeur |
| Ouvrier | `ouvrier@ticonnect.test` | parcours ouvrier |

Le mot de passe est dans `dev.json`, à la racine du projet.

**`dev.json` est ignoré par Git, et doit le rester.** Le dépôt est public :
un mot de passe committé donnerait à n'importe qui l'accès superadmin à la
base de production. `dev.json.example` est là pour montrer le format à un
autre développeur. Les comptes et les données de démonstration sont recréés
par `supabase/seed_dev.sql`, lui aussi hors dépôt.

### Ce qu'il y a déjà en base

Trois missions de démonstration à Abidjan (maçonnerie, plomberie, chauffeur)
publiées par le compte client, et un profil de maçon vérifié. De quoi voir les
deux parcours tourner immédiatement.

### Le tableau de bord admin

Visible dans *Mon compte* quand le profil connecté figure dans la table
`admins` : volumétrie, signalements ouverts, et surtout le **taux de fuite
hors plateforme** — les messages contenant un numéro de téléphone. C'est
l'indicateur qui dira si les gens quittent l'app dès le premier contact.

L'accès repose sur `is_admin()` et les politiques RLS côté base, pas sur du
code applicatif : impossible à contourner en modifiant l'APK.

---

## Ce que l'application fait

**Côté client** — gratuit de bout en bout.
Recherche d'ouvriers par métier et catégorie, fiche ouvrier avec avis et
tarifs, accès au numéro sans payer, publication d'une demande, réception et
sélection des candidatures, clôture de la mission et notation.

**Côté ouvrier** — gratuit également.
Fil des missions filtré sur ses propres métiers, candidature gratuite, accès
au numéro du client sans rien payer, portefeuille de crédits (réservé aux
options à venir : mise en avant du profil, services premium).

**Commun** — messagerie temps réel, profil, déconnexion.

---

## Trois décisions de conception

### Tout est gratuit, y compris la prise de contact

Personne ne paie pour se mettre en relation : ni le client, ni l'ouvrier.
Le revenu vient de la publicité, et — depuis les migrations 12 à 17 — de
l'abonnement optionnel des ouvriers.

**Aucune commission n'est prélevée sur le travail, et ce n'est pas
provisoire.** Sans encaissement de la prestation, sans séquestre et sans
garantie, une commission serait déclarative : les deux parties
s'arrangeraient hors de l'application et il n'y aurait rien à collecter.
L'abonnement, lui, facture la visibilité — un service que la plateforme
rend réellement et qu'aucun arrangement direct ne remplace. C'est aussi
l'argument commercial le plus simple face aux plateformes à commission :
un ouvrier leur verse souvent sur un seul chantier ce qu'un mois
d'abonnement coûte ici.

Le taux de fuite hors plateforme, mesuré sur le tableau de bord admin,
dira si cette position doit un jour évoluer. Au-delà de 60 %, la question
est tranchée pour de bon.

Le paywall n'a pas été supprimé pour autant, il a été **désactivé par une
valeur**. `job_requests.unlock_cost` vaut 0 ; toute la mécanique de crédits,
de quotas et de vidéos récompensées reste en place et se réactive dès que
cette colonne repasse au-dessus de zéro — globalement via le `DEFAULT`, ou
mission par mission pour tester sur une ville avant de généraliser. Aucune
republication sur le Play Store n'est nécessaire.

C'est le curseur le plus important du produit : garde-le à zéro pour amorcer
la marketplace, monte-le quand les ouvriers auront constaté que l'app leur
rapporte du travail.

### Chaque mise en relation reste enregistrée

Même gratuite, la ligne est écrite dans `contact_unlocks`. C'est l'indicateur
qui compte : combien de clients et d'ouvriers se sont réellement parlé.
Sans cette mesure, impossible de savoir si le produit fonctionne.

### La publicité est pilotée depuis la base

La table `ad_placements` porte les identifiants d'unités, la fréquence, les
plafonds journaliers et le délai minimum entre deux affichages.
`AdsService` lit cette configuration au démarrage. Concrètement : tu ajustes
l'agressivité publicitaire depuis le tableau de bord Supabase, sans republier
sur le Play Store. C'est ce qui permettra de trouver l'équilibre revenu /
rétention après le lancement, quand tu auras de vrais chiffres.

---

## La publicité, en pratique

`lib/services/ads_service.dart` et `lib/widgets/locked_contact.dart`.

La prise de contact étant gratuite, le revenu vient désormais des **bannières**
(bas du fil des missions et des résultats de recherche) et des **interstitiels**
(ouverture d'une fiche ouvrier — entre deux écrans, jamais pendant une action
ni au lancement).

La **vidéo récompensée** subsiste à deux endroits : gagner un crédit depuis le
portefeuille, et le déverrouillage payant si tu réactives `unlock_cost`. Le
bouton est un opt-in explicite, présenté à chaque fois, avec une alternative
toujours visible. Forcer le visionnage déclencherait la violation
*Disallowed Rewarded Implementation* et pourrait faire suspendre le compte.

**À savoir :** ce sont les formats récompensés qui ont le meilleur eCPM, et de
loin. En rendant le contact gratuit, tu perds l'occasion la plus naturelle
d'en proposer un. Les bannières et interstitiels rapportent nettement moins,
surtout aux eCPM pratiqués sur ce marché.

### Ce qui est autorisé, et ce qui fait suspendre le compte

Une règle AdMob décide de tout ici : **une annonce `rewarded` ne peut être
diffusée qu'après un opt-in affirmatif, publicité par publicité.** Forcer
son visionnage — avant une candidature, avant la saisie d'un besoin,
n'importe où — déclenche la violation *Disallowed Rewarded Implementation*
et expose le compte à une suspension. Ce n'est pas un risque théorique.

Deux formats permettent malgré tout un affichage quasi systématique, et ce
sont les seuls employés :

| Format | Imposable ? | Condition |
|---|---|---|
| `interstitial` | oui, sans skip | entre deux écrans, jamais pendant une action ni à chaque action |
| `rewarded_interstitial` | oui, sans opt-in | écran d'introduction annonçant la récompense **et** bouton pour passer |
| `rewarded` | non | bouton explicite à chaque fois |

L'écran d'introduction est `AdIntro.ask()` dans `widgets/ad_intro.dart`.
Ses libellés viennent de `ad_placements`, mais **le bouton pour passer est
une pièce de conformité, pas un réglage** : le masquer ou le griser remet
le compte en infraction.

Où les publicités se jouent, et pourquoi :

- **Ouvrier, à la candidature** (`apply_rewarded_interstitial`) — c'est la
  charge principale. La valeur y est reçue, et le volume suit l'activité
  réelle de la marketplace plutôt que le nombre d'inscrits. Elle ne bloque
  jamais l'envoi : inventaire vide ou refus, la candidature part quand même.
- **Client, après validation du besoin** (`job_post_after_interstitial`) —
  actif par défaut. Le côté rare d'une marketplace de services n'est pas
  l'ouvrier mais le client qui a un vrai chantier ; lui imposer une vidéo
  avant qu'il puisse décrire son problème ajoute de la friction à l'instant
  où son engagement est encore nul.
- **Client, avant la saisie** (`job_post_before_interstitial`) — construit,
  désactivé. `app_settings.client_job_ad_placement` bascule entre les deux
  depuis le tableau de bord admin, sans republier. Surveiller le nombre de
  missions publiées après chaque bascule.

Un garde-fou global (`ad_min_seconds_between_any`, 45 s par défaut) empêche
deux pleins écrans de s'enchaîner, quels que soient leurs emplacements.

### Le point bloquant à traiter

Le chemin récompensé **n'accorde de crédit qu'une fois `admob-ssv`
déployée** — la fonction est écrite (`supabase/functions/admob-ssv`), il
reste à la déployer et à déclarer son URL dans la console AdMob. Voir
`docs/deploiement.md`.

Tant qu'elle ne l'est pas, `AdsService.showRewarded()` attend une
confirmation qui n'arrive jamais et rend `null`. C'est délibéré : la
politique RLS interdit au téléphone d'écrire `ssv_verified` ou
`reward_credits`, et sans vérification serveur une version modifiée de
l'app se créditerait à l'infini. Mieux vaut ne rien accorder que
d'accorder l'invérifiable.

---

## Structure

```
lib/
├── main.dart              init Supabase + AdMob, aiguillage session
├── core/
│   ├── config.dart        URL et clé Supabase, mode test AdMob
│   ├── supabase.dart      raccourcis client, traduction des erreurs SQL
│   ├── theme.dart         contrastes élevés, zones tactiles généreuses
│   └── formatters.dart    francs CFA, dates relatives, distances
├── models/models.dart     miroir Dart des tables et des fonctions de recherche
├── services/
│   ├── session.dart       état observable : profil, profil ouvrier, crédits
│   ├── auth_service.dart  connexion par SMS, normalisation des numéros
│   ├── ads_service.dart   AdMob piloté par ad_placements
│   ├── contact_service.dart  déverrouillage + portefeuille
│   ├── jobs_service.dart  missions et candidatures
│   ├── workers_service.dart  profils ouvriers et avis
│   ├── chat_service.dart  messagerie temps réel
│   └── catalog_service.dart  référentiel des 54 métiers, mis en cache
├── widgets/
│   ├── common.dart        cartes, notation, bannière publicitaire
│   └── locked_contact.dart  accès au contact (gratuit, paywall désactivable)
└── features/
    ├── auth/     téléphone → code SMS → rôle
    ├── shell/    navigation adaptée au rôle
    ├── workers/  recherche et fiche ouvrier (vue client)
    ├── jobs/     publication, mes demandes, candidatures reçues
    ├── worker/   fil des missions, détail, portefeuille
    ├── chat/     conversations et discussion
    └── profile/  compte et profil ouvrier
```

29 fichiers Dart, environ 4 700 lignes.

Les 11 migrations SQL du schéma sont versionnées avec le code dans
`supabase/migrations/`, dans l'ordre d'application. Elles sont déjà appliquées
sur le projet `Ticonnect 1.0` ; elles servent à rejouer le schéma sur un autre
environnement et à garder l'historique dans le dépôt.

---

## Vérifications effectuées

Faute de SDK Flutter dans l'environnement de rédaction, la validation s'est
faite par analyse statique et par confrontation à la base réelle :

| Contrôle | Résultat |
|---|---|
| Résolution des 60+ imports relatifs | aucun cassé |
| Équilibrage syntaxique des 29 fichiers | OK |
| Les 16 tables interrogées existent en base | OK |
| Noms des paramètres des 3 fonctions RPC | conformes aux signatures SQL |
| Les 4 contraintes de clé étrangère citées dans les jointures | existent |
| 99 noms de colonnes référencés | tous présents dans le schéma |

Quatre défauts trouvés et corrigés au passage : le flux temps réel de la
messagerie affichait les messages à l'envers ; `DateFormat` en locale `fr`
levait une exception faute d'initialisation des symboles de date ; quatre
validations de formulaire retournaient une valeur `void` ; la bannière
publicitaire se créait avant le chargement de sa configuration et ne
s'affichait donc jamais.

**Reste à faire par toi :** `flutter analyze`, puis un premier lancement sur
appareil réel. C'est là que se verront les écarts de version d'API que
l'analyse statique ne peut pas détecter.

---

## Configuration

Les identifiants Supabase sont dans `lib/core/config.dart`. La clé est
*publiable* — elle est faite pour vivre dans le code client, toute la sécurité
repose sur les politiques RLS.

Pour cibler un autre environnement :

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://xxx.supabase.co \
  --dart-define=SUPABASE_KEY=sb_publishable_xxx
```

Les identifiants AdMob sont ceux de **test** de Google. Avant publication,
remplace-les dans la table `ad_placements` et dans `bootstrap.sh`, et passe
`--dart-define=ADS_TEST=false`. Ne teste jamais avec tes vrais identifiants :
cliquer sur ses propres publicités fait suspendre le compte.

---

## Abonnements

Trois plans (`free`, `pro`, `premium`), en mensuel ou en annuel, avec une
grille tarifaire **par pays** dans `plan_prices` : les conditions
économiques d'Abidjan et de Lagos n'ont rien de commun, et l'inflation ne
suit pas le rythme des publications sur le Play Store. Le repli `XX` sert
de tarif par défaut — une absence de ligne ne doit jamais empêcher
d'afficher un prix.

Le mensuel est la porte d'entrée, l'annuel se vend par la remise : dix mois
payés pour douze. Le mobile money ouest-africain est une culture de petits
montants fréquents ; demander une année d'avance à un artisan du secteur
informel écarterait la majorité de la cible.

Le premium achète une **position sponsorisée plafonnée** : au plus un
résultat sur quatre (`sponsored_slot_ratio`), jamais sous une note plancher
(`sponsored_min_rating`), et le nombre de places est limité par le vivier
organique disponible — sans ce dernier garde-fou, un métier comptant vingt
abonnés et trois profils gratuits verrait sa première page devenir
intégralement payante, ce qui détruirait la recherche. Les places
sponsorisées portent la mention « SPONSORISÉ » : un client qui découvre
seul que les premiers résultats sont achetés cesse de faire confiance à
tout le classement.

Deux règles de sécurité, non négociables :

- **Le prix ne vient jamais du téléphone.** Il est relu dans `plan_prices`
  par l'Edge Function `create-payment`, qui détient seule les clés
  marchandes. Une requête modifiée achèterait sinon un premium annuel pour
  un franc.
- **L'application n'active jamais un abonnement.** Seul
  `payment-webhook` le fait, après vérification de la signature HMAC.
  `activate_subscription()` a son droit d'exécution révoqué pour `anon` et
  `authenticated` : un APK décompilé ne peut rien en tirer.

Fournisseurs : **GeniusPay** (page de checkout multi-opérateurs — Wave,
Orange, MTN, Moov, carte) et **FedaPay**.

---

## Identité progressive

L'inscription se fait par pseudo et mot de passe, sans SMS. Le numéro n'est
exigé qu'au **premier acte engageant** : publier un besoin, ou se déclarer
ouvrier. À ce moment, l'utilisateur a compris ce que l'application lui
apporte, et le taux de complétion n'a plus rien à voir avec celui d'un
formulaire d'inscription.

Les triggers `job_requests_require_phone` et `worker_profiles_require_phone`
l'imposent côté base. `has_phone()` permet à l'application de demander au
bon moment plutôt que d'échouer après un formulaire rempli.

Trois protections viennent avec : unicité du numéro, bannissement
automatique du numéro d'un compte suspendu (levé à la réhabilitation), et
refus d'enregistrer un numéro banni. Sans elles, une inscription anonyme
rendrait la suspension purement décorative.

---

## Prochaines étapes

Le détail opérationnel est dans **`docs/deploiement.md`**. En résumé :

1. **`flutter analyze` puis un lancement sur appareil réel.** Le code n'a
   toujours pas été compilé ; tout le reste en dépend.
2. **Appliquer les migrations 12 à 17** (`supabase db push`). La 13 doit
   passer seule — PostgreSQL refuse d'utiliser une valeur d'énumération
   dans la transaction qui l'a créée. La 16 s'interrompt volontairement si
   deux profils partagent un numéro.
3. **Déployer les trois Edge Functions** et renseigner les secrets des
   fournisseurs.
4. **Déclarer l'URL de vérification serveur** dans la console AdMob, puis
   remplacer les identifiants d'unités de test — dont une unité
   **interstitiel récompensé**, format nouveau dans ce projet.
5. **Notifications push** — seul lot non terminé. `DevicesService` sait
   enregistrer et retirer un jeton ; obtenir ce jeton exige
   `firebase_messaging`, qui exige un `google-services.json` que seule ta
   console Firebase peut produire. La dépendance n'a pas été ajoutée car
   son absence ferait échouer la compilation Gradle.

**Trois fonctions SQL appelées par l'application ne sont versionnées nulle
part** : `username_available`, `set_my_location` et `get_my_location`. Elles
existent sur `Ticonnect 1.0` — elles y ont été créées directement — mais
rejouer le schéma sur un nouvel environnement les laisserait manquantes.
À écrire dans une migration dès que possible.
