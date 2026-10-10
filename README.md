# Wohnzimmer Licht – Flutter-App

Steuert Govee-Lampen **direkt per LAN-API (UDP)**, ohne Server und ohne `govee.php`.

## Voraussetzungen

- Flutter SDK ≥ 3.27, Android SDK (`flutter doctor` ist grün)
- Für jede Lampe ist in der Govee-App **„LAN-Steuerung“** aktiviert
- Handy und Lampen sind im selben WLAN (kein Gast-WLAN, keine Client-Isolation)

## Bauen

```bash
./setup.sh
```

Das Skript erzeugt die Android-Plattformdateien, trägt die WLAN-/Multicast-Rechte ins Manifest ein, generiert das App-Icon und baut die APK:

```
build/app/outputs/flutter-apk/app-release.apk
```

```
fvm flutter build apk --release --split-per-abi
```

Installieren per `adb install -r build/app/outputs/flutter-apk/app-release.apk` oder die APK aufs Handy kopieren.
Die Release-APK ist mit dem Debug-Key signiert und damit für Sideloading gedacht.

Entwickeln mit angeschlossenem Handy: `flutter run`

## Funktionen

- Lampen werden beim ersten Start automatisch gefunden (Multicast-Scan)
- Karte „Alle Lampen“ sowie Einzelsteuerung mit EIN/AUS, Helligkeit und ±5
- Status wird alle 10 s abgefragt, nicht im Hintergrund; Pull-to-Refresh
- Unter ⚙︎ lassen sich Lampen umbenennen, sortieren (lange drücken), manuell per IP anlegen und testen (antippen)
- IP-Änderungen durch DHCP werden beim Start per Scan anhand der MAC nachgezogen

## Ports

| Richtung | Port | Zweck |
|---|---|---|
| App → 239.255.255.250 | 4001 | Scan |
| App → Lampe | 4003 | Befehle |
| Lampe → App | 4002 | Antworten |
