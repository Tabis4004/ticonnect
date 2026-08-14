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

# Mode publicitaire, annoncé à l'écran plutôt que deviné.
#
# Le script ne passait aucun --dart-define, donc ADS_TEST valait toujours
# `true` — et rien ne le disait. On y a perdu du temps : les visionnages
# s'enregistraient, aucune récompense n'arrivait, et la cause était
# simplement que l'application tournait sur les unités de démonstration
# de Google, auxquelles aucune vérification serveur ne peut être attachée.
#
#   ./build_apk.sh              -> unités de démonstration (défaut, sûr)
#   ADS_TEST=false ./build_apk.sh -> vraies unités de ton compte AdMob
ADS_TEST="${ADS_TEST:-true}"

echo "==> Compilation"
if [ "$ADS_TEST" = "false" ]; then
  echo "    PUBLICITÉS RÉELLES — unités de ton compte AdMob."
  echo "    Ne clique sur une annonce que depuis un appareil enrôlé"
  echo "    dans app_settings.ad_test_device_ids."
else
  echo "    Publicités de TEST — unités de démonstration Google."
  echo "    Aucune vérification serveur ne peut aboutir dans ce mode."
fi
flutter build apk --release --dart-define=ADS_TEST="$ADS_TEST"

SUFFIXE=$([ "$ADS_TEST" = "false" ] && echo "-prod" || echo "-test")
DEST="$HOME/Desktop/ticonnect-$(date +%Y%m%d-%H%M)$SUFFIXE.apk"
cp build/app/outputs/flutter-apk/app-release.apk "$DEST"

echo
echo "APK prêt : $DEST"
du -h "$DEST" | cut -f1 | sed 's/^/Taille : /'
