#!/usr/bin/env bash
# Rebuilds the published site into docs/ (GitHub Pages → main /docs).
#
#   ./build.sh                    app source at ../MoodPlaystation
#   MOOD_APP=/path/to/app ./build.sh
#
# The app is copied into .build/ and the demo overlay applied there, so the
# app repository is never modified.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP="${MOOD_APP:-$HERE/../MoodPlaystation}"
REPO="$(basename "$HERE")"
WORK="$HERE/.build/app"
OUT="$HERE/docs"

[[ -f "$APP/pubspec.yaml" ]] || { echo "error: no Flutter app at $APP (set MOOD_APP)" >&2; exit 1; }

rm -rf "$WORK"
mkdir -p "$WORK"
rsync -a --exclude .git --exclude build --exclude .dart_tool \
  --exclude android --exclude ios --exclude macos --exclude windows --exclude linux \
  "$APP/" "$WORK/"
python3 "$HERE/overlay/apply.py" "$WORK"

(cd "$WORK" && flutter pub get >/dev/null && flutter build web --release \
  --dart-define=DEMO_MODE=true --base-href "/$REPO/app/" --no-wasm-dry-run)

# The public bundle must never carry the real owner password.
if grep -q "Mood2023" "$WORK/build/web/main.dart.js"; then
  echo "error: the owner password leaked into the demo bundle" >&2
  exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"
cp -R "$HERE/site/." "$OUT/"
cp -R "$WORK/build/web" "$OUT/app"
# The service worker would pin visitors to a stale copy of the demo.
rm -f "$OUT/app/flutter_service_worker.js"
touch "$OUT/.nojekyll"
perl -pi -e "s|__SITE_URL__|https://salahianoo.github.io/$REPO/|g" "$OUT/index.html"

echo "Built $OUT"
