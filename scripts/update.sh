#!/bin/sh
set -eu

SERVICE=neotranscoder
BIN=/usr/local/bin/neotranscoder
LIB=/usr/local/lib/neotranscoder
STATE_DIR=/var/lib/neotranscoder
BACKUP_DIR=$STATE_DIR/backups

usage() {
  echo "usage: update.sh --file /path/neotranscoder [--sha256 HEX]" >&2
  echo "       update.sh --url https://example/neotranscoder [--sha256 HEX]" >&2
  echo "       update.sh --bundle /path/to/release-dir [--sha256 HEX]" >&2
}

if [ "$(id -u)" -ne 0 ]; then
  echo "run as root" >&2
  exit 1
fi

SOURCE=
MODE=
SHA256=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --file)
      if [ "$#" -lt 2 ]; then
        usage
        exit 2
      fi
      MODE=file
      SOURCE=$2
      shift 2
      ;;
    --url)
      if [ "$#" -lt 2 ]; then
        usage
        exit 2
      fi
      MODE=url
      SOURCE=$2
      shift 2
      ;;
    --bundle)
      if [ "$#" -lt 2 ]; then
        usage
        exit 2
      fi
      MODE=bundle
      SOURCE=$2
      shift 2
      ;;
    --sha256)
      if [ "$#" -lt 2 ]; then
        usage
        exit 2
      fi
      SHA256=$2
      shift 2
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [ -z "$MODE" ] || [ -z "$SOURCE" ]; then
  usage
  exit 2
fi

if [ ! -x "$BIN" ]; then
  echo "neotranscoder is not installed at $BIN" >&2
  exit 1
fi

install -d -m 0755 "$LIB" "$BACKUP_DIR"
TMP=$(mktemp "$LIB/update.XXXXXX")
trap 'rm -f "$TMP"' EXIT

case "$MODE" in
  file)
    if [ ! -f "$SOURCE" ]; then
      echo "file not found: $SOURCE" >&2
      exit 1
    fi
    cp "$SOURCE" "$TMP"
    ;;
  bundle)
    if [ ! -f "$SOURCE/neotranscoder" ]; then
      echo "bundle binary not found: $SOURCE/neotranscoder" >&2
      exit 1
    fi
    cp "$SOURCE/neotranscoder" "$TMP"
    ;;
  url)
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL "$SOURCE" -o "$TMP"
    elif command -v wget >/dev/null 2>&1; then
      wget -qO "$TMP" "$SOURCE"
    else
      echo "curl or wget is required for --url updates" >&2
      exit 1
    fi
    ;;
esac

if [ -n "$SHA256" ]; then
  if command -v sha256sum >/dev/null 2>&1; then
    ACTUAL=$(sha256sum "$TMP" | awk '{print $1}')
  elif command -v shasum >/dev/null 2>&1; then
    ACTUAL=$(shasum -a 256 "$TMP" | awk '{print $1}')
  else
    echo "sha256sum or shasum is required for --sha256" >&2
    exit 1
  fi
  if [ "$ACTUAL" != "$SHA256" ]; then
    echo "checksum mismatch" >&2
    echo "expected: $SHA256" >&2
    echo "actual:   $ACTUAL" >&2
    exit 1
  fi
fi

chmod 0755 "$TMP"
if ! "$TMP" version >/dev/null 2>&1; then
  echo "downloaded file is not a runnable neotranscoder binary" >&2
  exit 1
fi

OLD_VERSION=$("$BIN" version 2>/dev/null || echo "unknown")
NEW_VERSION=$("$TMP" version)
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP="$BACKUP_DIR/neotranscoder.$STAMP"

cp "$BIN" "$BACKUP"
chmod 0755 "$BACKUP"
install -m 0755 "$TMP" "$BIN"

if systemctl is-enabled "$SERVICE" >/dev/null 2>&1 || systemctl is-active "$SERVICE" >/dev/null 2>&1; then
  if ! systemctl restart "$SERVICE"; then
    install -m 0755 "$BACKUP" "$BIN"
    systemctl restart "$SERVICE" >/dev/null 2>&1 || true
    echo "update failed; rolled back to previous binary" >&2
    exit 1
  fi
fi

if [ "$MODE" = "bundle" ]; then
  for script in install.sh update.sh uninstall.sh; do
    if [ -f "$SOURCE/$script" ]; then
      install -m 0755 "$SOURCE/$script" "$LIB/$script"
    fi
  done
fi

echo "NeoTranscoder updated"
echo "old: $OLD_VERSION"
echo "new: $NEW_VERSION"
echo "backup: $BACKUP"
