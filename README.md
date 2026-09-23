# Life Dashboard Updates

Dieses Repository ist der Update-Feed für die macOS-App **Life Dashboard**.

## Struktur

- `update.json` — beschreibt die aktuell veröffentlichte Dashboard-Version.
- `dashboard.part01` … — bilden zusammen die aktuelle `dashboard.html`.
- Die App setzt die Teile in der Reihenfolge aus `dashboardParts` zusammen und prüft danach die SHA-256-Prüfsumme.

## Update-Ablauf

Normale Änderungen an Oberfläche und Dashboard-Funktionen benötigen keinen neuen Installer mehr:

1. Neue Dashboard-Version erzeugen.
2. Dashboard-Datei in Update-Teile zerlegen.
3. Teile in diesem Repository aktualisieren.
4. SHA-256 der vollständigen Datei in `update.json` eintragen.
5. `dashboardVersion` erhöhen.
6. Life Dashboard erkennt das Update beim Start bzw. bei der nächsten Update-Prüfung.

Native Swift-Änderungen können weiterhin eine neue Desktop-Basis erfordern. Das wird über `minimumNativeVersion` erkannt.

Aktuelle Basis: **0.9.0**
