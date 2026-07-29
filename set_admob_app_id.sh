#!/usr/bin/env bash
# Renseigne les App ID AdMob réels pour Android et iOS.
#
# Tant que ce script n'a pas été lancé, le projet compile avec les App ID de
# test publiés par Google : l'application démarre et peut être publiée, mais ne
# sert aucune vraie publicité. Aucune modification de code n'est nécessaire
# pour basculer en production, seulement ce script.
#
# Les fichiers écrits (android/admob.properties et
# ios/Flutter/AdmobLocal.xcconfig) sont dans .gitignore : les identifiants ne
# partent pas dans le dépôt public.
#
# Où trouver les App ID : console AdMob > Applications > Ticonnect >
# Paramètres de l'application. Une application « non listée sur un store »
# suffit pour en obtenir un ; la publication sur le Play Store n'est pas un
# prérequis. AdMob crée une fiche distincte par plateforme, donc deux App ID
# différents.
set -euo pipefail
cd "$(dirname "$0")"

ANDROID_FILE="android/admob.properties"
IOS_FILE="ios/Flutter/AdmobLocal.xcconfig"

# Le SDK refuse tout ID mal formé en faisant planter l'application au
# démarrage, avant le premier écran. Autant le détecter ici plutôt qu'après
# un build de plusieurs minutes.
valid_app_id() {
  [[ "$1" =~ ^ca-app-pub-[0-9]{16}~[0-9]{10}$ ]]
}

# Une saisie vide laisse la plateforme sur l'App ID de test : utile pour ne
# configurer qu'Android d'abord, puis revenir pour iOS.
read_app_id() {
  local platform="$1" answer
  while true; do
    printf 'App ID AdMob %s (Entrée pour laisser en mode test) : ' "$platform" >&2
    read -r answer
    if [ -z "$answer" ] || valid_app_id "$answer"; then
      printf '%s' "$answer"
      return
    fi
    echo "Format attendu : ca-app-pub-<16 chiffres>~<10 chiffres>. Réessaie." >&2
  done
}

ANDROID_ID="$(read_app_id Android)"
IOS_ID="$(read_app_id iOS)"

if [ -z "$ANDROID_ID" ] && [ -z "$IOS_ID" ]; then
  echo "Aucun App ID saisi. Rien n'a été modifié." >&2
  exit 1
fi

# Les deux plateformes partagent un compte AdMob mais pas une fiche : un même
# ID des deux côtés est presque toujours un copier-coller involontaire.
if [ -n "$ANDROID_ID" ] && [ "$ANDROID_ID" = "$IOS_ID" ]; then
  echo "Android et iOS ont le même App ID : AdMob en génère un par plateforme." >&2
  echo "Vérifie la console avant de relancer. Rien n'a été modifié." >&2
  exit 1
fi

if [ -n "$ANDROID_ID" ]; then
  printf 'admobAppId=%s\n' "$ANDROID_ID" > "$ANDROID_FILE"
  echo "Écrit : $ANDROID_FILE"
fi

if [ -n "$IOS_ID" ]; then
  printf 'ADMOB_APP_ID=%s\n' "$IOS_ID" > "$IOS_FILE"
  echo "Écrit : $IOS_FILE"
fi

echo
echo "Pense à passer les unités publicitaires en production :"
echo "  - lib/services/ads_service.dart (identifiants d'unités)"
echo "  - build avec --dart-define=ADS_TEST=false"
