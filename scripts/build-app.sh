#!/usr/bin/env bash
# Builds build/SwitchProfile.app (release, ad-hoc signed).
# Usage: scripts/build-app.sh [--install]
#   --install  copy to ~/Applications/SwitchProfile.app, register it with LaunchServices and open it
set -euo pipefail
cd "$(dirname "$0")/.."

INSTALL=0
case "${1:-}" in
  "") ;;
  --install) INSTALL=1 ;;
  *) echo "usage: scripts/build-app.sh [--install]" >&2; exit 64 ;;
esac

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift toolchain not found; install Command Line Tools: xcode-select --install" >&2
  exit 1
fi

swift build -c release --product SwitchProfile
BIN="$(swift build -c release --show-bin-path)/SwitchProfile"

APP=build/SwitchProfile.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SwitchProfile"
cp Packaging/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict "$APP"

if [[ "$INSTALL" -eq 0 ]]; then
  echo "Built $PWD/$APP"
  echo "Install with: scripts/build-app.sh --install (copies to ~/Applications)"
  exit 0
fi

DEST="$HOME/Applications/SwitchProfile.app"
# Bounded quit of a running copy; refuse to replace a bundle that is still running.
osascript -e 'with timeout of 10 seconds' \
          -e 'tell application id "io.github.khuepm.switchprofile" to quit' \
          -e 'end timeout' >/dev/null 2>&1 || true
if pgrep -x SwitchProfile >/dev/null; then
  echo "Switch Profile is still running; quit it (resolve pending links) and re-run." >&2
  exit 1
fi

rm -rf "$DEST"
ditto "$APP" "$DEST"
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREG" -f "$DEST"
"$LSREG" -u "$PWD/$APP"
open "$DEST"
echo "Installed $DEST"
