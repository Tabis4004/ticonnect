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
set -e

if ! command -v flutter >/dev/null 2>&1; then
  echo "==> Installation de Flutter"
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$HOME/flutter"
  export PATH="$HOME/flutter/bin:$PATH"
fi

flutter --version
flutter config --enable-web
flutter pub get
flutter build web --release
