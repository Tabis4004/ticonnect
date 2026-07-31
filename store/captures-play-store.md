# TiConnect — plan de captures pour la fiche Play Store

8 captures téléphone + 8 captures tablette, construites à partir des écrans réellement
présents dans `lib/features/`. Chaque ligne indique l'écran source, l'état à préparer
avant la capture, et la légende à incruster.

Charte : vert `#1B5E3F` (primaire), orange `#F2A03D` (accent), fond `#F7F8F7`.

---

## Spécifications Play Console

| | Téléphone | Tablette 7" | Tablette 10" |
|---|---|---|---|
| Taille recommandée | 1080 × 1920 | 1200 × 1920 | 1600 × 2560 |
| Nombre | 2 à 8 | jusqu'à 8 | jusqu'à 8 |
| Format | PNG 24 bits ou JPEG, **sans canal alpha**, 8 Mo max | idem | idem |
| Contrainte | chaque côté entre 320 et 3840 px ; le grand côté ≤ 2× le petit | idem | idem |

Les trois premières captures sont les seules visibles sans défilement sur la fiche :
elles doivent porter la proposition de valeur, pas une fonctionnalité secondaire.

---

## Téléphone — 1080 × 1920 (portrait)

L'ordre suit le parcours client (audience la plus large) puis bascule côté ouvrier.

| # | Écran source | État à préparer | Légende |
|---|---|---|---|
| 1 | `workers/worker_search_page.dart` | 5–6 résultats, métiers variés, photos réelles, filtre ville visible | **Trouvez l'ouvrier qu'il vous faut, près de chez vous** |
| 2 | `workers/worker_detail_page.dart` | Profil complet : photo, métier, note, tarif, bouton de contact | **Compétences, avis, tarifs : tout est visible avant de contacter** |
| 3 | `jobs/job_create_page.dart` | Formulaire à moitié rempli, exemple concret (« Réfection toiture, Lomé ») | **Publiez votre besoin en deux minutes** |
| 4 | `jobs/job_applications_page.dart` | 3–4 candidatures avec notes différentes | **Comparez les candidatures, choisissez en confiance** |
| 5 | `chat/chat_page.dart` | Conversation courte et crédible, 4–5 bulles, horodatage récent | **Échangez directement, sans intermédiaire** |
| 6 | `worker/job_feed_page.dart` | Fil rempli, distances affichées, badge « nouveau » | **Ouvriers : les missions près de vous, en temps réel** |
| 7 | `worker/wallet_page.dart` | Solde non nul, 3–4 opérations, montants réalistes en FCFA | **Suivez vos gains et vos paiements** |
| 8 | `profile/profile_page.dart` | Profil vérifié, badge de validation, note moyenne | **Un profil vérifié qui inspire confiance** |

### Variante à tester
Si tu veux mesurer l'effet du cadrage, garde les mêmes écrans mais inverse 1 et 6 :
une fiche qui s'ouvre côté ouvrier (« Trouvez des missions ») ne recrute pas la même
audience qu'une fiche côté client. Play Console permet de tester les deux via les
expériences de fiche Store.

---

## Tablette — 1600 × 2560 (10") et 1200 × 1920 (7")

| # | Écran source | Mise en page attendue | Légende |
|---|---|---|---|
| 1 | `worker_search_page` + `worker_detail_page` | Deux panneaux : liste à gauche, profil à droite | **Toute la recherche sur un seul écran** |
| 2 | `worker_search_page` | Grille de cartes, 2 à 3 colonnes | **Des dizaines de profils d'un coup d'œil** |
| 3 | `jobs/my_jobs_page` + `job_applications_page` | Demandes à gauche, candidatures à droite | **Vos demandes et leurs réponses, côte à côte** |
| 4 | `jobs/job_create_page` | Formulaire large, champs sur deux colonnes | **Décrivez votre chantier en détail** |
| 5 | `chat/chat_pages` + `chat_page` | Liste des conversations + fil ouvert | **Toutes vos discussions au même endroit** |
| 6 | `worker/job_feed_page` + `job_detail_page` | Fil à gauche, mission détaillée à droite | **Repérez et acceptez une mission sans quitter la liste** |
| 7 | `worker/wallet_page` | Tableau des opérations, en pleine largeur | **Une comptabilité claire de votre activité** |
| 8 | `worker/notifications_page` | Liste dense, plusieurs types de notifications | **Ne manquez aucune opportunité** |

