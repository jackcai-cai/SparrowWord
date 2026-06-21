#!/usr/bin/env bash
# Build a distributable (ad-hoc signed) macOS .zip for SparrowWord.
# No Apple Developer ID / notarization — users open via right-click -> Open the first time.
# Gate L: verify the lite dictionary is bundled and small, and that the zipped app
# still passes codesign after a round-trip; emit a sha256 of the final zip.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-1.0}"
PROJECT="SparrowWord/SparrowWord.xcodeproj"
SCHEME="SparrowWord"
DERIVED=".build/xcode-release"
APP="$DERIVED/Build/Products/Release/SparrowWord.app"
OUT="dist"
ZIP="$OUT/SparrowWord-v${VERSION}.zip"

echo "==> 1/6 Release build"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -derivedDataPath "$DERIVED" build >/dev/null
echo "    built: $APP"

echo "==> 2/6 ad-hoc sign"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "    codesign OK (ad-hoc)"

echo "==> 3/6 in-bundle checks (gate L)"
DB="$APP/Contents/Resources/ecdict-lite.sqlite"
[ -f "$DB" ] || { echo "FAIL: bundled ecdict-lite.sqlite missing"; exit 1; }
SZ=$(stat -f%z "$DB"); MB=$((SZ / 1048576))
[ "$MB" -lt 50 ] || { echo "FAIL: ecdict-lite is ${MB}MB (>=50MB)"; exit 1; }
echo "    bundled lite: ${MB}MB OK"

echo "==> 4/6 zip"
mkdir -p "$OUT"; rm -f "$ZIP" "$ZIP.sha256"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "    $ZIP ($(du -h "$ZIP" | cut -f1))"

echo "==> 5/6 round-trip codesign verify"
TMP="$(mktemp -d)"
ditto -x -k "$ZIP" "$TMP"
codesign --verify --deep --strict "$TMP/SparrowWord.app"
rm -rf "$TMP"
echo "    extracted app codesign OK"

echo "==> 6/6 sha256"
( cd "$OUT" && shasum -a 256 "SparrowWord-v${VERSION}.zip" | tee "SparrowWord-v${VERSION}.zip.sha256" )

echo ""
echo "DONE -> $ZIP"
echo "NOTE: unsigned/un-notarized. First launch: right-click the app -> Open -> Open."
echo "      ('spctl --assess' will reject; that is expected without notarization.)"
