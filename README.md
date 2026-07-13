# NeoTranscoder

NeoTranscoder is a single-node multicast transcoder and secure SRT delivery
manager for Linux servers.
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

It can also forward a UDP multicast MPEG-TS input unchanged to authenticated
SRT callers on the internet. This relay path does not decode or transcode the
media and does not use FFmpeg.

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
one release bundle (daemon plus static SRT worker)
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

NeoTranscoder daemon
      |
      | starts and supervises
      v
Static libsrt worker
      |
      v
UDP multicast MPEG-TS -> encrypted SRT callers
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
- supervising isolated SRT relay workers and applying per-client access policy;
- recording SRT connection attempts, rejections, sessions, and operator actions
  in a separate audit journal.

The web UI is a client of the API. It does not touch Linux services or FFmpeg
directly.

## Web UI

The management UI is a Flutter Web application embedded into the Go binary.

UI stack:

```text
Flutter Web
Dio
go_router
flutter_bloc / Cubit
Path URL strategy
Material widgets
```

The UI uses a light operator-dashboard style: white surfaces, restrained
tables, compact controls, and NeoTelecom blue as the primary color.
Feature screens keep UI rendering separate from state and business logic:
`BlocBuilder` renders immutable Cubit state, Cubits call repositories, and
repositories call the HTTP API through Dio.

Routes are declared through `AppRoutes` instead of hardcoded strings. Flutter
uses path URL strategy, and the Go daemon serves unknown web paths through the
SPA fallback, so browser refresh keeps the current page when local
authentication state is valid. App startup goes through a splash route while
the UI verifies or refreshes the local session; after that the router sends the
operator either to login or back to the originally requested URL.

Main UI workflows:

- live dashboard with encoding and SRT relay status, media metrics, active SRT
  listeners, multicast input health, and process metrics;
- stream create/edit/delete;
- stream start/stop/restart;
- input stream probe;
- FFmpeg command preview;
- profile create/edit/delete;
- recent logs with filtering;
- service settings overview;
- SRT relay, access-client, live-session, and audit management.

Source layout:

```text
ui/lib/app
ui/lib/core/api
ui/lib/core/design_system
ui/lib/core/state
ui/lib/core/widgets
ui/lib/data/repositories
ui/lib/features/dashboard
ui/lib/features/streams
ui/lib/features/profiles
ui/lib/features/logs
ui/lib/features/settings
ui/lib/features/srt
```

## SRT Relay

The SRT module is for contribution and distribution where an existing UDP
multicast MPEG-TS must be sent over an untrusted IP network without changing
the elementary streams:

```text
239.10.10.1:1234 UDP multicast MPEG-TS
  -> NeoTranscoder SRT worker
  -> Publish: SRT Caller -> partner public IP:port (partner is Listener)
  -> Accept: local SRT Listener <- one or more partner Callers
```

`publish` is the normal point-to-point delivery mode: NeoTranscoder initiates
one outgoing connection to a literal partner destination IP and UDP port. The
partner must run an SRT Listener. `listener` keeps the inbound distribution
mode: NeoTranscoder binds a local UDP port and partner Callers connect to it.
Old relay records without `direction` remain `listener` for compatibility.

Each relay has its own worker process. One slow receiver cannot block multicast
ingestion: every session has a bounded queue. The manager restarts failed
workers with bounded backoff and marks repeated failures as flapping. Enabled
relays start automatically with `neotranscoder.service`.
When multicast packets stop for the relay's configured timeout, runtime state
becomes `degraded` and one `input_stalled` audit event is written. The SRT
endpoint stays online and state returns to `running` with one `input_restored`
event as soon as packets resume.

Inbound Listener access is deny-by-default and evaluated during the handshake:

- strict mode requires the caller to send a configured client ID as SRT Stream ID;
- the source address must match that client's IP/CIDR allowlist;
- the client must be enabled and assigned to the requested relay;
- per-client and per-relay concurrent session limits must allow the connection;
- the selected security mode is either AES-256 plus IP ACL, or IP ACL only.

AES-256 is the default and remains the mode for clients stored by older
NeoTranscoder versions. Its passphrase is derived from a random local master
key and client key version. It is never stored in the browser or persisted in
plaintext. The UI displays it once after client creation, key rotation, or a
change from unencrypted to AES-256. Rotating a key restarts assigned running
relays, disconnects their current sessions, and invalidates the old key.

