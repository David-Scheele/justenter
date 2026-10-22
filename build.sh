#!/bin/zsh
# Builds JustEnter.app from the Swift package. Usage: ./build.sh [--debug]
set -euo pipefail

cd "$(dirname "$0")"

CONFIG=release
if [[ "${1:-}" == "--debug" ]]; then
    CONFIG=debug
fi

echo "→ swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN=".build/$CONFIG/JustEnter"
APP="build/JustEnter.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/JustEnter"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -d Resources/Sounds ]]; then
    cp Resources/Sounds/*.wav "$APP/Contents/Resources/"
fi

# App icon: drop your logo at Assets/logo.png (1024x1024 recommended) and it
# gets converted into the app icon automatically.
if [[ -f Assets/logo.png ]]; then
    echo "→ building AppIcon.icns from Assets/logo.png"
    ICONSET=$(mktemp -d)/AppIcon.iconset
    mkdir -p "$ICONSET"
    for size in 16 32 64 128 256 512; do
        sips -z $size $size Assets/logo.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
        double=$((size * 2))
        sips -z $double $double Assets/logo.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

# Prefer the stable local identity (created by ./setup-signing.sh) so TCC permission
# grants survive rebuilds; fall back to ad-hoc if it isn't installed.
IDENTITY="JustEnter Dev Signing"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    codesign --force --sign "$IDENTITY" "$APP"
    echo "→ signed with stable identity ($IDENTITY)"
else
    codesign --force --sign - "$APP"
    echo "→ ad-hoc signed (run ./setup-signing.sh once to stop permission re-prompts)"
fi

# Install to a stable path: permissions (TCC) are tied to signature AND location,
# so always running the /Applications copy keeps grants forever. Move (not copy)
# so no stale duplicate lingers in build/ — launching a stale copy resets permissions.
rm -rf /Applications/JustEnter.app
mv "$APP" /Applications/JustEnter.app

echo "✓ Built and installed /Applications/JustEnter.app"
echo "  Run it:  open /Applications/JustEnter.app"
