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
Le revenu repose entièrement sur la publicité.

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

### Le point bloquant à traiter

Le chemin « vidéo récompensée » **ne peut pas encore accorder de crédit**.

`AdsService.showRewarded()` journalise l'impression, affiche la vidéo, puis
attend qu'AdMob confirme le visionnage via sa callback *Server-Side
Verification*. Tant que l'Edge Function `admob-ssv` n'est pas déployée, cette
attente expire et la méthode rend `null`.

C'est délibéré. La politique RLS interdit au téléphone d'écrire
`ssv_verified` ou `reward_credits` : sans vérification serveur, une version
modifiée de l'app se créditerait à l'infini. Mieux vaut ne rien accorder que
d'accorder l'invérifiable.

Ce qui fonctionne en attendant : le quota de 3 déverrouillages offerts, et les
crédits accordés manuellement en base.

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

## Prochaines étapes

1. **Edge Function `admob-ssv`** — vérifier la signature de la callback AdMob
   avec la clé publique Google, marquer `ssv_verified`, créditer via
   `adjust_credits()`. Sans elle, la vidéo récompensée ne rapporte rien.
2. **Activer l'authentification par SMS** dans Supabase (Auth → Providers →
   Phone) avec un fournisseur SMS. Sans ça, aucune connexion n'est possible.
3. **Buckets Storage** — `avatars`, `portfolio`, `job-photos` publics,
   `id-documents` privé. Les photos de mission sont prévues dans le schéma
   mais l'écran de publication ne les envoie pas encore.
4. **Paiement Mobile Money** — CinetPay ou PayDunya, plus l'Edge Function de
   callback. Le bouton existe déjà et affiche « bientôt disponible ».
5. **Notifications push** — la table `devices` attend les jetons FCM.
