#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
STAGE=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/QuotaBar.XXXXXX")
APP="$STAGE/QuotaBar.app"
ZIP="$ROOT/outputs/QuotaBar.zip"
trap '/bin/rm -rf "$STAGE"' EXIT

/usr/bin/swift build --package-path "$ROOT" -c release
BIN_DIR=$(/usr/bin/swift build --package-path "$ROOT" -c release --show-bin-path)

/bin/mkdir -p "$ROOT/outputs"
/bin/rm -rf "$ROOT/outputs/QuotaBar.app"
/bin/rm -f "$ZIP"
/bin/mkdir -p "$APP/Contents/MacOS"
/bin/cp "$BIN_DIR/QuotaBar" "$APP/Contents/MacOS/QuotaBar"
/bin/cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
/usr/bin/xattr -cr "$APP"
/usr/bin/codesign --force --sign - --timestamp=none "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"

/usr/bin/printf 'Built %s\n' "$ZIP"
