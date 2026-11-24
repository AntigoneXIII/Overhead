#!/bin/bash
# Builds Overhead.app into ./build. Pass --install to copy it to ~/Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/Overhead.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Overhead "$APP/Contents/MacOS/Overhead"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    mkdir -p "$HOME/Applications"
    pkill -x Overhead 2>/dev/null || true
    pkill -x Notchbox 2>/dev/null || true              # earlier names of this app
    pkill -x HoldingBay 2>/dev/null || true
    rm -rf "$HOME/Applications/Notchbox.app" "$HOME/Applications/Holding Bay.app"
    rm -rf "$HOME/Applications/Overhead.app"
    cp -R "$APP" "$HOME/Applications/"
    open "$HOME/Applications/Overhead.app"
    echo "Installed to ~/Applications and launched"
fi
