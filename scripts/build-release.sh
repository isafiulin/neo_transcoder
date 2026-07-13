#!/bin/sh
set -eu

VERSION=${VERSION:-$(cat VERSION 2>/dev/null || echo dev)}
COMMIT=${COMMIT:-$(git rev-parse --short HEAD 2>/dev/null || echo unknown)}
DATE=${DATE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}
OUT=${OUT:-dist/neotranscoder}
GO=${GO:-go}
BUILD_UI=${BUILD_UI:-1}
BUILD_SRT=${BUILD_SRT:-auto}
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

if [ "$BUILD_SRT" = "1" ] || { [ "$BUILD_SRT" = "auto" ] && [ "$GOOS" = "linux" ] && pkg-config --exists srt 2>/dev/null; }; then
  if [ "$GOOS" != "linux" ]; then
    echo "SRT worker must be built on Linux or supplied as a prebuilt binary" >&2
    exit 1
  fi
  env GOOS="$GOOS" GOARCH="$GOARCH" CGO_ENABLED=1 "$GO" build \
    -tags libsrt \
    -ldflags "-X neotranscoder/internal/buildinfo.Version=$VERSION -X neotranscoder/internal/buildinfo.Commit=$COMMIT -X neotranscoder/internal/buildinfo.Date=$DATE" \
    -o "$OUT/neotranscoder-srt-worker" \
    ./cmd/neotranscoder-srt-worker
elif [ -n "${SRT_WORKER:-}" ]; then
  cp "$SRT_WORKER" "$OUT/neotranscoder-srt-worker"
elif [ "$BUILD_SRT" = "1" ]; then
  echo "libsrt development files are required to build the SRT worker" >&2
  exit 1
else
  echo "warning: SRT worker omitted; use BUILD_SRT=1 on Linux for production releases" >&2
fi

cp scripts/install.sh "$OUT/install.sh"
cp scripts/uninstall.sh "$OUT/uninstall.sh"
cp scripts/update.sh "$OUT/update.sh"
cp scripts/test-srt-native.sh "$OUT/test-srt-native.sh"
cp scripts/test-srt-caller-native.sh "$OUT/test-srt-caller-native.sh"
cp README.md "$OUT/README.md"
cp config.example.json "$OUT/config.example.json"
chmod +x "$OUT/neotranscoder" "$OUT/install.sh" "$OUT/uninstall.sh" "$OUT/update.sh" "$OUT/test-srt-native.sh" "$OUT/test-srt-caller-native.sh"
if [ -f "$OUT/neotranscoder-srt-worker" ]; then
  chmod +x "$OUT/neotranscoder-srt-worker"
fi
if command -v sha256sum >/dev/null 2>&1; then
  (cd "$OUT" && sha256sum neotranscoder > neotranscoder.sha256)
	if [ -f "$OUT/neotranscoder-srt-worker" ]; then (cd "$OUT" && sha256sum neotranscoder-srt-worker > neotranscoder-srt-worker.sha256); fi
elif command -v shasum >/dev/null 2>&1; then
  (cd "$OUT" && shasum -a 256 neotranscoder > neotranscoder.sha256)
	if [ -f "$OUT/neotranscoder-srt-worker" ]; then (cd "$OUT" && shasum -a 256 neotranscoder-srt-worker > neotranscoder-srt-worker.sha256); fi
fi

echo "$OUT"
