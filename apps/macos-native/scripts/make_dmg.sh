#!/bin/bash
# Packages build/Ultimate Screen Recording.app into site/downloads/UltimateScreenRecording-<version>-arm64.dmg
set -euo pipefail
cd "$(dirname "$0")/.."
export VERSION="${1:-0.4.1}"
./scripts/build_app.sh
APP="build/Ultimate Screen Recording.app"
STAGE="$(mktemp -d)"
ditto --norsrc --noextattr "$APP" "$STAGE/Ultimate Screen Recording.app"
ln -s /Applications "$STAGE/Applications"
cp scripts/READ_ME_FIRST.txt "$STAGE/READ ME FIRST.txt"
OUT="../../site/downloads/UltimateScreenRecording-$VERSION-arm64.dmg"
mkdir -p "$(dirname "$OUT")"; rm -f "$OUT"
hdiutil create -quiet -volname "Ultimate Screen Recording" -srcfolder "$STAGE" -format UDZO -ov "$OUT"
shasum -a 256 "$OUT" | tee "$OUT.sha256"