The caller Stream ID may be the plain client ID (`partner-a`) or SRT access
control syntax such as `#!::u=partner-a,m=request`. A receiver URL is typically:

```text
srt://public.example.net:9000?mode=caller&transtype=live&streamid=partner-a&passphrase=<one-time-key>&pbkeylen=32
```

For a legacy receiver configured as `IP ACL only`, omit both encryption
parameters:

```text
srt://public.example.net:9000?mode=caller&transtype=live&streamid=partner-legacy
```

Open the relay's UDP port in the host and upstream firewall. If the server is
behind NAT, forward that UDP port to the relay bind address. Configure the ACL
with the source IP seen by the server after NAT, not an address local to the
receiver. Stream ID is an identifier, not a secret. For an unencrypted client,
any caller sharing an allowed public NAT address can claim that Stream ID, so a
dedicated partner IP and a host/edge firewall allowlist are strongly preferred.
NeoTranscoder rejects `0.0.0.0/0` and `::/0` for unencrypted clients. Broad
packet-flood limits belong in nftables/firewalld or the edge firewall; the
worker also applies a bounded per-IP handshake limiter to prevent audit-log
amplification.

Listener compatibility mode is opt-in for VLC and legacy receivers that cannot
send a Stream ID. Set `allow_missing_stream_id` and select one explicit
`default_client_id`. A caller with no Stream ID is evaluated only against that
client's enabled state, relay assignment, IP/CIDR ACL, session limit, and
encryption key. NeoTranscoder never guesses a client from overlapping ACLs.
The selected client cannot be disabled, detached, or deleted until compatibility
mode is disabled or another default is selected. With AES-256 the minimal URL is:

```text
srt://public.example.net:9000?passphrase=<one-time-key>
```

For an `IP ACL only` default client, the URL can be just
`srt://public.example.net:9000`.

The current SRT relay input contract is raw UDP multicast MPEG-TS. `rtp://` is
rejected because forwarding RTP headers as TS would corrupt the output. RTP
header parsing can be added later as a separate input mode.

SRT audit data is separate from FFmpeg/application logs:

```text
/var/log/neotranscoder/srt-audit/srt-audit-YYYY-MM-DD.jsonl
```

It records connection attempts, rejection reason, remote IP/port, Stream ID,
client, relay, peer version, encryption state, session lifecycle, final stats,
multicast `input_stalled` and `input_restored` transitions, worker failures,
and operator configuration actions. Files are mode `0600`, synced on append,
rotated daily, and removed after the configured retention (90 days by default).
The dashboard receives relay metrics and session lifecycle changes through SSE;
it does not poll once per second. Each SRT card links directly to the audit view
filtered for that relay.

On the server, use:

```sh
journalctl -u neotranscoder -f
tail -f /var/log/neotranscoder/neotranscoder.log
tail -f /var/log/neotranscoder/srt-audit/srt-audit-$(date +%F).jsonl
```

The first two contain daemon lifecycle, worker stderr, startup failures, and
service diagnostics. The SRT audit answers who attempted to connect, whether
the attempt was accepted, why it was rejected, when a listener disconnected,
and when multicast input disappeared or recovered. A stalled input changes the
relay to `degraded` after `input_timeout_seconds` (10 seconds by default) but
keeps the SRT listener online.

## Filesystem Layout

Default Linux layout:

```text
/usr/local/bin/neotranscoder
/usr/local/lib/neotranscoder/neotranscoder-srt-worker
/etc/systemd/system/neotranscoder.service
/etc/neotranscoder/config.json
/var/lib/neotranscoder/state.json
/var/lib/neotranscoder/srt-state.json
/var/lib/neotranscoder/srt-master.key
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
    "ffprobe_path": "/usr/bin/ffprobe",
    "log_level": "warning",
    "udp": {
      "buffer_size": 8388608,
      "fifo_size": 100000000,
      "overrun_nonfatal": true,
      "reuse": true,
      "pkt_size": 1316
    },
    "probe": {
      "analyzeduration": 10000000,
      "probesize": 20000000
    }
  },
  "storage": {
    "path": "/var/lib/neotranscoder/state.json"
  },
  "logs": {
    "level": "info",
    "path": "/var/log/neotranscoder/neotranscoder.log"
  },
  "srt": {
    "worker_path": "/usr/local/lib/neotranscoder/neotranscoder-srt-worker",
    "state_path": "/var/lib/neotranscoder/srt-state.json",
    "master_key_path": "/var/lib/neotranscoder/srt-master.key",
    "audit_dir": "/var/log/neotranscoder/srt-audit",
    "audit_retention_days": 90
  }
}
```

