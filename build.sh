#!/bin/bash
# Builds Notchbox.app into ./build. Pass --install to copy it to ~/Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/Notchbox.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Notchbox "$APP/Contents/MacOS/Notchbox"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/logo-mark.png "$APP/Contents/Resources/"
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    mkdir -p "$HOME/Applications"
    pkill -x Notchbox 2>/dev/null || true
    pkill -x HoldingBay 2>/dev/null || true            # earlier build of this app
    rm -rf "$HOME/Applications/Holding Bay.app"
    rm -rf "$HOME/Applications/Notchbox.app"
    cp -R "$APP" "$HOME/Applications/"
    open "$HOME/Applications/Notchbox.app"
    echo "Installed to ~/Applications and launched"
fi
