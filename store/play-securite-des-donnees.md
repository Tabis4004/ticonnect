# Formulaire « Sécurité des données » — réponses pour Ticonnect

Établi le 14 août 2026, à partir du code et du schéma de la base, non
d'un modèle générique. Chaque ligne est vérifiable : la colonne qui la
justifie est nommée.

**Ce formulaire n'est pas déclaratif au sens faible.** Google compare vos
réponses au comportement réel de l'application, décompilée et exécutée.
Une donnée collectée mais non déclarée est un motif de retrait, pas de
simple rejet. Une donnée déclarée mais non collectée n'est qu'une
imprécision — en cas de doute, déclarer.

---

## Lien de suppression de compte

```
https://ticonnect.isidoretabati.workers.dev/suppression-compte.html
```

C'est le fichier `web/suppression-compte.html` du dépôt. `flutter build web`
recopie tout `web/` dans `build/web`, comme il le fait déjà pour
`app-ads.txt` — la page sera en ligne au prochain `./deploy.sh`, sans autre
manipulation.

**À faire avant de coller ce lien dans la Play Console :** lancer
`./deploy.sh`, puis ouvrir l'adresse dans un navigateur en navigation
privée. Google vérifie la page à la main. Un lien qui renvoie l'application
Flutter au lieu de la page — ce qui arriverait si le déploiement n'avait
pas eu lieu, la configuration Cloudflare renvoyant `index.html` pour toute
adresse inconnue — vaut un rejet avec le motif « invalid account deletion
link ».

L'exigence a deux volets, et Google vérifie les deux : la suppression doit
être possible **depuis l'application** et **depuis le web**. Le volet
applicatif est en place depuis le commit `77b29a0` : *Mon compte →
Supprimer mon compte*. Il faut donc publier cette version avant de
répondre au formulaire.

---

## Écran 1 — Collecte et partage

| Question | Réponse |
|---|---|
| L'appli collecte-t-elle des données utilisateur ? | **Oui** |
| Toutes les données sont-elles chiffrées en transit ? | **Oui** — Supabase et AdMob sont en HTTPS exclusivement, aucun appel en clair |
| Méthodes de création de compte | **Nom d'utilisateur et mot de passe** (seule case à cocher) |
| Lien de suppression de compte | l'adresse ci-dessus |

---

## Écran 2 — Types de données

Ce qui suit est la liste complète. Tout ce qui n'y figure pas doit rester
décoché.

### Informations personnelles

| Type | Collectée | Partagée | Obligatoire | Finalités |
|---|---|---|---|---|
| **Nom** — `profiles.full_name` | Oui | Non | Obligatoire | Fonctionnalité de l'appli · Gestion du compte |
| **Adresse e-mail** — `contact_details.email` | Oui | Non | Facultative | Fonctionnalité de l'appli |
| **ID utilisateur** — `profiles.username`, identifiant du compte | Oui | Non | Obligatoire | Fonctionnalité de l'appli · Gestion du compte |
| **Numéro de téléphone** — `contact_details.phone`, `whatsapp` | Oui | Non | Obligatoire | Fonctionnalité de l'appli · Gestion du compte |

Le téléphone se déclare **obligatoire** et non facultatif. Il n'est certes
demandé qu'au premier acte engageant — candidater, écrire, publier — mais
tout usage réel de l'application y conduit. Le déclarer facultatif serait
défendable sur le papier et faux en pratique.

*Ne pas cocher* : adresse postale, race et origine ethnique, opinions
politiques ou religieuses, orientation sexuelle, autres informations.

### Position

| Type | Collectée | Partagée | Obligatoire | Finalités |
|---|---|---|---|---|
| **Position approximative** — `profiles.city`, `neighborhood`, saisis par l'utilisateur | Oui | Non | Obligatoire | Fonctionnalité de l'appli |
| **Position précise** — GPS via `geolocator`, `profiles.location` | Oui | Non | Facultative | Fonctionnalité de l'appli |

La position précise est réellement facultative : `LocationService.current()`
rend `null` si l'autorisation est refusée, et rien dans l'application n'en
dépend. Elle ne sert qu'au tri par distance et peut être effacée depuis
*Mes coordonnées*.

### Messages