`ffmpeg.udp.*` and `ffmpeg.probe.*` are system-level UDP transport tuning for
multicast IPTV delivery and input probing — safe by construction, since
neither touches the encoder. They are not part of an encoding profile and are
not editable per stream; every stream started by this daemon picks them up
automatically. Omitting a field from `config.json` keeps its default, shown
above.

Encode-affecting flags (`-fflags`, `-err_detect`, `-g`/`-keyint_min`/
`-sc_threshold`, `-threads`, `-minrate`, `-x264-params`) are **not** part of
this system config and are never added by default — see `profile.advanced`
below. Enabling them unconditionally previously changed GOP structure and
corrupt-packet tolerance in ways that shifted output bitrate, which is why
they're opt-in per profile instead.

Validate configuration:

```sh
neotranscoder config validate --config /etc/neotranscoder/config.json
```

Write a default config:

```sh
neotranscoder config write-default --config /etc/neotranscoder/config.json
```

Authentication is managed by the backend, not by a static token in the config
file. On the first start NeoTranscoder creates a default local admin account:

```text
username: admin
password: 123456
```

That password must be changed after the first login. Users are stored in the
state file as password hashes together with the token signing secret. The state
file is sensitive and is written with `0600` permissions. The backend issues
short-lived bearer access tokens and refresh tokens after login. The web UI
stores those tokens in browser local storage.

API example:

```sh
curl -X POST http://server:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"123456"}'
```

Use the returned access token for protected API calls:

```sh
curl -H "Authorization: Bearer <access_token>" http://server:8080/api/streams
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
neotranscoder.sha256
neotranscoder-srt-worker
neotranscoder-srt-worker.sha256
install.sh
update.sh
uninstall.sh
```

Install:

```sh
sudo ./neotranscoder init
```

The init command asks for the management web port. Press Enter to keep the
default `8080`.

Non-interactive install with the default port:

```sh
sudo ./neotranscoder init --yes
```

Install with a custom management web port:

```sh
sudo ./neotranscoder init --port 18080
```

NeoTranscoder binds to all server IP addresses on the selected port
(`0.0.0.0:<port>`).

If `/etc/neotranscoder/config.json` already exists, `--port` updates only the
`server` section. To recreate the default config before applying the port:

```sh
sudo ./neotranscoder init --force-config --port 18080
```

The release still includes shell scripts for compatibility. If the executable
bit is lost while copying the bundle, either run the binary-based installer
above or restore permissions:

```sh
chmod +x neotranscoder install.sh update.sh uninstall.sh
```

The binary-based `init` command does not execute shell scripts. When the helper
scripts are present next to the binary, it copies them into
`/usr/local/lib/neotranscoder` so later `neotranscoder update` and
`neotranscoder uninstall` commands keep working.

The installer:

- creates the `neotranscoder` system user if needed;
- installs `/usr/local/bin/neotranscoder`;
- installs the static SRT worker in `/usr/local/lib/neotranscoder` when it is
  present in the bundle;
- creates `/etc/neotranscoder`;
- creates `/var/lib/neotranscoder`;
- creates `/var/log/neotranscoder`;
- installs `neotranscoder.service`;
- runs non-fatal `neotranscoder doctor` checklist for FFmpeg, ffprobe, the SRT
  worker, storage/state paths, and log/audit paths;
- enables and starts the service.

The installer and service manager only operate on NeoTranscoder-owned paths:

```text
/usr/local/bin/neotranscoder
/usr/local/lib/neotranscoder
/etc/neotranscoder
/var/lib/neotranscoder
/var/log/neotranscoder
/etc/systemd/system/neotranscoder.service
```

No other services, system utilities, FFmpeg binaries, or network settings are
modified.

Update from an unpacked release bundle:

```sh
sudo neotranscoder update --bundle ./neotranscoder-release
```

If the installed version is too old to have the `update` command, run the
updater from the new bundle:

```sh
cd ./neotranscoder-release
sudo ./update.sh --bundle .
```

