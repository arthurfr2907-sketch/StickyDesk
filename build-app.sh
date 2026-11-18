#!/bin/bash
# Construit StickyDesk.app, l'installe dans Applications et la lance.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="StickyDesk"
BUNDLE_ID="com.arthur.stickydesk"
VERSION="1.0"
ICON_NAME="AppIcon-$(date +%s)"   # nom unique : macOS ne peut pas réutiliser l'ancienne icône en cache

echo "→ Compilation (version optimisée)…"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

echo "→ Icône…"
if [ -f Assets/AppIcon.png ]; then
  ICONSET="build/AppIcon.iconset"
  rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s Assets/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z $d $d Assets/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/$ICON_NAME.icns"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>$ICON_NAME</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "→ Signature locale…"
xattr -cr "$APP" 2>/dev/null || true   # retire les métadonnées du Finder (bloquent la signature)
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 \
  || echo "  (signature ignorée, l'app fonctionnera quand même)"

echo "→ Installation…"
DEST="/Applications"
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"
pkill -x "$APP_NAME" 2>/dev/null || true   # ferme l'ancienne version (y compris celle lancée par Xcode)
sleep 0.5
rm -rf "$DEST/$APP_NAME.app"
cp -R "$APP" "$DEST/"
touch "$DEST/$APP_NAME.app"
# Réenregistre l'app auprès de macOS et rafraîchit le Dock (nouvelle icône)
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST/$APP_NAME.app" 2>/dev/null || true
killall Dock 2>/dev/null || true
sleep 1

open "$DEST/$APP_NAME.app"
echo "✓ StickyDesk est installée dans $DEST et lancée."
