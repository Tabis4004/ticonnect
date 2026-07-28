#!/usr/bin/env bash
# Génère les dossiers de plateforme (android/, ios/) que Flutter doit créer
# lui-même, puis applique la configuration AdMob dans le manifeste Android.
set -e
cd "$(dirname "$0")"

echo "==> Génération du squelette de plateforme"
flutter create . --org ci.ticonnect --project-name ticonnect --platforms=android,ios,web

echo "==> Récupération des dépendances"
flutter pub get

MANIFEST=android/app/src/main/AndroidManifest.xml
ADMOB_APP_ID="ca-app-pub-3940256099942544~3347511713"  # ID de TEST Google

echo "==> Configuration du manifeste Android"
python3 - "$MANIFEST" "$ADMOB_APP_ID" <<'PY'
import re, sys
path, app_id = sys.argv[1], sys.argv[2]
xml = open(path, encoding='utf-8').read()

# Permission Internet
if 'android.permission.INTERNET' not in xml:
    xml = xml.replace('<manifest',
        '<manifest', 1)
    xml = re.sub(r'(<manifest[^>]*>)',
                 r'\1\n    <uses-permission android:name="android.permission.INTERNET"/>',
                 xml, count=1)

# Identifiant d'application AdMob
if 'com.google.android.gms.ads.APPLICATION_ID' not in xml:
    meta = ('\n        <meta-data\n'
            '            android:name="com.google.android.gms.ads.APPLICATION_ID"\n'
            f'            android:value="{app_id}"/>\n')
    xml = xml.replace('</application>', meta + '    </application>')

open(path, 'w', encoding='utf-8').write(xml)
print("   manifeste mis à jour")
PY

echo
echo "Terminé. Lance l'app avec :"
echo "  flutter run"