Bundle updates replace both versioned binaries and refresh the installed helper
scripts: `install.sh`, `update.sh`, and `uninstall.sh`. If service restart fails,
both binaries are rolled back. Use bundle updates when a release changes SRT;
`--file` and `--url` update only the main binary.

Update from a local binary:

```sh
sudo neotranscoder update --file ./neotranscoder
```

Update from a URL:

```sh
sudo neotranscoder update --url https://example.com/releases/neotranscoder-linux-amd64
```

For file and URL updates, checksum verification is optional but recommended:

```sh
sudo neotranscoder update \
  --url https://example.com/releases/neotranscoder-linux-amd64 \
  --sha256 0123456789abcdef...
```

The updater downloads or copies the new binary to a temporary file, optionally
verifies its SHA-256 checksum, verifies that it can run `neotranscoder version`,
stores a backup in `/var/lib/neotranscoder/backups`, atomically replaces
`/usr/local/bin/neotranscoder`, and restarts only `neotranscoder.service`. If the
service restart fails, the previous binary is restored and the service is
started again.

Remove the program and service while keeping config, state, and logs:

```sh
sudo neotranscoder uninstall
```

Fully remove the program, service, config, state, logs, backups, and system
user:

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
- that the SRT worker exists and can run its `version` command;
- storage directory writability;
- log directory writability;
- SRT state and audit directory writability.

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
POST   /api/auth/login
POST   /api/auth/refresh
GET    /api/auth/verify
POST   /api/auth/change-password
GET    /api/doctor
GET    /api/events
GET    /api/metrics
GET    /api/logs
```

User management:

```text
GET    /api/users
POST   /api/users
PUT    /api/users/{username}/password
DELETE /api/users/{username}
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

Profiles can also be template-based. Template profiles store an FFmpeg argument
array, not a shell command. The daemon replaces `${i}` with the input URL,
`${o}` with the output URL, and any additional `${name}` value from profile
defaults or stream `options`. Stream options override profile defaults.

Example template profile:

```json
{
  "name": "h264_ultrafast_template_4m",
  "template": {
    "args": [
      "-y",
      "-hide_banner",
      "-nostdin",
      "-i",
      "${i}?overrun_nonfatal=1&fifo_size=100000000",
      "-map",
      "0:v:0",
      "-map",
      "0:a:0",
      "-c:v",
      "libx264",
      "-preset",
      "${preset}",
      "-profile:v",
      "main",
      "-pix_fmt",
      "yuv420p",
      "-vf",
      "yadif",
      "-b:v",
      "${video_bitrate}",
      "-maxrate",
      "${video_bitrate}",
      "-bufsize",
      "${video_bufsize}",
      "-c:a",
      "aac",
      "-b:a",
      "${audio_bitrate}",
      "-ar",
      "48000",
      "-ac",
      "2",
      "-f",
      "mpegts",
      "${o}?pkt_size=1316"
    ],
    "defaults": {
      "preset": "ultrafast",
      "video_bitrate": "4M",
      "video_bufsize": "8M",
      "audio_bitrate": "128k"
    }
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
  "source_type": "multicast",
  "input_url": "udp://239.1.1.1:1234?localaddr=10.0.0.5",
  "output_url": "udp://239.2.2.2:1234?pkt_size=1316",
  "profile_name": "h264_veryfast_4m",
  "audio_maps": ["0:a:0"],
  "disable_audio": false,
  "logo": {
    "enabled": false,
    "path": "/opt/neotranscoder/assets/logo.png",
    "x": 20,
    "y": 20
  },
  "options": {
    "video_bitrate": "4M",
    "audio_bitrate": "128k"
  },
  "log_retention_seconds": 60,
  "log_level": "",
  "keep_stats": false,
  "enabled": true,
  "restart": {
    "enabled": true,
    "max_attempts": 5,
    "window_seconds": 300,
    "backoff_seconds": 5
  },
  "watchdog": {
    "enabled": true,
    "progress_timeout_seconds": 120,
    "max_memory_bytes": 0,
    "memory_grace_seconds": 30
  }
}
```

`source_type` can be:

```text
multicast
file
```

For file-to-multicast streams, set `source_type` to `file` and use a local file
path in `input_url`. The daemon adds `-re` so FFmpeg reads the file at realtime
speed and publishes it to the multicast `output_url`.

