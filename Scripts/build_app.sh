#!/usr/bin/env bash
#
# Assembles MenuBarBible.app from the SwiftPM build product.
#
# SwiftPM produces a bare executable; a menu bar app needs a bundle with an Info.plist
# (for LSUIElement), the read-only bible.sqlite in Resources, and a signature carrying
# the sandbox entitlement.
#
#   ./Scripts/build_app.sh                 # debug, ad-hoc signed
#   ./Scripts/build_app.sh release         # release, ad-hoc signed
#   ./Scripts/build_app.sh release "Developer ID Application: Name (TEAMID)"
#
set -euo pipefail

CONFIG="${1:-debug}"
IDENTITY="${2:--}"          # '-' is ad-hoc

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/MenuBarBible.app"
CONTENTS="$APP/Contents"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG" --package-path "$ROOT"
BIN="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BIN/MenuBarBible"            "$CONTENTS/MacOS/MenuBarBible"
cp "$ROOT/Resources/Info.plist"   "$CONTENTS/Info.plist"
cp "$ROOT/Resources/bible.sqlite" "$CONTENTS/Resources/bible.sqlite"
[ -f "$ROOT/Resources/AppIcon.icns" ] && cp "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
printf 'APPL????' > "$CONTENTS/PkgInfo"

# The ETL scripts under tools/ are build artifacts and are never copied in.

echo "==> Signing (identity: $IDENTITY)"
codesign --force --deep \
         --options runtime \
         --entitlements "$ROOT/Resources/MenuBarBible.entitlements" \
         --sign "$IDENTITY" \
         "$APP"

codesign --verify --verbose=2 "$APP"

echo
echo "Built: $APP"
du -sh "$APP" | awk '{print "Size:  " $1}'
echo
if [ "$IDENTITY" = "-" ]; then
  cat <<'NOTE'
Ad-hoc signed — fine for local use. For distribution:

  ./Scripts/build_app.sh release "Developer ID Application: <Name> (<TEAMID>)"
  ditto -c -k --keepParent build/MenuBarBible.app build/MenuBarBible.zip
  xcrun notarytool submit build/MenuBarBible.zip \
        --keychain-profile <profile> --wait
  xcrun stapler staple build/MenuBarBible.app

Launch at login (SMAppService) needs a real signature and a stable location;
move the app to /Applications before expecting that toggle to stick.
NOTE
fi
