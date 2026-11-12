#!/bin/bash
# Builds "Dupe Sweep.app" (Apple silicon and Intel), signs it and packs a disk image into dist/.
#   ./scripts/build_app.sh                       ad-hoc signed: runs on this Mac and on others after "Open Anyway"
#   DEVELOPER_ID="Developer ID Application: Name (TEAMID)" ./scripts/build_app.sh
#   DEVELOPER_ID=... NOTARY_PROFILE=name ./scripts/build_app.sh    also notarizes and staples (needs an Apple Developer account)
set -euo pipefail
cd "$(dirname "$0")/.."
NAME="Dupe Sweep"; EXE="DupeSweep"; VERSION="${VERSION:-1.0}"; BUILD="${BUILD:-1}"; BUNDLE_ID="${BUNDLE_ID:-com.albgoldin.dupesweep}"
DIST="dist"; APP="$DIST/$NAME.app"; DMG="$DIST/$EXE-$VERSION.dmg"

echo "== building (arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64 --product "$EXE" 2>&1 | grep -E "error|Compiling|Build" | tail -3
BIN=".build/apple/Products/Release/$EXE"
[ -f "$BIN" ] || BIN=".build/release/$EXE"

echo "== icon"
mkdir -p "$DIST/icon"
swiftc -O scripts/make_icon.swift -o "$DIST/icon/make_icon" 2>/dev/null
"$DIST/icon/make_icon" "$DIST/icon/icon-1024.png" >/dev/null
ICONSET="$DIST/icon/AppIcon.iconset"; rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$DIST/icon/icon-1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$DIST/icon/icon-1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$DIST/icon/AppIcon.icns"

echo "== bundle"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$EXE"
cp "$DIST/icon/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$EXE</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Copyright 2026 AL B. Goldin</string>
  <key>NSDesktopFolderUsageDescription</key><string>Dupe Sweep reads the folders you choose to find duplicate files.</string>
  <key>NSDocumentsFolderUsageDescription</key><string>Dupe Sweep reads the folders you choose to find duplicate files.</string>
  <key>NSDownloadsFolderUsageDescription</key><string>Dupe Sweep reads the folders you choose to find duplicate files.</string>
  <key>NSRemovableVolumesUsageDescription</key><string>Dupe Sweep reads the drives you choose to find duplicate files.</string>
  <key>NSNetworkVolumesUsageDescription</key><string>Dupe Sweep reads the shared folders you choose to find duplicate files.</string>
</dict></plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null

echo "== sign"
if [ -n "${DEVELOPER_ID:-}" ]; then
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
else
  codesign --force --options runtime --sign - "$APP"
fi
codesign --verify --deep --strict "$APP" && echo "signature ok ($( [ -n "${DEVELOPER_ID:-}" ] && echo Developer ID || echo ad-hoc ))"

echo "== disk image"
STAGE="$DIST/dmg"; rm -rf "$STAGE" "$DMG"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"; ln -s /Applications "$STAGE/Applications"
cp scripts/READ_ME_FIRST.txt "$STAGE/READ ME FIRST.txt"
hdiutil create -volname "$NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
if [ -n "${DEVELOPER_ID:-}" ]; then codesign --force --sign "$DEVELOPER_ID" "$DMG"; fi
if [ -n "${DEVELOPER_ID:-}" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
  echo "== notarizing"; xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait && xcrun stapler staple "$DMG"
fi
echo "== done"; ls -la "$DMG" | awk '{printf "%s  %.1f MB\n", $9, $5/1e6}'
lipo -archs "$APP/Contents/MacOS/$EXE" | sed 's/^/architectures: /'
