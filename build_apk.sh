#!/usr/bin/env bash
# Compile l'APK et le dépose sur le Bureau.
#
# Aucun --dart-define-from-file ici, volontairement : dev.json contient le
# mot de passe administrateur, et tout ce qu'on passe en --dart-define finit
# en clair dans l'APK, lisible par quiconque le décompresse. L'URL et la clé
# anon suffisent, elles sont déjà les valeurs par défaut de config.dart.
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f android/key.properties ] || \
   diff -q android/key.properties android/key.properties.example >/dev/null 2>&1; then
  echo "android/key.properties n'est pas renseigné." >&2
  echo "Lance d'abord : ./set_keystore_password.sh" >&2
  exit 1
fi

echo "==> Nettoyage (obligatoire après le changement de nom de package)"
flutter clean

echo "==> Dépendances"
flutter pub get

echo "==> Compilation"
flutter build apk --release

DEST="$HOME/Desktop/ticonnect-$(date +%Y%m%d-%H%M).apk"
cp build/app/outputs/flutter-apk/app-release.apk "$DEST"

echo
echo "APK prêt : $DEST"
du -h "$DEST" | cut -f1 | sed 's/^/Taille : /'
