#!/bin/sh
set -eu

VERSION=${VERSION:-dev}
COMMIT=${COMMIT:-$(git rev-parse --short HEAD 2>/dev/null || echo unknown)}
DATE=${DATE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}
OUT=${OUT:-dist/neotranscoder}
GO=${GO:-go}
BUILD_UI=${BUILD_UI:-1}
GOOS=${GOOS:-$("$GO" env GOOS)}
GOARCH=${GOARCH:-$("$GO" env GOARCH)}
CGO_ENABLED=${CGO_ENABLED:-0}

if [ "$BUILD_UI" = "1" ]; then
  ./scripts/build-ui.sh
fi

mkdir -p "$OUT"
env GOOS="$GOOS" GOARCH="$GOARCH" CGO_ENABLED="$CGO_ENABLED" "$GO" build \
  -ldflags "-X neotranscoder/internal/buildinfo.Version=$VERSION -X neotranscoder/internal/buildinfo.Commit=$COMMIT -X neotranscoder/internal/buildinfo.Date=$DATE" \
  -o "$OUT/neotranscoder" \
  ./cmd/neotranscoder

cp scripts/install.sh "$OUT/install.sh"
cp scripts/uninstall.sh "$OUT/uninstall.sh"
cp scripts/update.sh "$OUT/update.sh"
chmod +x "$OUT/neotranscoder" "$OUT/install.sh" "$OUT/uninstall.sh" "$OUT/update.sh"
if command -v sha256sum >/dev/null 2>&1; then
  (cd "$OUT" && sha256sum neotranscoder > neotranscoder.sha256)
elif command -v shasum >/dev/null 2>&1; then
  (cd "$OUT" && shasum -a 256 neotranscoder > neotranscoder.sha256)
fi

echo "$OUT"
