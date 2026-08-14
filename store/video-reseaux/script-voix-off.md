# Ticonnect — vidéo réseaux sociaux

Format vertical 1080 × 1920, durée 24 s, sans musique. Voix off française,
grave et posée, débit lent — le silence entre les phrases fait autant que
les mots. Ne pas surjouer : le ton juste est celui d'un constat, pas d'une
réclame.

Chaque affirmation ci-dessous a été vérifiée contre le code et la base au
6 août 2026. Ne rien ajouter sans la même vérification : c'est une
promesse non tenue dans la description qui a valu le rejet de la fiche
Play, et une publicité mensongère se corrige moins facilement.

---

## Minutage

| Temps | Voix off | À l'image |
|---|---|---|
| 0:00 – 0:04 | « À Abidjan, à Lomé, un bon artisan se trouve encore de bouche à oreille. » | Logo sur fond vert foncé, puis fondu vers la recherche |
| 0:04 – 0:07 | « Ticonnect change ça. » | Écran de recherche, liste d'ouvriers qui défile lentement |
| 0:07 – 0:13 | « Publiez votre besoin. Les ouvriers du métier le voient, et se manifestent. » | Formulaire de publication, puis fil des missions côté ouvrier |
| 0:13 – 0:17 | « Vous comparez les propositions. Vous choisissez. » | Écran des candidatures, arrêt sur le bouton « Choisir » |
| 0:17 – 0:21 | « Vous êtes ouvrier ? Les chantiers près de chez vous, dans votre poche. » | Fil des missions disponibles |
| 0:21 – 0:24 | « Gratuit pour tous. Aucune commission. Sur Google Play. » | Logo, mention « Contient des annonces », badge Google Play |

Total : environ 60 mots. À ce débit, compter 24 s. Si l'enregistrement
dépasse 26 s, couper la première phrase plutôt que d'accélérer.

---

## Ce qui peut être dit, et ce qui ne peut pas

**Vérifié, dicible tel quel**

- Publication d'une demande avec métier, ville, budget, urgence.
- Les ouvriers du métier concerné voient la demande dans leur fil.
- Comparaison des candidatures : profil, note, prix proposé.
- Le client choisit ; l'ouvrier ne peut pas s'attribuer une mission.
- Contact gratuit : téléphone, WhatsApp, messagerie interne.
- Aucune commission sur le travail réalisé.
- Gratuit pour les clients comme pour les ouvriers.

**À ne pas dire**

- « Les ouvriers **reçoivent** votre demande » — la notification push
  existe côté serveur mais aucun appareil n'est encore enregistré. Dire
  « la voient dans leur fil » décrit ce qui se passe réellement.
- « Trouvez un ouvrier **près de chez vous** » avec une distance à
  l'écran — `worker_service_areas` est vide, la distance ne s'affiche
  jamais. La formule « les chantiers près de chez vous » reste acceptable
  côté ouvrier : le fil est bien filtré par ville.
- Toute mention d'achat de crédits, de Mobile Money ou d'abonnement —
  rien de tout cela n'existe dans l'application.
- Tout chiffre : nombre d'ouvriers, de missions, d'avis. L'annuaire
  compte un ouvrier visible.

---

## Captures à utiliser

Uniquement celles de la fiche Play publiée. **Pas** les fichiers de
`store/raw/` : ce sont les maquettes refusées par Google, elles affichent
des distances, des avis, des badges vérifiés et un écran d'achat de
crédits qui n'existent pas.

Pour recapturer proprement :

```bash
~/Library/Android/sdk/platform-tools/adb exec-out screencap -p > ecran-01.png
sips -s format png --deleteColorManagementProperties ecran-01.png
```

Déposer les fichiers dans `store/video-reseaux/captures/`, nommés
`ecran-01.png` à `ecran-06.png`, dans l'ordre du minutage ci-dessus.

---

## Montage

Une fois les captures en place, le montage est automatisable : fondus
enchaînés d'une seconde, léger zoom lent sur chaque écran, sous-titres
incrustés reprenant la voix off — **indispensables**, une large part des
vues sur les réseaux se fait sans le son.

La voix off s'ajoute en piste séparée, ce qui permet de la réenregistrer
sans refaire le montage.