Audio selection is controlled by `audio_maps`. Use FFmpeg map expressions such
as `0:a:0` or `0:a:1`, one per selected track. Set `disable_audio` to `true` to
remove audio from the output.

Logo overlay is controlled by `logo`. When enabled, the daemon adds the logo as
a second FFmpeg input and overlays it on the selected video stream at `x:y`.

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

Each running FFmpeg process also has a lightweight watchdog. By default it
restarts the process if FFmpeg stops reporting structured `-progress` updates
for 120 seconds. A per-process memory cap is optional: set
`watchdog.max_memory_bytes` to a positive value, and NeoTranscoder will restart
FFmpeg only after RSS stays above that value for
`watchdog.memory_grace_seconds`. The default `max_memory_bytes: 0` means no
memory cap.

```json
{
  "watchdog": {
    "enabled": true,
    "progress_timeout_seconds": 120,
    "max_memory_bytes": 2147483648,
    "memory_grace_seconds": 30
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

Each stream can set `log_retention_seconds`. The default is `60`, which keeps
the web encoding journal short and prevents noisy FFmpeg output from filling the
in-memory recent log buffer. Server logs still go to journald and the configured
daemon log target.

Each stream can also override `log_level` (empty, `info`, `warning`, or
`error`) to get more or less detail than the system-wide `ffmpeg.log_level`
(see Configuration above) for just that stream — e.g. set it to `info`
temporarily on one problem stream to see ffmpeg's full per-stream banner
(stream mapping, codec details) while debugging, without making every other
stream's log noisy. Takes effect on the next start/restart, since it changes
the ffmpeg command line. Retention still applies on top of this, so detailed
logs roll off the same way once `log_retention_seconds` elapses.

Each stream can also set `keep_stats` (default `false`) to omit `-nostats`
from that stream's ffmpeg command, letting ffmpeg print its own periodic
console stats line to stderr alongside `-progress pipe:1`. That line is
rewritten in place with a bare `\r` and never gets a trailing newline; the
log-capture scanner (`internal/streams/jobs.go`) splits on a bare `\r` as
well as `\n` specifically so this never grows unbounded and never forces a
restart, and separately recognizes and discards the stats line itself
(`isFFmpegStatsLine`) so it isn't stored as a log entry — `-progress pipe:1`
already exposes the same numbers (frame/fps/bitrate/speed) structured, so
logging the console line too would just be a near-duplicate entry every
`stats_period`. `keep_stats` is safe to leave on; it only matters if
something external specifically needs ffmpeg's native stats formatting.

Common errors are classified into stable codes for UI filtering and highlighting:

```text
process_exit
input_error
output_error
bind_error
network_error
codec_error
permission_error
watchdog
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

SRT relays:

```text
GET    /api/srt/relays
POST   /api/srt/relays
GET    /api/srt/relays/{id}
PUT    /api/srt/relays/{id}
DELETE /api/srt/relays/{id}
POST   /api/srt/relays/{id}/start
POST   /api/srt/relays/{id}/stop
POST   /api/srt/relays/{id}/restart
```

Publish/Caller configuration example:

```json
{
  "id": "news-hd-partner",
  "name": "News HD to partner",
  "direction": "publish",
  "input_url": "udp://239.10.10.1:1234",
  "network_interface": "eno1",
  "destination_address": "203.0.113.50",
  "destination_port": 9000,
  "stream_id": "news-hd",
  "encryption_mode": "aes-256",
  "latency_ms": 800,
  "payload_size": 1316,
  "input_timeout_seconds": 10,
  "enabled": true
}
```

The create response contains the generated publish `passphrase` once when
AES-256 is enabled. The partner configures the same value on its Listener.
`none` produces no key. The destination must be a literal IP so DNS cannot
silently redirect a production feed.

Accept/Listener configuration example:

```json
{
  "id": "news-hd-srt",
  "name": "News HD internet delivery",
  "input_url": "udp://239.10.10.1:1234?localaddr=10.0.0.5",
  "network_interface": "eno1",
  "bind_address": "0.0.0.0",
  "port": 9000,
  "latency_ms": 800,
  "payload_size": 1316,
  "max_clients": 16,
  "input_timeout_seconds": 10,
  "allow_missing_stream_id": true,
  "default_client_id": "partner-a",
  "enabled": true
}
```

