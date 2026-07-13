#!/bin/sh
set -eu

WORKER=${WORKER:-${1:-./neotranscoder-srt-worker}}
FFMPEG=${FFMPEG:-ffmpeg}
FFPROBE=${FFPROBE:-ffprobe}
TIMEOUT=${TIMEOUT:-timeout}
MULTICAST_IP=${MULTICAST_IP:-239.255.42.42}
MULTICAST_PORT=${MULTICAST_PORT:-12340}
SRT_PORT=${SRT_PORT:-19000}
INTERFACE=${INTERFACE:-lo}
ROUNDS=${ROUNDS:-1}
RECEIVE_SECONDS=${RECEIVE_SECONDS:-3}
MAX_RSS_GROWTH_KB=${MAX_RSS_GROWTH_KB:-0}
MAX_FD_GROWTH=${MAX_FD_GROWTH:-16}

if [ "$(uname -s)" != "Linux" ]; then
  echo "native SRT test requires Linux" >&2
  exit 1
fi
for command in "$WORKER" "$FFMPEG" "$FFPROBE" "$TIMEOUT"; do
  if ! command -v "$command" >/dev/null 2>&1 && [ ! -x "$command" ]; then
    echo "required executable not found: $command" >&2
    exit 1
  fi
done
if ! "$FFMPEG" -hide_banner -protocols 2>/dev/null | grep -q 'srt'; then
  echo "ffmpeg was built without SRT protocol support" >&2
  exit 1
fi

TMP=$(mktemp -d)
WORKER_PID=
GENERATOR_PID=
cleanup() {
  if [ -n "$GENERATOR_PID" ]; then kill "$GENERATOR_PID" >/dev/null 2>&1 || true; fi
  if [ -n "$WORKER_PID" ]; then kill "$WORKER_PID" >/dev/null 2>&1 || true; fi
  wait >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

cat > "$TMP/config.json" <<EOF
{
  "relay": {
    "id": "native-smoke",
    "input_url": "udp://${MULTICAST_IP}:${MULTICAST_PORT}",
    "network_interface": "${INTERFACE}",
    "bind_address": "127.0.0.1",
    "port": ${SRT_PORT},
    "latency_ms": 120,
    "payload_size": 1316,
    "max_clients": 4,
    "input_timeout_seconds": 5,
    "allow_missing_stream_id": true,
    "default_client_id": "no-key-client",
    "enabled": true
  },
  "clients": [
    {
      "id": "smoke-client",
      "passphrase": "native-smoke-correct-passphrase",
      "allowed_cidrs": ["127.0.0.1/32"],
      "max_sessions": 1
    },
    {
      "id": "bad-key-client",
      "passphrase": "native-smoke-second-passphrase",
      "allowed_cidrs": ["127.0.0.1/32"],
      "max_sessions": 1
    },
    {
      "id": "no-key-client",
      "encryption_mode": "none",
      "allowed_cidrs": ["127.0.0.1/32"],
      "max_sessions": 1
    }
  ]
}
EOF

"$WORKER" --config-stdin < "$TMP/config.json" > "$TMP/events.jsonl" 2> "$TMP/worker.err" &
WORKER_PID=$!
attempt=0
until grep -q '"type":"relay_ready"' "$TMP/events.jsonl" 2>/dev/null; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 50 ] || ! kill -0 "$WORKER_PID" 2>/dev/null; then
    cat "$TMP/worker.err" >&2
    echo "SRT worker did not become ready" >&2
    exit 1
  fi
  sleep 0.1
done

"$FFMPEG" -hide_banner -loglevel error -re \
  -f lavfi -i testsrc=size=320x180:rate=25 \
  -f lavfi -i sine=frequency=1000:sample_rate=48000 \
  -c:v mpeg2video -b:v 1000k -c:a mp2 -b:a 128k -f mpegts \
  "udp://${MULTICAST_IP}:${MULTICAST_PORT}?pkt_size=1316&localaddr=127.0.0.1&ttl=1" &
GENERATOR_PID=$!
sleep 1

