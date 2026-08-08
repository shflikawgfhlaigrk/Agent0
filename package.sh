#!/bin/bash
# Reproducibly build Agent0Graph.app from source + tracked Info.plist.
# The .app is needed (not `swift run`) for microphone/speech permissions to work.
set -e
cd "$(dirname "$0")"
swift build -c release
APP="Agent0Graph.app"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Agent0Graph "$APP/Contents/MacOS/Agent0Graph"
cp packaging/Info.plist "$APP/Contents/Info.plist"
LSREG="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
"$LSREG" -f "$PWD/$APP" >/dev/null 2>&1 || true
echo "packaged $APP"

# keep a current copy on the Desktop for easy launching
DESK="$HOME/Desktop/Agent 0.app"
rm -rf "$DESK"
cp -R "$APP" "$DESK"
"$LSREG" -f "$DESK" >/dev/null 2>&1 || true
echo "refreshed Desktop app: $DESK"
