#!/bin/sh
set -eu

SERVICE=neotranscoder
BIN=/usr/local/bin/neotranscoder
LIB=/usr/local/lib/neotranscoder
CONFIG_DIR=/etc/neotranscoder
STATE_DIR=/var/lib/neotranscoder
LOG_DIR=/var/log/neotranscoder
UNIT=/etc/systemd/system/neotranscoder.service
BACKUP_DIR=/var/lib/neotranscoder/backups

if [ "$(id -u)" -ne 0 ]; then
  echo "run as root" >&2
  exit 1
fi

if [ ! -x "./neotranscoder" ]; then
  echo "expected ./neotranscoder binary next to install.sh" >&2
  exit 1
fi
if [ ! -f "./uninstall.sh" ]; then
  echo "expected ./uninstall.sh next to install.sh" >&2
  exit 1
fi
if [ ! -f "./update.sh" ]; then
  echo "expected ./update.sh next to install.sh" >&2
  exit 1
fi

if ! id "$SERVICE" >/dev/null 2>&1; then
  useradd --system --home "$STATE_DIR" --shell /usr/sbin/nologin "$SERVICE"
fi

install -d -m 0755 "$CONFIG_DIR" "$STATE_DIR" "$LOG_DIR" "$LIB" "$BACKUP_DIR"
if [ -x "$BIN" ]; then
  cp "$BIN" "$BACKUP_DIR/neotranscoder.$(date -u +%Y%m%dT%H%M%SZ)"
fi
install -m 0755 ./neotranscoder "$BIN"
install -m 0755 ./uninstall.sh "$LIB/uninstall.sh"
install -m 0755 ./update.sh "$LIB/update.sh"

if [ ! -f "$CONFIG_DIR/config.json" ]; then
  "$BIN" config write-default --config "$CONFIG_DIR/config.json"
fi

cat > "$UNIT" <<'UNIT'
[Unit]
Description=NeoTranscoder multicast transcoder manager
After=network-online.target
Wants=network-online.target

[Service]
User=neotranscoder
Group=neotranscoder
ExecStart=/usr/local/bin/neotranscoder serve --config /etc/neotranscoder/config.json
Restart=always
RestartSec=5
LimitNOFILE=1048576
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
UNIT

chown -R "$SERVICE:$SERVICE" "$STATE_DIR" "$LOG_DIR"
systemctl daemon-reload
systemctl enable --now "$SERVICE"
echo "NeoTranscoder installed: systemctl status $SERVICE"
