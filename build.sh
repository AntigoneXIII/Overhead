#!/bin/bash
# Builds "Holding Bay.app" into ./build. Pass --install to copy it to ~/Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/Holding Bay.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/HoldingBay "$APP/Contents/MacOS/HoldingBay"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    mkdir -p "$HOME/Applications"
    pkill -x HoldingBay 2>/dev/null || true
    rm -rf "$HOME/Applications/Holding Bay.app"
    cp -R "$APP" "$HOME/Applications/"
    open "$HOME/Applications/Holding Bay.app"
    echo "Installed to ~/Applications and launched"
fi
