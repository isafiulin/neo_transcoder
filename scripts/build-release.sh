#!/bin/sh
set -eu

VERSION=${VERSION:-dev}
COMMIT=${COMMIT:-$(git rev-parse --short HEAD 2>/dev/null || echo unknown)}
DATE=${DATE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}
OUT=${OUT:-dist/neotranscoder}

mkdir -p "$OUT"
go build \
  -ldflags "-X neotranscoder/internal/buildinfo.Version=$VERSION -X neotranscoder/internal/buildinfo.Commit=$COMMIT -X neotranscoder/internal/buildinfo.Date=$DATE" \
  -o "$OUT/neotranscoder" \
  ./cmd/neotranscoder

cp scripts/install.sh "$OUT/install.sh"
cp scripts/uninstall.sh "$OUT/uninstall.sh"
chmod +x "$OUT/neotranscoder" "$OUT/install.sh" "$OUT/uninstall.sh"

echo "$OUT"
