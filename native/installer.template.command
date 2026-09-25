#!/bin/bash
set -uo pipefail
APP_NAME="Life Dashboard"
DEST_DIR="$HOME/Applications"
FINAL_APP="$DEST_DIR/$APP_NAME.app"
WORK_DIR="$(mktemp -d)"
BUILD_APP="$WORK_DIR/$APP_NAME.app"
LOG_FILE="$WORK_DIR/build.log"
finish_with_error() {
  code=$?
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "✗ Build fehlgeschlagen"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  if [ -f "$LOG_FILE" ]; then cat "$LOG_FILE"; fi
  echo ""
  echo "Bitte Screenshot oder letzten Fehler an ChatGPT schicken."
  echo "Drücke Enter zum Schließen."
  read -r _
  exit "$code"
}
trap finish_with_error ERR

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Life Dashboard Desktop V15"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if /usr/bin/pgrep -x LifeDashboard >/dev/null 2>&1; then
  echo "Bitte Life Dashboard mit ⌘Q beenden. Die Installation läuft danach weiter."
  while /usr/bin/pgrep -x LifeDashboard >/dev/null 2>&1; do
    /bin/sleep 1
  done
fi

command -v xcrun >/dev/null 2>&1 || { xcode-select --install || true; exit 1; }
SWIFTC="$(xcrun --find swiftc 2>/dev/null || true)"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
[ -n "$SWIFTC" ] && [ -d "$SDK_PATH" ]
ARCH="$(uname -m)"
case "$ARCH" in arm64) TARGET_ARCH="arm64" ;; x86_64) TARGET_ARCH="x86_64" ;; *) TARGET_ARCH="$ARCH" ;; esac

mkdir -p "$BUILD_APP/Contents/MacOS" "$BUILD_APP/Contents/Resources"
cat > "$WORK_DIR/dashboard.b64" <<'__DASHBOARD_B64__'
{{DASHBOARD_B64}}
__DASHBOARD_B64__
cat > "$WORK_DIR/source.b64" <<'__SWIFT_B64__'
{{SWIFT_B64}}
__SWIFT_B64__
cat > "$WORK_DIR/icon.b64" <<'__ICON_B64__'
{{ICON_B64}}
__ICON_B64__
/bin/cat "$WORK_DIR/dashboard.b64" | /usr/bin/base64 -D > "$BUILD_APP/Contents/Resources/dashboard.html"
/bin/cat "$WORK_DIR/source.b64" | /usr/bin/base64 -D > "$WORK_DIR/LifeDashboard.swift"
/bin/cat "$WORK_DIR/icon.b64" | /usr/bin/base64 -D > "$WORK_DIR/icon.png"

cat > "$BUILD_APP/Contents/Info.plist" <<'__PLIST__'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleName</key><string>Life Dashboard</string>
<key>CFBundleDisplayName</key><string>Life Dashboard</string>
<key>CFBundleIdentifier</key><string>com.lifedashboard.desktop</string>
<key>CFBundleExecutable</key><string>LifeDashboard</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleSignature</key><string>????</string>
<key>CFBundleShortVersionString</key><string>0.15</string>
<key>CFBundleVersion</key><string>15</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppleEventsUsageDescription</key><string>Life Dashboard steuert die Musik-App.</string>
<key>NSCalendarsUsageDescription</key><string>Life Dashboard zeigt deine Kalendertermine an.</string>
<key>NSCalendarsFullAccessUsageDescription</key><string>Life Dashboard liest deine Kalendertermine.</string>
</dict></plist>
__PLIST__

echo "0/6 App-Icon vorbereiten …"
mkdir -p "$WORK_DIR/AppIcon.iconset"
for size in 16 32 128 256 512; do
  /usr/bin/sips -z "$size" "$size" "$WORK_DIR/icon.png" --out "$WORK_DIR/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
done
/usr/bin/sips -z 32 32 "$WORK_DIR/icon.png" --out "$WORK_DIR/AppIcon.iconset/icon_16x16@2x.png" >/dev/null
/usr/bin/sips -z 64 64 "$WORK_DIR/icon.png" --out "$WORK_DIR/AppIcon.iconset/icon_32x32@2x.png" >/dev/null
/usr/bin/sips -z 256 256 "$WORK_DIR/icon.png" --out "$WORK_DIR/AppIcon.iconset/icon_128x128@2x.png" >/dev/null
/usr/bin/sips -z 512 512 "$WORK_DIR/icon.png" --out "$WORK_DIR/AppIcon.iconset/icon_256x256@2x.png" >/dev/null
/usr/bin/sips -z 1024 1024 "$WORK_DIR/icon.png" --out "$WORK_DIR/AppIcon.iconset/icon_512x512@2x.png" >/dev/null
/usr/bin/iconutil -c icns "$WORK_DIR/AppIcon.iconset" -o "$BUILD_APP/Contents/Resources/AppIcon.icns" 2>&1 | tee "$LOG_FILE"

echo "1/6 Info.plist prüfen …"
/usr/bin/plutil -lint "$BUILD_APP/Contents/Info.plist" | tee -a "$LOG_FILE"
echo "2/6 Swift-App kompilieren …"
xcrun --sdk macosx swiftc -swift-version 5 -sdk "$SDK_PATH" -target "$TARGET_ARCH-apple-macosx13.0" -O -framework Cocoa -framework WebKit -framework EventKit -framework UserNotifications -framework Security "$WORK_DIR/LifeDashboard.swift" -o "$BUILD_APP/Contents/MacOS/LifeDashboard" 2>&1 | tee -a "$LOG_FILE"
echo "3/6 Executable prüfen …"
test -s "$BUILD_APP/Contents/MacOS/LifeDashboard"
chmod 755 "$BUILD_APP/Contents/MacOS/LifeDashboard"
echo "4/6 App signieren …"
/usr/bin/codesign --force --deep --sign - "$BUILD_APP" 2>&1 | tee -a "$LOG_FILE"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$BUILD_APP" 2>&1 | tee -a "$LOG_FILE"
echo "5/6 Installieren …"
mkdir -p "$DEST_DIR"
PREVIOUS_APP="$DEST_DIR/.Life Dashboard.previous.app"
rm -rf "$PREVIOUS_APP"
if [ -d "$FINAL_APP" ]; then /bin/mv "$FINAL_APP" "$PREVIOUS_APP"; fi
if /bin/mv "$BUILD_APP" "$FINAL_APP"; then
  rm -rf "$PREVIOUS_APP"
else
  if [ -d "$PREVIOUS_APP" ]; then /bin/mv "$PREVIOUS_APP" "$FINAL_APP"; fi
  exit 1
fi
/usr/bin/xattr -dr com.apple.quarantine "$FINAL_APP" 2>/dev/null || true
echo "6/6 Fertigstellen …"
touch "$FINAL_APP"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✓ Life Dashboard Desktop V15 ist fertig"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Deine Daten und der OpenAI-Schlüssel bleiben beim Update erhalten."
open "$FINAL_APP"
echo ""
echo "Drücke Enter zum Schließen."
read -r _
