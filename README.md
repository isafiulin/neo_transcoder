# NeoTranscoder

NeoTranscoder is a single-node multicast transcoder manager for Linux servers.
It is designed for CPU-based transcoding hosts, especially servers built around
Intel Xeon-class processors without NVIDIA GPUs.

The project does not try to replace FFmpeg. NeoTranscoder is the control plane:
it validates configuration, probes incoming streams, starts FFmpeg processes,
tracks their runtime state, exposes an HTTP API, and serves a web interface.
FFmpeg and ffprobe do the actual media work.

## What It Is For

NeoTranscoder is intended for operators who need to receive multicast streams,
inspect codecs and tracks, select an encoding profile, and publish the result
back to multicast output.

Typical flow:

```text
UDP/RTP multicast input
  -> ffprobe stream inspection
  -> profile selection
  -> FFmpeg process
  -> MPEG-TS over UDP/RTP multicast output
```

The deployment model is intentionally simple:

```text
one binary
one systemd service
one config file
one local state directory
one web UI served by the same binary
```

No containers are required for the main production path. Multicast networking,
systemd, logs, process limits, and hardware access are easier to debug directly
on the host.

## Architecture

```text
Browser / Web UI
      |
      | HTTP API
      v
NeoTranscoder daemon
      |
      | starts and supervises
      v
FFmpeg / ffprobe
      |
      v
Multicast input/output
```

The daemon is responsible for:

- loading and validating configuration;
- exposing the HTTP API;
- serving the web UI;
- running `ffprobe` for stream inspection;
- building safe FFmpeg argument lists;
- starting and stopping FFmpeg processes;
- tracking stream state such as status, PID, start time, stop time, and errors;
- exposing diagnostics through `/api/doctor`;
- integrating with systemd.

The web UI is a client of the API. It does not touch Linux services or FFmpeg
directly.

## Web UI

The management UI is a Flutter Web application embedded into the Go binary.

UI stack:

```text
Flutter Web
Dio
go_router
Path URL strategy
Material widgets
```

The UI uses a light operator-dashboard style: white surfaces, restrained
tables, compact controls, and NeoTelecom blue as the primary color.

Main UI workflows:

- live dashboard with stream status, media metrics, and process metrics;
- stream create/edit/delete;
- stream start/stop/restart;
- input stream probe;
- FFmpeg command preview;
- profile create/edit/delete;
- recent logs with filtering;
- service settings overview.

Source layout:

```text
ui/lib/app
ui/lib/core/api
ui/lib/core/design_system
ui/lib/core/widgets
ui/lib/features/dashboard
ui/lib/features/streams
ui/lib/features/profiles
ui/lib/features/logs
ui/lib/features/settings
```

## Filesystem Layout

Default Linux layout:

```text
/usr/local/bin/neotranscoder
/etc/systemd/system/neotranscoder.service
/etc/neotranscoder/config.json
/var/lib/neotranscoder/state.json
/var/log/neotranscoder/
```

Optional bundled FFmpeg layout, if a release decides to ship its own FFmpeg:

```text
/opt/neotranscoder/bin/ffmpeg
/opt/neotranscoder/bin/ffprobe
```

The current configuration format is JSON because it is supported by the Go
standard library without extra dependencies. YAML can be added later if operator
workflows require it.

## Configuration

Example:

```json
{
  "server": {
    "bind": "0.0.0.0",
    "port": 8080
  },
  "auth": {
    "token": "change-me"
  },
  "ffmpeg": {
    "path": "/usr/bin/ffmpeg",
    "ffprobe_path": "/usr/bin/ffprobe"
  },
  "storage": {
    "path": "/var/lib/neotranscoder/state.json"
  },
  "logs": {
    "level": "info",
    "path": "/var/log/neotranscoder/neotranscoder.log"
  }
}
```

Validate configuration:

```sh
neotranscoder config validate --config /etc/neotranscoder/config.json
```

Write a default config:

```sh
neotranscoder config write-default --config /etc/neotranscoder/config.json
```

If `auth.token` is empty, API authentication is disabled. For production,
set a long random token and use it in the web login screen or curl requests:

```sh
curl -H "Authorization: Bearer <token>" http://server:8080/api/streams
```

The web login screen stores the token in browser local storage. If auth is
disabled in the daemon config, the UI can continue without a token.

## System Service

NeoTranscoder is designed to run as a systemd service:

```sh
systemctl start neotranscoder
systemctl stop neotranscoder
systemctl restart neotranscoder
systemctl status neotranscoder
```

