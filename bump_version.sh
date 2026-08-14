#!/usr/bin/env bash
# Incrémente la version de l'application dans pubspec.yaml.
#
# Deux nombres, deux rôles distincts :
#
#   version: 2.0.5+7
#            ^^^^^ ^
#            |     versionCode — un entier que la Play Console exige
#            |     STRICTEMENT croissant. Le réutiliser fait rejeter le
#            |     dépôt. C'est la seule cause de rejet purement mécanique.
#            versionName — ce que l'utilisateur lit sur la fiche.
#
# Le versionCode monte à chaque appel, quel que soit le mode. On ne dépose
# jamais deux bundles avec le même, même pour corriger un oubli de drapeau.
#
#   ./bump_version.sh          -> 2.0.5+7  devient 2.0.6+8   (correctif)
#   ./bump_version.sh minor    -> 2.0.5+7  devient 2.1.0+8   (nouveautés)
#   ./bump_version.sh major    -> 2.0.5+7  devient 3.0.0+8   (refonte)
#   ./bump_version.sh build    -> 2.0.5+7  devient 2.0.5+8   (rebuild seul)
#   ./bump_version.sh 2.1.3    -> 2.1.3+8                    (version imposée)
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-patch}"

ACTUEL="$(sed -n 's/^version: *//p' pubspec.yaml | tr -d '[:space:]')"
if [ -z "$ACTUEL" ]; then
  echo "Aucune ligne 'version:' dans pubspec.yaml." >&2
  exit 1
fi

NOM="${ACTUEL%%+*}"
CODE="${ACTUEL##*+}"

# Sans '+' dans pubspec.yaml il n'y a pas de versionCode : Flutter en
# fabrique un implicite et la Play Console finit par refuser le dépôt sans
# que la cause soit lisible. Autant s'arrêter ici.
if [ "$NOM" = "$CODE" ]; then
  echo "La version '$ACTUEL' n'a pas de versionCode (partie après '+')." >&2
  echo "Corrige pubspec.yaml en 'version: $NOM+1' puis relance." >&2
  exit 1
fi

IFS=. read -r MAJ MIN PAT <<< "$NOM"
NOUVEAU_CODE=$((CODE + 1))

case "$MODE" in
  patch) NOUVEAU_NOM="$MAJ.$MIN.$((PAT + 1))" ;;
  minor) NOUVEAU_NOM="$MAJ.$((MIN + 1)).0" ;;
  major) NOUVEAU_NOM="$((MAJ + 1)).0.0" ;;
  build) NOUVEAU_NOM="$NOM" ;;
  [0-9]*.[0-9]*.[0-9]*)
    NOUVEAU_NOM="$MODE"
    # Une version imposée plus basse que l'actuelle passerait le contrôle
    # de la Play Console — le versionCode monte quand même — mais la fiche
    # afficherait une régression aux utilisateurs. C'est presque toujours
    # une faute de frappe.
    PLUS_HAUTE="$(printf '%s\n%s\n' "$NOM" "$MODE" | sort -V | tail -1)"
    if [ "$PLUS_HAUTE" = "$NOM" ] && [ "$NOM" != "$MODE" ]; then
      echo "La version demandée ($MODE) est antérieure à l'actuelle ($NOM)." >&2
      exit 1
    fi
    ;;
  *)
    echo "Mode inconnu : '$MODE'" >&2
    echo "Attendu : patch | minor | major | build | X.Y.Z" >&2
    exit 1
    ;;
esac

NOUVEAU="$NOUVEAU_NOM+$NOUVEAU_CODE"

# -i '' est la forme BSD (macOS). L'écriture passe par un fichier temporaire
# pour qu'une interruption ne laisse pas un pubspec.yaml tronqué.
TMP="$(mktemp)"
sed "s/^version: .*/version: $NOUVEAU/" pubspec.yaml > "$TMP"
mv "$TMP" pubspec.yaml

echo "$ACTUEL  ->  $NOUVEAU"
echo
echo "Prochaine étape :"
echo "  ./build_aab.sh          (publicités réelles par défaut)"
