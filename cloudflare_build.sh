#!/usr/bin/env bash
# Build web pour Cloudflare.
#
# L'image de build Cloudflare ne contient pas Flutter : on le récupère,
# puis on compile. Compter 5 à 10 minutes au premier passage.
#
# Aucun --dart-define-from-file ici : dev.json contient le mot de passe
# administrateur, et tout ce qu'on passe en --dart-define finit en clair
# dans le JavaScript public. L'URL et la clé anon suffisent, elles sont
# déjà les valeurs par défaut de lib/core/config.dart.
set -euo pipefail

FLUTTER_DIR="${FLUTTER_DIR:-$HOME/flutter}"

if ! command -v flutter >/dev/null 2>&1; then
  echo "==> Installation de Flutter"
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$FLUTTER_DIR"
  export PATH="$FLUTTER_DIR/bin:$PATH"
fi

# Flutter refuse de tourner sur un dépôt dont il n'est pas propriétaire
# (protection Git "dubious ownership"), ce qui arrive dans les runners CI.
git config --global --add safe.directory "$FLUTTER_DIR" || true
git config --global --add safe.directory "$PWD" || true

flutter --version
flutter config --no-analytics >/dev/null 2>&1 || true

# Les dossiers de plateforme ne sont pas versionnés : on les génère ici.
# La commande est idempotente et ne touche ni lib/ ni pubspec.yaml.
echo "==> Génération de la plateforme web"
flutter create . --platforms=web --project-name ticonnect --org ci.ticonnect

flutter pub get
flutter build web --release

echo "==> Contenu produit :"
ls -la build/web | head