---

## Décision retenue : téléphone uniquement

Les captures tablette sont reportées (voir la section suivante). La fiche part avec les
8 captures téléphone, ce qui est conforme : Play Console exige 2 captures minimum et les
captures tablette sont facultatives.

Faute d'émulateur disponible, les 8 écrans sont pour l'instant des **maquettes**
reconstruites d'après le code Dart par `render_screens.py` : structures de `WorkerCard`
et `RatingStars` (`lib/widgets/common.dart`), libellés réels des `AppBar` et des champs,
catégories issues de la table `trade_categories`, formats de prix, distance et temps
relatif repris de `Fmt`. Elles sont à remplacer par de vraies captures dès qu'un
appareil ou un émulateur est disponible — une fiche dont les visuels divergent de
l'application peut être suspendue.

```bash
python3 render_screens.py     # maquettes -> raw/tel-01..08.png
```

Les 8 gabarits sont générés par `make_store_shots.py` :

```bash
cd ~/Documents/ticonnect/store
python3 -m pip install pillow --break-system-packages   # si besoin
python3 make_store_shots.py --src raw --out out
```

Dépose les captures brutes dans `store/raw/` sous les noms `tel-01.png` … `tel-08.png`
(l'ordre suit le tableau ci-dessus) et relance. Toute capture absente est remplacée par
un placeholder, ce qui permet de valider la maquette avant d'avoir l'app sous la main —
c'est ce que montre `apercus/planche-contact.png`.

Les légendes se modifient dans la liste `CAPTIONS` en tête du script.

## Le point à vérifier avant de produire les captures tablette

Les huit propositions ci-dessus supposent une mise en page adaptative (deux panneaux
au-delà d'un certain seuil de largeur). Si `ticonnect` ne fait qu'étirer la mise en page
téléphone, les captures montreront des colonnes de texte très larges et des zones vides :
Google le signale comme un défaut d'adaptation grand écran, et cela pénalise la
visibilité de l'app sur tablettes et Chromebooks.

Vérifie en lançant l'app sur un AVD tablette. Si la mise en page n'est pas adaptée, deux
options : livrer d'abord les 8 captures téléphone seules (les captures tablette sont
facultatives), ou introduire un point de rupture avec `LayoutBuilder` sur les trois
parcours à deux panneaux (recherche, messagerie, fil de missions) avant de capturer.

---

## Produire les fichiers

```bash
# Émulateur téléphone 1080×1920
flutter emulators --launch <avd_phone>
flutter run --release
adb exec-out screencap -p > tel-01.png

# Émulateur tablette : créer un AVD au profil « Pixel Tablet » puis
adb exec-out screencap -p > tab-01.png

# Vérifier l'absence de canal alpha (Play refuse les PNG transparents)
sips -s format png --deleteColorManagementProperties tel-01.png
python3 -c "from PIL import Image; print(Image.open('tel-01.png').mode)"   # doit afficher RGB, pas RGBA
```

Les légendes s'incrustent ensuite dans un cadre marketing (appareil + bandeau de texte).
C'est autorisé et c'est la pratique dominante, à condition que la capture reste
représentative de l'application réelle : une fiche qui montre des écrans inexistants
peut être suspendue.

## Contenu des captures

Utilise des données de démonstration cohérentes et anonymes : pas de vrais numéros de
téléphone, pas de photos de personnes réelles sans autorisation écrite, pas de montants
qui laisseraient croire à des revenus garantis. Des noms plausibles et des métiers réels
(maçon, électricien, plombier, menuisier) suffisent à rendre les écrans crédibles.