| Type | Collectée | Partagée | Obligatoire | Finalités |
|---|---|---|---|---|
| **Autres messages in-app** — `messages.body` | Oui | Non | Obligatoire | Fonctionnalité de l'appli |

*Ne pas cocher* : e-mails, SMS ou MMS.

### Activité dans l'appli

| Type | Collectée | Partagée | Obligatoire | Finalités |
|---|---|---|---|---|
| **Interactions dans l'appli** — `ad_impressions`, `job_requests.views_count` | Oui | Non | Obligatoire | Fonctionnalité de l'appli · Analyse · Publicité ou marketing |
| **Autre contenu généré par l'utilisateur** — descriptions de missions, avis, présentation du profil | Oui | Non | Obligatoire | Fonctionnalité de l'appli |

### Identifiants de l'appareil ou autres identifiants

| Type | Collectée | Partagée | Obligatoire | Finalités |
|---|---|---|---|---|
| **ID de l'appareil ou autres ID** — identifiant publicitaire lu par le SDK AdMob, `devices.fcm_token` | Oui | **Oui** | Obligatoire | Publicité ou marketing · Analyse · Prévention des fraudes et sécurité · Fonctionnalité de l'appli |

**C'est la seule ligne où « partagée » vaut Oui, et elle n'est pas
négociable.** Le SDK `google_mobile_ads` transmet l'identifiant publicitaire
à Google pour son propre compte. Google considère cela comme un partage,
même si vous n'envoyez rien vous-même. C'est l'omission la plus fréquente
et la plus facile à constater : il suffit d'exécuter l'application.

### Informations et performances de l'appli

| Type | Collectée | Partagée | Obligatoire | Finalités |
|---|---|---|---|---|
| **Autres données de performances** — `devices.app_version`, `device_model` | Oui | Non | Obligatoire | Fonctionnalité de l'appli |

Ces deux colonnes servent à savoir quelles versions sont encore en service.
Pas de journaux de plantage : ni Crashlytics ni équivalent n'est installé.

### Ce qui reste décoché

- **Informations financières** — aucun paiement n'existe dans l'application.
  Les tables `payments` et `subscriptions` sont présentes mais inertes, et
  le formulaire porte sur ce que l'application fait, pas sur ce que la base
  pourrait faire. **À rouvrir le jour où un paiement est activé.**
- **Photos et vidéos** — aucun téléversement n'est implémenté. `image_picker`
  figure dans `pubspec.yaml` mais n'est importé nulle part dans `lib/`.
  **À rouvrir le jour où l'envoi de photos est branché.**
- Santé et forme, contacts, calendrier, fichiers et documents, historique de
  recherche, applications installées, historique Web.

---

## Écran 3 — Pratiques de sécurité

| Question | Réponse |
|---|---|
| Les données sont-elles chiffrées en transit ? | Oui |
| Les utilisateurs peuvent-ils demander la suppression de leurs données ? | **Oui**, avec l'adresse ci-dessus |
| Engagement envers la Politique Familles de Play | Non concerné — l'application ne cible pas les enfants |
| Examen de sécurité indépendant | Non |

---

## Ce que le formulaire ne couvre pas, et qui doit figurer dans la politique de confidentialité

Le formulaire ne demande jamais qui, chez vous, peut lire les données. La
politique de confidentialité, elle, le doit — et c'est le point le plus
exposé du projet.

Trois phrases à y ajouter, sans euphémisme :

> L'administrateur de la plateforme peut consulter l'intégralité des
> messages échangés dans la messagerie interne, ainsi que les coordonnées
> des utilisateurs, afin de traiter les signalements et les litiges liés aux
> missions. Les échanges menés dans Ticonnect ne sont donc pas privés.
> Pour une conversation confidentielle, utilisez le téléphone ou WhatsApp.

Et la durée de conservation après suppression du compte, telle que la page
web l'annonce : historique partagé détaché de l'identité, numéros des
comptes suspendus conservés pour empêcher la recréation immédiate.

Une politique de confidentialité qui tait un accès administrateur que le
code accorde est un écart entre la déclaration et le comportement réel —
exactement ce que Google sanctionne, et exactement ce qui donne prise en
cas de plainte d'un utilisateur.
