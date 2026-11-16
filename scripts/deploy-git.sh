#!/bin/sh
# Build an isolated Git revision before touching the running service.
set -eu

if [ "$#" -ne 2 ]; then
  echo "usage: $0 REPOSITORY BRANCH_OR_TAG" >&2
  exit 2
fi
REPOSITORY=$1
REVISION=$2
case "$REPOSITORY" in -*) echo "invalid repository" >&2; exit 2;; esac
case "$REVISION" in ''|-*) echo "invalid revision" >&2; exit 2;; esac

for tool in git go flutter pkg-config cc; do
  command -v "$tool" >/dev/null 2>&1 || { echo "missing build tool: $tool" >&2; exit 1; }
done
[ "$(uname -s)" = Linux ] || { echo "deploy on the target Linux host" >&2; exit 1; }
pkg-config --exists srt || { echo "libsrt development files are required" >&2; exit 1; }

DEPLOY_DIR=$(mktemp -d)
trap 'rm -rf "$DEPLOY_DIR"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
git init -q "$DEPLOY_DIR/source"
git -C "$DEPLOY_DIR/source" remote add origin "$REPOSITORY"
git -C "$DEPLOY_DIR/source" fetch --depth=1 origin "$REVISION"
git -C "$DEPLOY_DIR/source" checkout --detach FETCH_HEAD
cd "$DEPLOY_DIR/source"
COMMIT=$(git rev-parse HEAD)
export COMMIT
printf 'Building NeoSRT revision %s\n' "$COMMIT"
go test ./...
(cd ui && flutter test)
BUILD_UI=1 BUILD_SRT=1 OUT="$DEPLOY_DIR/release" ./scripts/build-release.sh

# Validate both executables before requesting elevated installation.
"$DEPLOY_DIR/release/neotranscoder" version
"$DEPLOY_DIR/release/neotranscoder-srt-worker" version
if [ "$(id -u)" -eq 0 ]; then
  SUDO=
else
  SUDO=sudo
fi
if [ -x /usr/local/bin/neotranscoder ]; then
  $SUDO "$DEPLOY_DIR/release/update.sh" --bundle "$DEPLOY_DIR/release"
else
  (cd "$DEPLOY_DIR/release" && $SUDO ./install.sh --yes)
fi
printf 'Deployed NeoSRT Git revision %s\n' "$COMMIT"
