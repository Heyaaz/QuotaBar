#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP="$ROOT/outputs/QuotaBar.app"

/usr/bin/swift build --package-path "$ROOT" -c release
BIN_DIR=$(/usr/bin/swift build --package-path "$ROOT" -c release --show-bin-path)

/bin/rm -rf "$APP"
/bin/mkdir -p "$APP/Contents/MacOS"
/bin/cp "$BIN_DIR/QuotaBar" "$APP/Contents/MacOS/QuotaBar"
/bin/cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
/usr/bin/codesign --force --sign - --timestamp=none "$APP"

/usr/bin/printf 'Built %s\n' "$APP"

