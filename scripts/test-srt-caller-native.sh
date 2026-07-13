#!/bin/sh
set -eu

WORKER=${WORKER:-${1:-./neotranscoder-srt-worker}}
FFMPEG=${FFMPEG:-ffmpeg}
FFPROBE=${FFPROBE:-ffprobe}
TIMEOUT=${TIMEOUT:-timeout}
SRT_PORT=${SRT_PORT:-19001}
MULTICAST_PORT=${MULTICAST_PORT:-12341}
TMP=$(mktemp -d)
WORKER_PID=
RECEIVER_PID=
GENERATOR_PID=

cleanup() {
  for pid in "$GENERATOR_PID" "$WORKER_PID" "$RECEIVER_PID"; do
    if [ -n "$pid" ]; then kill "$pid" >/dev/null 2>&1 || true; fi
  done
  wait >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

[ "$(uname -s)" = Linux ] || { echo "Linux is required" >&2; exit 1; }
for command in "$WORKER" "$FFMPEG" "$FFPROBE" "$TIMEOUT"; do
  command -v "$command" >/dev/null 2>&1 || [ -x "$command" ] || {
    echo "required executable not found: $command" >&2; exit 1;
  }
done

cat >"$TMP/config.json" <<EOF
{"relay":{"id":"caller-smoke","direction":"publish","input_url":"udp://239.255.42.43:${MULTICAST_PORT}","network_interface":"lo","destination_address":"127.0.0.1","destination_port":${SRT_PORT},"stream_id":"caller-smoke","encryption_mode":"aes-256","latency_ms":120,"payload_size":1316,"max_clients":1,"input_timeout_seconds":5,"enabled":true},"publish_passphrase":"caller-native-secure-passphrase"}
EOF

"$TIMEOUT" 20 "$FFMPEG" -y -hide_banner -loglevel error -rw_timeout 15000000 \
  -i "srt://0.0.0.0:${SRT_PORT}?mode=listener&transtype=live&passphrase=caller-native-secure-passphrase&pbkeylen=32&latency=120" \
  -t 3 -map 0 -c copy -f mpegts "$TMP/received.ts" &
RECEIVER_PID=$!
sleep 1
"$WORKER" --config-stdin <"$TMP/config.json" >"$TMP/events.jsonl" 2>"$TMP/worker.err" &
WORKER_PID=$!

attempt=0
until grep -q '"type":"relay_ready"' "$TMP/events.jsonl" 2>/dev/null; do
  attempt=$((attempt + 1))
  [ "$attempt" -lt 50 ] && kill -0 "$WORKER_PID" 2>/dev/null || {
    cat "$TMP/worker.err" >&2; exit 1;
  }
  sleep 0.1
done

"$FFMPEG" -hide_banner -loglevel error -re -f lavfi \
  -i testsrc=size=320x180:rate=25 -f lavfi -i sine=frequency=1000:sample_rate=48000 \
  -c:v mpeg2video -b:v 1000k -c:a mp2 -b:a 128k -f mpegts \
  "udp://239.255.42.43:${MULTICAST_PORT}?pkt_size=1316&localaddr=127.0.0.1&ttl=1" &
GENERATOR_PID=$!
wait "$RECEIVER_PID"
RECEIVER_PID=

[ -s "$TMP/received.ts" ] || { echo "caller output is empty" >&2; exit 1; }
"$FFPROBE" -v error -show_entries stream=codec_type -of csv=p=0 "$TMP/received.ts" | grep -q video
grep '"type":"session_connected"' "$TMP/events.jsonl" | grep -q '"encrypted":true'
echo "native SRT caller test passed"