BAD_URL="srt://127.0.0.1:${SRT_PORT}?mode=caller&transtype=live&streamid=bad-key-client&passphrase=definitely-wrong-passphrase&pbkeylen=32&latency=120"
if "$TIMEOUT" 6 "$FFMPEG" -hide_banner -loglevel error -rw_timeout 5000000 \
  -i "$BAD_URL" -t 1 -f null - >/dev/null 2>&1; then
  echo "connection with an invalid SRT passphrase unexpectedly succeeded" >&2
  exit 1
fi

rss_before=$(awk '/VmRSS:/ {print $2}' "/proc/$WORKER_PID/status")
fd_before=$(find "/proc/$WORKER_PID/fd" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)
round=1
GOOD_URL="srt://127.0.0.1:${SRT_PORT}?mode=caller&transtype=live&streamid=smoke-client&passphrase=native-smoke-correct-passphrase&pbkeylen=32&latency=120"
while [ "$round" -le "$ROUNDS" ]; do
  output="$TMP/received-${round}.ts"
  "$TIMEOUT" $((RECEIVE_SECONDS + 10)) "$FFMPEG" -hide_banner -loglevel error \
    -rw_timeout 5000000 -i "$GOOD_URL" -t "$RECEIVE_SECONDS" -map 0 -c copy \
    -f mpegts "$output"
  if [ ! -s "$output" ]; then
    echo "round $round produced an empty MPEG-TS output" >&2
    exit 1
  fi
  streams=$("$FFPROBE" -v error -show_entries stream=codec_type -of csv=p=0 "$output")
  echo "$streams" | grep -q video
  echo "$streams" | grep -q audio
  round=$((round + 1))
done

NO_KEY_OUTPUT="$TMP/received-no-key.ts"
NO_KEY_URL="srt://127.0.0.1:${SRT_PORT}?mode=caller&transtype=live&latency=120"
"$TIMEOUT" $((RECEIVE_SECONDS + 10)) "$FFMPEG" -hide_banner -loglevel error \
  -rw_timeout 5000000 -i "$NO_KEY_URL" -t "$RECEIVE_SECONDS" -map 0 -c copy \
  -f mpegts "$NO_KEY_OUTPUT"
if [ ! -s "$NO_KEY_OUTPUT" ]; then
  echo "unencrypted SRT session produced an empty MPEG-TS output" >&2
  exit 1
fi
sleep 1

connected=$(grep -c '"type":"session_connected"' "$TMP/events.jsonl" || true)
encrypted=$(grep '"type":"session_connected"' "$TMP/events.jsonl" | grep -c '"encrypted":true' || true)
unencrypted=$(grep '"type":"session_connected"' "$TMP/events.jsonl" | grep '"client_id":"no-key-client"' | grep -c '"encrypted":false' || true)
if [ "$connected" -lt $((ROUNDS + 1)) ] || [ "$encrypted" -lt "$ROUNDS" ] || [ "$unencrypted" -lt 1 ]; then
  cat "$TMP/events.jsonl" >&2
  echo "missing encrypted or unencrypted session lifecycle events" >&2
  exit 1
fi

rss_after=$(awk '/VmRSS:/ {print $2}' "/proc/$WORKER_PID/status")
fd_after=$(find "/proc/$WORKER_PID/fd" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)
rss_growth=$((rss_after - rss_before))
fd_growth=$((fd_after - fd_before))
if [ "$MAX_RSS_GROWTH_KB" -gt 0 ] && [ "$rss_growth" -gt "$MAX_RSS_GROWTH_KB" ]; then
  echo "worker RSS grew by ${rss_growth} KiB (limit ${MAX_RSS_GROWTH_KB})" >&2
  exit 1
fi
if [ "$fd_growth" -gt "$MAX_FD_GROWTH" ]; then
  echo "worker FD count grew by $fd_growth (limit $MAX_FD_GROWTH)" >&2
  exit 1
fi

echo "native SRT test passed"
echo "rounds=$ROUNDS encrypted_sessions=$encrypted unencrypted_sessions=$unencrypted rss_growth_kib=$rss_growth fd_growth=$fd_growth"
