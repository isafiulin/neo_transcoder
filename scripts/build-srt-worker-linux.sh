#!/bin/sh
set -eu

VERSION=${VERSION:-$(cat VERSION 2>/dev/null || echo dev)}
COMMIT=${COMMIT:-$(git rev-parse --short HEAD 2>/dev/null || echo unknown)}
DATE=${DATE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}
PLATFORM=${PLATFORM:-linux/amd64}
OUT=${OUT:-dist/srt-worker-linux-amd64}

docker buildx build \
  --platform "$PLATFORM" \
  --build-arg "VERSION=$VERSION" \
  --build-arg "COMMIT=$COMMIT" \
  --build-arg "DATE=$DATE" \
  --file scripts/Dockerfile.srt-worker \
  --output "type=local,dest=$OUT" \
  .

chmod +x "$OUT/neotranscoder-srt-worker"
echo "$OUT/neotranscoder-srt-worker"
