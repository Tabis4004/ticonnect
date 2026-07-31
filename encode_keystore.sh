#!/usr/bin/env bash
# Prépare les secrets GitHub à partir du keystore local.
#
# GitHub Actions ne stocke que du texte : le .jks doit donc être encodé
# en base64. Ce script produit la valeur à coller, sans jamais afficher
# le moindre mot de passe à l'écran ni les laisser dans l'historique du
# shell.
#
# La valeur base64 est placée dans le presse-papiers, pas dans un
# fichier : un fichier oublié dans le dossier finirait par être committé
# un jour, et le dépôt est public.
set -euo pipefail
cd "$(dirname "$0")"

KEYSTORE="${1:-$HOME/upload-keystore-ticonnect.jks}"

if [ ! -f "$KEYSTORE" ]; then
  echo "Keystore introuvable : $KEYSTORE" >&2
  echo "Usage : ./encode_keystore.sh [chemin/vers/keystore.jks]" >&2
  exit 1
fi

# -w0 sur GNU, absent sur macOS où base64 ne coupe pas les lignes par
# défaut. Un retour à la ligne au milieu du secret le rendrait invalide.
if base64 --help 2>&1 | grep -q -- '-w'; then
  B64=$(base64 -w0 "$KEYSTORE")
else
  B64=$(base64 < "$KEYSTORE" | tr -d '\n')
fi

if command -v pbcopy >/dev/null 2>&1; then
  printf '%s' "$B64" | pbcopy
  COPIED="La valeur est dans ton presse-papiers."
else
  COPIED="Copie la ligne ci-dessous (sans espace ni retour à la ligne) :
$B64"
fi

# `keytool -list` réclame le mot de passe du keystore et attend sur
# l'entrée standard. Avec stderr masqué, l'invite est invisible et le
# script paraît figé — c'est exactement ce qui s'est produit.
#
# Ce script ne demande aucun mot de passe, et n'a pas à en demander : son
# seul travail est d'encoder un fichier. On redirige donc l'entrée depuis
# /dev/null pour que keytool renonce immédiatement, et l'alias retombe
# sur la valeur usuelle si la lecture échoue.
ALIAS=$(keytool -list -keystore "$KEYSTORE" </dev/null 2>/dev/null \
        | awk -F', ' '/PrivateKeyEntry|Entrée de type/ {print $1; exit}' || true)

cat <<EOF

Secrets à créer sur GitHub
  Settings > Secrets and variables > Actions > New repository secret

  ANDROID_KEYSTORE_BASE64    $COPIED
  ANDROID_KEYSTORE_PASSWORD  le mot de passe du keystore
  ANDROID_KEY_PASSWORD       le mot de passe de la clé
  ANDROID_KEY_ALIAS          ${ALIAS:-upload}
  ADMOB_APP_ID               facultatif, quand tu auras le vrai App ID

Le workflow se lance ensuite depuis l'onglet Actions
(« Build Android signé » > Run workflow), ou automatiquement en
poussant une étiquette :

  git tag v$(sed -n 's/^version: *//p' pubspec.yaml | cut -d+ -f1) && git push --tags

EOF
