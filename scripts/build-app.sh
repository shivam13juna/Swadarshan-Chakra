#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
CONFIGURATION=release
LAUNCH=false
for argument in "$@"; do
    case "$argument" in
        --debug) CONFIGURATION=debug ;;
        --launch) LAUNCH=true ;;
        *) printf 'Unknown option: %s\n' "$argument" >&2; exit 1 ;;
    esac
done

if [ ! -f "$PROJECT_DIR/icon.png" ]; then
    printf 'Missing app icon: %s/icon.png\n' "$PROJECT_DIR" >&2
    exit 1
fi
python3 scripts/verify-assets.py
swift build -c "$CONFIGURATION" --product SwadarshanChakra
BINARY_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
OUTPUT_APP="$PROJECT_DIR/dist/Swadarshan Chakra.app"
mkdir -p "$PROJECT_DIR/dist"
# Sign a fresh bundle so an already-running app keeps its executable and session intact.
STAGING_DIR="$(mktemp -d "$PROJECT_DIR/dist/.app-build.XXXXXX")"
APP_DIR="$STAGING_DIR/Swadarshan Chakra.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BINARY_DIR/SwadarshanChakra" "$APP_DIR/Contents/MacOS/SwadarshanChakra"
ditto "$BINARY_DIR/SwadarshanChakra_SwadarshanChakra.bundle" \
      "$APP_DIR/Contents/Resources/SwadarshanChakra_SwadarshanChakra.bundle"
cp packaging/Info.plist "$APP_DIR/Contents/Info.plist"

ICON_DIR="$PROJECT_DIR/.build/AppIcon.iconset"
if [ ! -f "$PROJECT_DIR/.build/AppIcon.icns" ] || [ scripts/generate-icon.swift -nt "$PROJECT_DIR/.build/AppIcon.icns" ] || [ icon.png -nt "$PROJECT_DIR/.build/AppIcon.icns" ]; then
    swift scripts/generate-icon.swift "$PROJECT_DIR/icon.png" "$ICON_DIR"
    iconutil -c icns "$ICON_DIR" -o "$PROJECT_DIR/.build/AppIcon.icns"
fi
cp "$PROJECT_DIR/.build/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
if [ -d "$OUTPUT_APP" ]; then
    mv "$OUTPUT_APP" "$STAGING_DIR/Previous.app"
fi
if ! mv "$APP_DIR" "$OUTPUT_APP"; then
    if [ -d "$STAGING_DIR/Previous.app" ]; then mv "$STAGING_DIR/Previous.app" "$OUTPUT_APP"; fi
    exit 1
fi
touch "$OUTPUT_APP"
printf '\nBuilt %s\n' "$OUTPUT_APP"
if [ "$LAUNCH" = true ]; then open "$OUTPUT_APP"; fi
