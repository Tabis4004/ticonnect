#!/usr/bin/env bash
# Rebuild web + déploiement Cloudflare.
#
# À lancer depuis un Terminal sur le Mac :
#   cd ~/Documents/ticonnect && ./deploy.sh
#
# Aucun --dart-define-from-file : dev.json contient le mot de passe admin,
# et tout --dart-define finit en clair dans le JavaScript public.
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Commit servi : $(git rev-parse --short HEAD) — $(git log -1 --pretty=%s)"
if [ -n "$(git status --porcelain -- lib pubspec.yaml)" ]; then
  echo "    (attention : modifications non commitées dans lib/ ou pubspec.yaml)"
fi

echo "==> Génération de la plateforme web"
flutter create . --platforms=web --project-name ticonnect --org com.ticonnect

echo "==> Dépendances"
flutter pub get

echo "==> Build web (release)"
rm -rf build/web
flutter build web --release

# Le build précédent était incomplet : on vérifie que le bundle Dart est bien là.
if ! ls build/web/main.dart.js >/dev/null 2>&1; then
  echo "ERREUR : build/web/main.dart.js absent — le build a échoué." >&2
  exit 1
fi
echo "    OK : $(du -sh build/web | cut -f1) dans build/web"

echo "==> Déploiement Cloudflare"
npx --yes wrangler@latest deploy

echo
echo "Terminé. Vérifie https://ticonnect.isidoretabati.workers.dev"
echo "L'écran de connexion doit afficher « Pseudo » + « Mot de passe »"
echo "(et non le champ numéro + code SMS de l'ancienne version)."
