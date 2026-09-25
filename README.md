# Life Dashboard Updates

Dieses Repository ist der Update-Feed für die macOS-App **Life Dashboard**.

## Was kann aktualisiert werden?

Ab Desktop-Basis **V11** können über den Feed nicht nur Dashboard-Dateien, sondern auch App-Ressourcen aktualisiert werden.

Dazu gehören aktuell:
- Dashboard-Oberfläche und Funktionen
- CSS / JavaScript
- App-Icon
- weitere Dateien unter `Contents/Resources`

Vor jeder Installation werden Dashboard und betroffene Ressourcen gesichert. Der Menüpunkt **Letztes Dashboard-Update zurücksetzen** stellt diese Sicherung wieder her.

## Struktur

- `update.json` — Version, Prüfsummen und Ressourcen
- `dashboard.part01` … — aktuelle Dashboard-Datei
- `AppIcon.png.b64` — kompaktes Icon-Payload für Ressourcen-Updates

Die App prüft jede heruntergeladene Datei per SHA-256, bevor sie in das App-Bundle geschrieben wird. Danach wird die App lokal neu signiert.

## Update-Ablauf

1. Neue Dashboard-/Ressourcen-Version vorbereiten.
2. Prüfsummen berechnen.
3. Dateien im Repository aktualisieren.
4. `dashboardVersion` erhöhen.
5. `update.json` zuletzt aktualisieren.
6. Life Dashboard erkennt und installiert das Update automatisch.

Änderungen am nativen Swift-Code können weiterhin eine neue Desktop-Basis erfordern. Das wird über `minimumNativeVersion` erkannt.

Aktuelle native Basis: **0.15.0**
Aktuelle Dashboard-Basis: **0.20.0**

## Ernährungspläne mit ChatGPT

Im Generator können die Ernährungswünsche als ChatGPT-Vorgaben kopiert werden. Die fertige JSON-Antwort wird in der App eingefügt, vor dem Speichern auf Vollständigkeit, Zutaten, Ausschlüsse und Tagesziele geprüft und erst nach Bestätigung übernommen. Alternativ wählt **Ohne KI** Gerichte aus der lokalen Bibliothek. Die App selbst ruft keine KI-API auf; du entscheidest, ob du Angaben an ChatGPT weitergibst. Nährwerte aus ChatGPT sind Schätzungen.

Die API-Anbindung und Schlüssel-Eingabe aus älteren Versionen wurden entfernt. Ein früher im macOS-Schlüsselbund gespeicherter API-Schlüssel bleibt zunächst unangetastet und kann unter **Einstellungen → ChatGPT-Import → Früheren API-Schlüssel entfernen** auf Wunsch gelöscht werden. Der Schlüssel wird beim Start nicht gelesen.

Desktop-Update: [Install-Life-Dashboard-Desktop-v15.zip](Install-Life-Dashboard-Desktop-v15.zip) herunterladen, entpacken und die `.command`-Datei ausführen. Die bestehende Dashboard-Datensicherung bleibt verfügbar.
