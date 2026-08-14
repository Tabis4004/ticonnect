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
# Même logique que build_apk.sh : le mode publicitaire s'annonce, il ne
# se devine pas. Un bundle déposé sur la Play Console avec les unités de
# démonstration ne rapporterait rien, sans que rien ne le signale.
ADS_TEST="${ADS_TEST:-true}"
if [ "$ADS_TEST" = "false" ]; then
  echo "    PUBLICITÉS RÉELLES — unités de ton compte AdMob."
else
  echo "    Publicités de TEST — à ne pas déposer sur la Play Console."
fi
flutter build appbundle --release --dart-define=ADS_TEST="$ADS_TEST"

# La version dans le nom du fichier : la Play Console refuse un versionCode
# déjà utilisé, et plusieurs bundles sur le Bureau sont vite indiscernables.
VERSION="$(sed -n 's/^version: *//p' pubspec.yaml | tr '+' '-')"
DEST="$HOME/Desktop/ticonnect-$VERSION-$(date +%Y%m%d-%H%M).aab"
cp build/app/outputs/bundle/release/app-release.aab "$DEST"

echo
echo "Bundle prêt : $DEST"
du -h "$DEST" | cut -f1 | sed 's/^/Taille : /'
echo
echo "Play Console → Production → Créer une release → importer ce fichier."
