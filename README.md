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

## Filesystem Layout

Default Linux layout:

```text
/usr/local/bin/neotranscoder
/etc/systemd/system/neotranscoder.service
/etc/neotranscoder/config.json
/var/lib/neotranscoder/neotranscoder.db
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
  "ffmpeg": {
    "path": "/usr/bin/ffmpeg",
    "ffprobe_path": "/usr/bin/ffprobe"
  },
  "storage": {
    "path": "/var/lib/neotranscoder/neotranscoder.db"
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
GET    /api/doctor
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
```

Create or update a stream:

```json
{
  "id": "channel_1",
  "name": "Channel 1",
  "input_url": "udp://239.1.1.1:1234?localaddr=10.0.0.5",
  "output_url": "udp://239.2.2.2:1234?pkt_size=1316",
  "profile_name": "h264_veryfast_4m",
  "enabled": true
}
```

The current implementation keeps stream definitions in memory. Persistent local
storage is planned through the existing `storage.path` setting.

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
- FFmpeg;
- ffprobe.

Useful commands:

```sh
go test ./...
go run ./cmd/neotranscoder version
go run ./cmd/neotranscoder config validate --config ./config.example.json
go run ./cmd/neotranscoder serve --config ./config.example.json
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