Use either `network_interface` or the input URL `localaddr` query to select the
multicast interface. The input address must be multicast. Payload size must be
a multiple of the 188-byte MPEG-TS packet size and cannot exceed 1456 bytes;
1316 is seven TS packets and is the default.
The input timeout accepts 3–300 seconds and defaults to 10. It controls health
state and auditing only; temporary source loss does not restart the worker.
Compatibility mode is listener-only and requires an existing enabled client
assigned to this relay. Create the relay in strict mode, create and assign the
access client, then edit the relay to select it as the compatibility default.

SRT access clients:

```text
GET    /api/srt/clients
POST   /api/srt/clients
PUT    /api/srt/clients/{id}
DELETE /api/srt/clients/{id}
POST   /api/srt/clients/{id}/rotate-key
```

Create-client example:

```json
{
  "id": "partner-a",
  "name": "Distribution partner A",
  "enabled": true,
  "encryption_mode": "aes-256",
  "allowed_relay_ids": ["news-hd-srt"],
  "allowed_cidrs": ["203.0.113.8", "198.51.100.0/24"],
  "max_sessions": 1
}
```

`encryption_mode` accepts `aes-256` (default) or `none`. AES create, rotate-key,
and `none` to `aes-256` responses contain `passphrase` exactly once. Client list
responses never disclose it. Key rotation is rejected for `none`. A plain IP is
normalized to `/32` or `/128`; an unencrypted client cannot use an IPv4 or IPv6
`/0`. Changes to an access client restart its affected running relays so the new
ACL, key, or encryption mode cannot remain unapplied in an old worker.

Sessions and audit:

```text
GET /api/srt/sessions
GET /api/srt/sessions?active=true
GET /api/srt/audit?relay_id=news-hd-srt&client_id=partner-a&type=connection_rejected
```

All SRT endpoints use the same bearer authentication as the rest of the API.
SRT runtime updates are also sent through `/api/events`; the UI patches
per-second relay/session metrics from SSE without polling.

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
  -nostats
  -loglevel level+warning
  -progress pipe:1
  -stats_period 1
  -analyzeduration 10000000
  -probesize 20000000
  -i udp://239.1.1.1:1234?buffer_size=8388608&fifo_size=100000000&localaddr=10.0.0.5&overrun_nonfatal=1&reuse=1
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

This is intentionally close to the pre-tuning command: only UDP transport and
probing changed. `-analyzeduration`/`-probesize` and the
`overrun_nonfatal`/`fifo_size`/`buffer_size`/`reuse`/`pkt_size` query
parameters come from `ffmpeg.udp`/`ffmpeg.probe` system config (see
Configuration above) and are added automatically regardless of which profile
a stream uses — none of it touches the encoder.

`-fflags`, `-err_detect`, `-g`/`-keyint_min`/`-sc_threshold`, `-threads`,
`-minrate`, and `-x264-params` are **never** added unless a profile
explicitly opts in via its `advanced` section:

```json
{
  "advanced": {
    "enable_genpts": false,
    "discard_corrupt": false,
    "ignore_decode_errors": false,
    "video_threads": null,
    "gop": null,
    "keyint_min": null,
    "sc_threshold": null,
    "minrate": null,
    "x264_params": null
  }
}
```

`enable_genpts`/`discard_corrupt` combine into a single `-fflags`
(`+genpts`, `+discardcorrupt`, or `+genpts+discardcorrupt`);
`ignore_decode_errors` adds `-err_detect ignore_err`. These all change how
tolerant ffmpeg is of corrupt input, which can shift timing and effective
bitrate — that's why they were pulled out of the system default after
operators saw exactly that on live streams, and are opt-in per profile now.

