#!/usr/bin/env bash
# setup.sh – Android-Projekt erzeugen, patchen und APK bauen
set -euo pipefail

cd "$(dirname "$0")"

echo "==> Flutter-Plattformdateien erzeugen (bestehende Dateien bleiben)"
fvm flutter create \
    --org de.home \
    --project-name wohnzimmer_licht \
    --platforms android \
    .

MANIFEST=android/app/src/main/AndroidManifest.xml

echo "==> AndroidManifest patchen"
if ! grep -q CHANGE_WIFI_MULTICAST_STATE "$MANIFEST"; then
    perl -0pi -e 's|(<manifest[^>]*>)|$1
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE"/>|s' "$MANIFEST"
fi

perl -pi -e 's|android:label="[^"]*"|android:label="Wohnzimmer"|' "$MANIFEST"

echo "==> Abhängigkeiten + App-Icon"
fvm flutter pub get
fvm dart run flutter_launcher_icons

echo "==> Release-APK bauen"
fvm flutter build apk --release

echo
echo "Fertig: build/app/outputs/flutter-apk/app-release.apk"

