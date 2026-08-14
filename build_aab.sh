#!/usr/bin/env bash
# Compile l'Android App Bundle (format exigé par la Play Console)
# et le dépose sur le Bureau.
#
# Aucun --dart-define-from-file : dev.json contient le mot de passe
# administrateur, et tout --dart-define finit en clair dans le bundle,
# lisible par quiconque le décompresse.
set -euo pipefail
cd "$(dirname "$0")"

# Sans key.properties renseigné, Gradle échoue sur signReleaseBundle après
# plusieurs minutes de compilation. Autant le dire tout de suite.
if [ ! -f android/key.properties ] || \
   diff -q android/key.properties android/key.properties.example >/dev/null 2>&1; then
  echo "android/key.properties n'est pas renseigné." >&2
  echo "Lance d'abord : ./set_keystore_password.sh" >&2
  exit 1
fi

echo "==> Dépendances"
flutter pub get

echo "==> Compilation du bundle"
# Défaut VOLONTAIREMENT inverse de build_apk.sh.
#
# Un APK est un artefact de test : le mode démonstration y est le bon
# défaut, il protège le compte AdMob. Un AAB n'existe que pour être déposé
# sur la Play Console — un défaut en mode démonstration y est un piège
# silencieux. L'application fonctionne, les utilisateurs voient des
# annonces factices de Google, et rien ne rapporte sans qu'aucune erreur
# ne le signale. On peut le découvrir des semaines plus tard.
#
#   ./build_aab.sh               -> vraies unités, prêt à publier
#   ADS_TEST=true ./build_aab.sh -> démonstration, pour vérifier un parcours
ADS_TEST="${ADS_TEST:-false}"
if [ "$ADS_TEST" = "false" ]; then
  echo "    PUBLICITÉS RÉELLES — unités de ton compte AdMob."
  echo "    Bundle publiable."
else
  echo
  echo "    ⚠️  PUBLICITÉS DE DÉMONSTRATION"
  echo "    Ce bundle ne rapportera RIEN s'il est déposé sur la Play Console."
  echo "    Le fichier portera le suffixe -DEMO pour éviter la confusion."
  echo
  # Cinq secondes pour interrompre : le coût d'une erreur ici se compte en
  # semaines de revenu perdu, celui de l'attente en secondes.
  sleep 5
fi
flutter build appbundle --release --dart-define=ADS_TEST="$ADS_TEST"

# La version dans le nom du fichier : la Play Console refuse un versionCode
# déjà utilisé, et plusieurs bundles sur le Bureau sont vite indiscernables.
VERSION="$(sed -n 's/^version: *//p' pubspec.yaml | tr '+' '-')"
# Le suffixe rend l'erreur visible sur le Bureau. Deux bundles côte à côte
# étaient jusqu'ici indiscernables — c'est au moment de choisir lequel
# téléverser qu'on veut le savoir, pas après.
SUFFIXE=$([ "$ADS_TEST" = "false" ] && echo "" || echo "-DEMO-NE-PAS-PUBLIER")
DEST="$HOME/Desktop/ticonnect-$VERSION-$(date +%Y%m%d-%H%M)$SUFFIXE.aab"
cp build/app/outputs/bundle/release/app-release.aab "$DEST"

echo
echo "Bundle prêt : $DEST"
du -h "$DEST" | cut -f1 | sed 's/^/Taille : /'
echo
echo "Play Console → Production → Créer une release → importer ce fichier."
