#!/bin/bash
# Packages build/Ultimate Screen Recording.app into site/downloads/UltimateScreenRecording-<version>-arm64.dmg
set -euo pipefail
cd "$(dirname "$0")/.."
export VERSION="${1:-0.5.0}"
./scripts/build_app.sh
APP="build/Ultimate Screen Recording.app"
STAGE="$(mktemp -d)"
ditto --norsrc --noextattr "$APP" "$STAGE/Ultimate Screen Recording.app"
ln -s /Applications "$STAGE/Applications"
cp scripts/READ_ME_FIRST.txt "$STAGE/READ ME FIRST.txt"
OUT="../../site/downloads/UltimateScreenRecording-$VERSION-universal.dmg"
mkdir -p "$(dirname "$OUT")"; rm -f "$OUT"
hdiutil create -quiet -volname "Ultimate Screen Recording" -srcfolder "$STAGE" -format UDZO -ov "$OUT"
shasum -a 256 "$OUT" | tee "$OUT.sha256"
SHA="$(cut -d' ' -f1 "$OUT.sha256")"
NOTES="${NOTES:-See docs/PROGRESS.md for what changed.}"
python3 - "$VERSION" "$(basename "$OUT")" "$SHA" "$NOTES" <<'PY' > ../../site/latest.json
import json,sys
v,f,sha,notes=sys.argv[1:5]
print(json.dumps({"version":v,"file":"downloads/"+f,"sha256":sha,"notes":notes,"minimumMacOS":"14.0"},indent=2))
PY
