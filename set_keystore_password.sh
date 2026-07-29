#!/usr/bin/env bash
# Renseigne android/key.properties avec le mot de passe du keystore.
#
# Le mot de passe est saisi à l'écran sans être affiché, écrit directement
# dans le fichier, et ne transite par aucun historique de commandes.
# android/key.properties est déjà dans .gitignore : il ne partira jamais
# dans le dépôt.
set -euo pipefail
cd "$(dirname "$0")"

KEYSTORE="$HOME/upload-keystore-ticonnect.jks"
ALIAS="upload"

if [ ! -f "$KEYSTORE" ]; then
  echo "Keystore introuvable : $KEYSTORE" >&2
  exit 1
fi

printf 'Mot de passe du keystore : '
read -rs STORE_PASS
echo

# Vérification avant d'écrire quoi que ce soit : inutile d'enregistrer
# un mot de passe faux et de relancer un build de trois minutes pour rien.
if ! keytool -list -keystore "$KEYSTORE" -storepass "$STORE_PASS" >/dev/null 2>&1; then
  echo "Mot de passe refusé par le keystore. Rien n'a été modifié." >&2
  exit 1
fi

printf 'Mot de passe de la clé "%s" (Entrée si identique) : ' "$ALIAS"
read -rs KEY_PASS
echo
KEY_PASS="${KEY_PASS:-$STORE_PASS}"

cat > android/key.properties <<PROPS
storePassword=$STORE_PASS
keyPassword=$KEY_PASS
keyAlias=$ALIAS
storeFile=$KEYSTORE
PROPS

chmod 600 android/key.properties
echo "android/key.properties écrit et vérifié."
echo "Tu peux lancer : ./build_apk.sh"