Logs:

```sh
journalctl -u neotranscoder -f
```

## Installation

A Linux host must have a few system prerequisites before installing
NeoTranscoder.

### Supported Host

Initial production target:

```text
Linux amd64
systemd
FFmpeg
ffprobe
```

Check CPU architecture:

```sh
uname -m
```

Expected value for Intel Xeon servers:

```text
x86_64
```

Check systemd:

```sh
systemctl --version
```

Check FFmpeg:

```sh
ffmpeg -version
ffprobe -version
```

### Install Dependencies On Debian Or Ubuntu

```sh
sudo apt-get update
sudo apt-get install -y ffmpeg ca-certificates curl
```

Useful diagnostics tools:

```sh
sudo apt-get install -y iproute2 net-tools tcpdump
```

### Install Dependencies On RHEL, Rocky, AlmaLinux, Or CentOS Stream

Enable EPEL and RPM Fusion/CRB repositories as required by your distribution,
then install FFmpeg.

Rocky/AlmaLinux 9 example:

```sh
sudo dnf install -y epel-release
sudo dnf config-manager --set-enabled crb
sudo dnf install -y https://mirrors.rpmfusion.org/free/el/rpmfusion-free-release-9.noarch.rpm
sudo dnf install -y ffmpeg ffmpeg-devel ca-certificates curl
```

Useful diagnostics tools:

```sh
sudo dnf install -y iproute tcpdump net-tools
```

### Multicast Host Checks

NeoTranscoder does not configure multicast routing for the host. Before running
production streams, verify the server can receive the input multicast group and
send to the output multicast group on the expected interface.

Show interfaces:

```sh
ip addr
```

Show routes:

```sh
ip route
```

Inspect multicast traffic on an interface:

```sh
sudo tcpdump -ni eth0 udp
```

Replace `eth0` with the actual network interface.

If the host has multiple interfaces, use FFmpeg URLs with `localaddr` where
needed:

```text
udp://239.1.1.1:1234?localaddr=10.0.0.5
```

### FFmpeg Smoke Check

Probe an input stream:

```sh
ffprobe -v error -show_streams -show_format -print_format json "udp://239.1.1.1:1234?localaddr=10.0.0.5"
```

If this command does not see the stream, fix host networking before debugging
NeoTranscoder.

A release bundle contains:

```text
neotranscoder
install.sh
uninstall.sh
```

Install or update:

```sh
sudo ./install.sh
```

The installer:

- creates the `neotranscoder` system user if needed;
- installs `/usr/local/bin/neotranscoder`;
- creates `/etc/neotranscoder`;
- creates `/var/lib/neotranscoder`;
- creates `/var/log/neotranscoder`;
- installs `neotranscoder.service`;
- enables and starts the service.

Remove the program and service while keeping config, state, and logs:

```sh
sudo neotranscoder uninstall
```

Fully remove the program, service, config, state, logs, and system user:

```sh
sudo neotranscoder uninstall --purge
```

## Diagnostics

Run local checks:

```sh
neotranscoder doctor
```

The doctor command checks:

- FFmpeg path;
- ffprobe path;
- storage directory writability;
- log directory writability.

The same information is available through:

```text
GET /api/doctor
```

Health check:

```text
GET /api/health
```

## API

Health and diagnostics:

```text
GET    /api/health
GET    /api/auth/required
GET    /api/doctor
GET    /api/events
GET    /api/metrics
GET    /api/logs
```

Probe input stream:

```text
POST   /api/probe
```

Request:

```json
{
  "input_url": "udp://239.1.1.1:1234?localaddr=10.0.0.5"
}
```

Profiles:

```text
GET    /api/profiles
POST   /api/profiles
GET    /api/profiles/{name}
PUT    /api/profiles/{name}
DELETE /api/profiles/{name}
```

Create or update a profile:

```json
{
  "name": "h264_fast_6m",
  "video": {
    "codec": "libx264",
    "preset": "fast",
    "tune": "zerolatency",
    "bitrate": "6000k",
    "maxrate": "6000k",
    "bufsize": "12000k"
  },
  "audio": {
    "codec": "aac",
    "bitrate": "128k"
  },
  "output": {
    "format": "mpegts"
  }
}
```

Streams:

```text
GET    /api/streams
POST   /api/streams
GET    /api/streams/{id}
PUT    /api/streams/{id}
DELETE /api/streams/{id}
```

Stream actions:

```text
POST   /api/streams/{id}/start
POST   /api/streams/{id}/stop
POST   /api/streams/{id}/restart
GET    /api/streams/{id}/ffmpeg-command
GET    /api/streams/{id}/logs
```

Create or update a stream:

```json
{
  "id": "channel_1",
  "name": "Channel 1",
  "input_url": "udp://239.1.1.1:1234?localaddr=10.0.0.5",
  "output_url": "udp://239.2.2.2:1234?pkt_size=1316",
  "profile_name": "h264_veryfast_4m",
  "enabled": true,
  "restart": {
    "enabled": true,
    "max_attempts": 5,
    "window_seconds": 300,
    "backoff_seconds": 5
  }
}
```

Profiles and stream definitions are persisted in the local JSON state file
configured by `storage.path`. Runtime process state such as PID and current
errors is rebuilt when the daemon starts.

If an FFmpeg process exits unexpectedly and the stream is enabled, NeoTranscoder
can restart it with a small backoff. If the process exceeds `max_attempts`
inside `window_seconds`, the stream is marked as `flapping` and automatic
restarts stop until an operator starts the stream again.

Automatic restart can be disabled per stream:

```json
{
  "restart": {
    "enabled": false
  }
}
```

Live events are exposed through Server-Sent Events:

```text
GET /api/events
```

Event payload shape:

```json
{
  "type": "stream_state",
  "stream_id": "channel_1",
  "time": "2026-06-30T12:00:00Z",
  "payload": {
    "status": "running",
    "pid": 12345
  }
}
```

Recent logs are kept in memory for fast UI access:

```text
GET /api/logs?limit=200
GET /api/streams/channel_1/logs?limit=200
```

FFmpeg stderr lines are captured as stream log entries and also emitted through
`/api/events` as `stream_log` events.

Common errors are classified into stable codes for UI filtering and highlighting:

```text
process_exit
input_error
output_error
bind_error
network_error
codec_error
permission_error
unknown_error
```

The stream state exposes the latest code as `error_code`. Log entries can also
include `code` when a line matches a known error category.

Runtime metrics are collected from FFmpeg's structured progress output:

```text
-progress pipe:1
```

The current metrics include:

Media metrics:

- frame;
- fps;
- bitrate;
- total output size;
- output time;
- speed;
- last progress state.

Process metrics:

- FFmpeg CPU percent;
- FFmpeg RSS memory bytes.

Snapshot endpoint:

```text
GET /api/metrics
```

Process metrics are read from Linux `/proc`. CPU percent is calculated from
process CPU ticks between one-second samples. Values can exceed `100` when
FFmpeg uses multiple CPU cores.

## Encoding Stack

Default encoding profile:

```text
video:  libx264
preset: veryfast
tune:   zerolatency
rate:   4000k
audio:  aac 128k
output: mpegts
```

Generated FFmpeg shape:

```text
ffmpeg
  -hide_banner
  -nostdin
  -progress pipe:1
  -stats_period 1
  -i udp://239.1.1.1:1234?localaddr=10.0.0.5
  -map 0:v:0
  -map 0:a:0?
  -c:v libx264
  -preset veryfast
  -tune zerolatency
  -b:v 4000k
  -maxrate 4000k
  -bufsize 8000k
  -c:a aac
  -b:a 128k
  -f mpegts
  udp://239.2.2.2:1234?pkt_size=1316
```

Only UDP and RTP URLs are accepted by the initial argument builder. Additional
protocols such as SRT, RTMP, HLS, or file outputs can be added explicitly when
they become product requirements.

## Development

Requirements:

- Go;
- Flutter;
- FFmpeg;
- ffprobe.

Useful commands:

```sh
go test ./...
go run ./cmd/neotranscoder version
go run ./cmd/neotranscoder config validate --config ./config.example.json
go run ./cmd/neotranscoder serve --config ./config.example.json
```

Build the Flutter Web UI and embed it into the Go binary static assets:

```sh
./scripts/build-ui.sh
```

Build a local release bundle:

```sh
VERSION=0.1.0 ./scripts/build-release.sh
```

The generated bundle is written to:

```text
dist/neotranscoder/
```

## Security Notes

NeoTranscoder starts external FFmpeg processes. Treat stream URLs and profile
settings as trusted operator input unless authentication and authorization are
enabled in the deployment.

FFmpeg commands are built as an argument array, not as a shell string. This
avoids shell interpolation and quoting bugs.

Do not expose the management HTTP port to untrusted networks without an
authentication layer or a trusted reverse proxy.
