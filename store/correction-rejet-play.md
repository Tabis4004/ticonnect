# Rejet « Misleading Claims » — audit et correction

Google reproche deux choses : la description annonce des fonctionnalités
absentes, et les captures montrent des fonctionnalités absentes. Les deux
griefs sont fondés. Ce document confronte chaque promesse au code et aux
données réelles, puis propose une description qui ne promet que ce que
l'application fait aujourd'hui.

---

## 1. Pourquoi les captures ont été refusées

`store/render_screens.py` porte cet avertissement dans son propre en-tête :

> Ce ne sont pas des captures : à remplacer par de vraies captures dès
> qu'un émulateur est disponible.

Les huit images déposées sont des **maquettes reconstruites d'après le code
Dart**, pas des captures de l'application. Elles représentent des états que
l'application ne peut pas produire en l'état :

| Capture | Ce qu'elle montre | Ce que l'application produit |
|---|---|---|
| 1 | 5–6 résultats, filtre ville | **1 ouvrier** listé en base |
| 2 | Note, avis, tarif | **0 avis**, tarif sur 2 profils |
| 6 | Distances, badge « nouveau » | aucune distance, pas de badge |
| 6 | « en temps réel » | aucune notification push |
| 7 | Solde non nul, opérations | solde à 0, aucun mouvement |
| 8 | Badge de validation | aucun profil vérifié |

Une maquette n'est pas interdite en soi ; montrer une fonctionnalité qui
n'existe pas l'est.

---

## 2. Les promesses de la description, une par une

Vérifié le 5 août 2026 contre `lib/` et la base de production.

| Promesse | Code | Donnée | Verdict |
|---|---|---|---|
| Recherche par métier et par catégorie | présent | 1 ouvrier, 1 métier | **tenable** |
| Filtre sur les ouvriers disponibles | présent | — | **tenable** |
| Fiche : métier, expérience, tarifs, note, missions | présent | 0 mission, 0 avis | **tenable** — un compteur à zéro reste une fonctionnalité |
| « avis des clients précédents » | présent | **0 avis** | tenable, mais indémontrable pour un testeur |
| « Les profils sont classés par proximité : vous voyez la distance » | présent | **0 zone de service** → `distance_km` toujours nul | **NON TENABLE** — la distance ne s'affiche jamais |
| Déblocage gratuit du numéro | présent | `unlock_cost = 0` | **tenable** |
| Appel, WhatsApp, messagerie interne | présent | — | **tenable** |
| Publication d'une demande | présent | 6 demandes | **tenable** |
| « Les ouvriers concernés **reçoivent** votre demande » | **aucun paquet de notification dans `pubspec.yaml`** | — | **NON TENABLE** — rien n'est envoyé ; l'ouvrier doit ouvrir l'écran « Alertes » |
| Comparaison des candidatures | présent | 1 candidature | **tenable** |
| Notation après la mission | présent | 0 avis | **tenable** |

### Les deux ruptures

**La notification.** Le verbe « reçoivent » annonce une notification. Il
n'existe aucune intégration push : ni `firebase_messaging`, ni
`flutter_local_notifications`. La table `notifications` et l'écran
« Alertes » existent, mais le fonctionnement est passif — l'ouvrier
consulte, rien ne le prévient. C'est le grief le plus net.

**La distance.** `search_workers` calcule bien `distance_km`, et
`WorkerCard` sait l'afficher. Mais le calcul part de `worker_service_areas`,
table **vide** : aucun ouvrier n'a déclaré de zone d'intervention. La valeur
est donc systématiquement nulle et le libellé n'apparaît jamais. La
fonctionnalité est écrite, elle n'est pas opérante.

---

## 3. Description corrigée

Reformulée pour ne décrire que le comportement observable. Les seuls
changements de fond portent sur la notification et la proximité.

```
VOUS CHERCHEZ UN OUVRIER

• Recherchez par métier ou par catégorie, et filtrez sur les ouvriers
  disponibles.
• Chaque profil affiche l'essentiel avant tout contact : métier,
  expérience, fourchette de tarifs à l'heure, à la journée ou au forfait,
  note moyenne, avis reçus et nombre de missions réalisées.
• Le numéro de téléphone se débloque gratuitement, sans abonnement ni
  frais cachés. Appelez, écrivez sur WhatsApp, ou passez par la
  messagerie de l'application.

VOUS PRÉFÉREZ QU'ON VIENNE À VOUS

• Publiez votre demande en quelques minutes : métier recherché,
  description du chantier, ville et quartier, budget indicatif, degré
  d'urgence.
• Votre demande apparaît dans le fil des ouvriers du métier concerné,
  qui peuvent y répondre.
• Comparez les candidatures au même endroit : profil, note, avis, prix
  proposé.
• Choisissez, échangez, puis notez l'ouvrier une fois la mission
  terminée. Vos avis alimentent la réputation de tout le monde.

VOUS ÊTES OUVRIER

• Créez votre profil : métiers, années d'expérience, tarifs,
  disponibilité.
• Consultez les demandes publiées et candidatez avec un message et un
  prix.
• Regardez une courte vidéo pour remonter dans les résultats de
  recherche pendant quelques heures. Gratuit, sans abonnement.

Ticonnect est gratuit pour les clients comme pour les ouvriers. Aucune
commission n'est prélevée sur votre travail.
```

**Ce qui a changé et pourquoi**

- « Les ouvriers reçoivent votre demande » → « Votre demande apparaît dans
  le fil des ouvriers ». Décrit exactement le mécanisme réel.
- « Les profils sont classés par proximité : vous voyez la distance » →
  supprimé. À rétablir mot pour mot le jour où les ouvriers déclarent une
  zone d'intervention.
- « avis des clients précédents » → « avis reçus ». Même fonctionnalité,
  formulation qui ne suppose pas un historique.
- Ajout du volet ouvrier, absent de la description alors que c'est la
  moitié de l'application — et que le testeur y arrive s'il choisit
  « Trouver du travail » à l'inscription.

---

## 4. Avant de renvoyer en révision

**Refaire les captures depuis l'application réelle.** La procédure est déjà
écrite dans `captures-play-store.md` :

```
adb exec-out screencap -p > tel-01.png
sips -s format png --deleteColorManagementProperties tel-01.png
```

Le canal alpha doit disparaître, sinon la Play Console refuse le fichier.

**Peupler la base avant de capturer.** Un testeur qui ouvre l'application
voit aujourd'hui un seul ouvrier, aucun avis, aucune mission terminée. Ce
n'est pas une violation en soi, mais c'est ce qui rend toute capture riche
« non conforme à l'application ». Il faut soit des comptes de démonstration
crédibles, soit des captures assumant la sobriété d'un service qui démarre.

**Fournir un compte de test à Google.** Play Console, *Contenu de
l'application → Accès à l'application*. Sans identifiants, le testeur reste
bloqué à l'inscription et juge sur les seules captures — ce qui explique
peut-être la sévérité du verdict.

**Ne pas faire appel.** Les deux griefs sont exacts. Un appel rejeté allonge
le délai et fragilise le compte.
