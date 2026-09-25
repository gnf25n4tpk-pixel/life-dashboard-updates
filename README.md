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

Aktuelle native Basis: **0.13.0**
Aktuelle Dashboard-Basis: **0.19.2**

## KI für Ernährungspläne

V12 ergänzt die native OpenAI-Anbindung. In **Einstellungen → KI für Ernährungspläne** lässt sich ein eigener OpenAI-API-Schlüssel im macOS-Schlüsselbund hinterlegen oder entfernen. Im Generator kann zwischen **Mit KI** (neue Gerichte) und **Ohne KI** (vorhandene Gerichte) gewählt werden. Die KI erhält nur Ernährungswünsche und kürzlich geplante Gerichtsnamen. Der API-Aufruf erfolgt in Swift über die Responses API mit `store: false` und strukturiertem JSON; der Schlüssel liegt weder in den Dashboard-Dateien noch im Repository. Eine API-Nutzung kann Kosten verursachen. Generierte Nährwerte sind Schätzungen.

V13 liest den API-Schlüssel erst, wenn ein KI-Plan angefordert wird. Beim App-Start und beim Öffnen der Einstellungen findet kein Schlüsselbundzugriff statt. Der nicht geheime Status wird lokal gespeichert; bereits in V12 gespeicherte Schlüssel werden beim ersten KI-Plan erkannt.

Desktop-Update: [Install-Life-Dashboard-Desktop-v13.zip](Install-Life-Dashboard-Desktop-v13.zip) herunterladen, entpacken und die `.command`-Datei ausführen. Die bestehende Dashboard-Datensicherung bleibt verfügbar.