`-loglevel level+<log_level>` controls how much ffmpeg writes to the stream
log, independent of the `level` tag itself (which is always kept, so log
entries can be classified by ffmpeg's real severity). The default,
`log_level: "warning"`, stops ffmpeg from emitting routine per-stream info
banners (stream mapping, codec details) at all — most of the volume in a
noisy log — while still surfacing real warnings/errors, including known
multicast-loss symptoms like `non-existing PPS/SPS referenced` or
`decode_slice_header error` (these are recognized and stored as a `warning`
with code `packet_loss`, not escalated to an error or used to trigger a
restart, since they typically mean lost/corrupt UDP packets or joining a
multicast feed mid-GOP — not a bug in NeoTranscoder or a broken encode). Set
`log_level` back to `"info"` to get the full per-stream banner detail for
troubleshooting.

`localaddr=<interface-ip>` in the input URL is how a stream picks which
network interface joins the multicast group on a multi-homed host — set it
per stream when configuring the input URL.

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

CI runs unit, integration, negative-path, race, Flutter state, and native SRT
media-path tests on every pull request. Important local checks are:

```sh
go test ./...
go test -race ./internal/auth ./internal/server ./internal/srtrelay ./internal/srtworker ./internal/streams
go vet ./...
cd ui && flutter analyze && flutter test
```

Build the Flutter Web UI and embed it into the Go binary static assets:

```sh
./scripts/build-ui.sh
```

Build a local release bundle:

```sh
VERSION=0.1.0 ./scripts/build-release.sh
```

The bundle contains both installation helpers, the public project manual, and
`config.example.json`. A supplied SRT worker is included with its own checksum.

Build the portable static Linux amd64 SRT worker. Docker/buildx is used only as
a reproducible compiler environment and is not a runtime dependency:

```sh
VERSION=0.1.0 ./scripts/build-srt-worker-linux.sh
```

Then include it in the release bundle while building the main Linux binary:

```sh
VERSION=0.1.0 \
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 \
SRT_WORKER=dist/srt-worker-linux-amd64/neotranscoder-srt-worker \
./scripts/build-release.sh
```

On a Linux builder with libsrt development files, `BUILD_SRT=1` can build the
worker directly. The static Docker path is preferred for a portable public
release because it does not depend on the target host's libsrt/OpenSSL ABI.

Release builds embed version metadata with Go linker flags. A production build
should set at least `VERSION`; `COMMIT` and `DATE` default to the current git
commit and current UTC time:

```sh
VERSION=0.1.0 COMMIT="$(git rev-parse --short HEAD)" ./scripts/build-release.sh
```

Check a built binary:

```sh
dist/neotranscoder/neotranscoder version
```

Run the native media-path test on Linux. It generates a local MPEG-TS
multicast, verifies that a wrong SRT passphrase is rejected, receives the same
stream through both encrypted and IP-ACL-only SRT, validates video/audio tracks,
checks the reported encryption state, and reports worker RSS/file-descriptor
growth:

```sh
cd dist/neotranscoder
./test-srt-native.sh
./test-srt-caller-native.sh
```

The second command starts FFmpeg as the partner Listener and verifies the
NeoTranscoder Publish/Caller path with AES-256 end to end.

Use repeated connections as a bounded soak test:

```sh
ROUNDS=100 RECEIVE_SECONDS=2 \
MAX_RSS_GROWTH_KB=65536 MAX_FD_GROWTH=16 \
./test-srt-native.sh
```

The script requires Linux, an FFmpeg build with SRT support, ffprobe, and the
bundled static `neotranscoder-srt-worker`. It uses loopback multicast and high
ports, does not install files, and cleans up all child processes on exit.

If `sha256sum` or `shasum` is available on the build machine, the release bundle
also includes `neotranscoder.sha256` for verified URL or file updates.

The generated bundle is written to:

```text
dist/neotranscoder/
```

## Security Notes

NeoTranscoder starts external FFmpeg processes. Treat stream URLs and profile
settings as trusted operator input. The built-in user system protects the
management API with backend-issued bearer access tokens and refresh tokens.

SRT passphrases are sent to workers through stdin, never process arguments, and
are never logged. Unencrypted clients are an explicit compatibility mode and
must use restricted IP/CIDR ACLs. The master key and daily audit files use mode `0600`. The
Linux manager sets a parent-death signal so an SRT worker cannot survive an
abrupt daemon exit. The systemd unit runs under the dedicated unprivileged user,
uses `NoNewPrivileges`, a read-only system filesystem, private temporary files,
restricted address families, and explicit writable state/log paths.

SRT encrypts media transport but does not protect the management HTTP port.
Place the web/API endpoint behind TLS and a trusted reverse proxy or management
VPN when it is accessed outside a protected operations network. Expose only the
specific UDP relay ports required by receivers and combine NeoTranscoder's
per-client ACL with host/edge firewall policy.

FFmpeg commands are built as an argument array, not as a shell string. This
avoids shell interpolation and quoting bugs.

Do not expose the management HTTP port to untrusted networks without TLS and
network-level access controls or a trusted reverse proxy.
