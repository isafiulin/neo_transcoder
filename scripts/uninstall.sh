#!/bin/sh
set -eu

PURGE=0
if [ "${1:-}" = "--purge" ]; then
  PURGE=1
fi

SERVICE=neotranscoder

if [ "$(id -u)" -ne 0 ]; then
  echo "run as root" >&2
  exit 1
fi

systemctl stop "$SERVICE" >/dev/null 2>&1 || true
systemctl disable "$SERVICE" >/dev/null 2>&1 || true
rm -f /etc/systemd/system/neotranscoder.service
systemctl daemon-reload >/dev/null 2>&1 || true

rm -f /usr/local/bin/neotranscoder
rm -rf /usr/local/lib/neotranscoder

if [ "$PURGE" -eq 1 ]; then
  rm -rf /etc/neotranscoder /var/lib/neotranscoder /var/log/neotranscoder
  userdel neotranscoder >/dev/null 2>&1 || true
  echo "NeoTranscoder fully removed"
else
  echo "NeoTranscoder removed; config/state/logs kept. Use --purge to remove data."
fi
