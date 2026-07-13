import 'package:neotranscoder_ui/core/api/srt_models.dart';

class StreamView {
  const StreamView({
    required this.config,
    required this.state,
  });

  factory StreamView.fromJson(Map<String, dynamic> json) {
    return StreamView(
      config:
          StreamConfig.fromJson(json['config'] as Map<String, dynamic>? ?? {}),
      state: StreamState.fromJson(json['state'] as Map<String, dynamic>? ?? {}),
    );
  }

  final StreamConfig config;
  final StreamState state;
}

class StreamConfig {
  const StreamConfig({
    required this.id,
    required this.name,
    required this.inputUrl,
    required this.outputUrl,
    required this.sourceType,
    required this.profileName,
    required this.enabled,
    required this.audioMaps,
    required this.disableAudio,
    required this.logo,
    required this.options,
    required this.logRetentionSeconds,
    required this.logLevel,
    required this.keepStats,
    required this.watchdog,
  });

  factory StreamConfig.fromJson(Map<String, dynamic> json) {
    return StreamConfig(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      inputUrl: json['input_url'] as String? ?? '',
      outputUrl: json['output_url'] as String? ?? '',
      sourceType: json['source_type'] as String? ?? 'multicast',
      profileName: json['profile_name'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? false,
      audioMaps:
          (json['audio_maps'] as List<dynamic>? ?? <dynamic>[]).cast<String>(),
      disableAudio: json['disable_audio'] as bool? ?? false,
      logo: LogoOverlay.fromJson(
          json['logo'] as Map<String, dynamic>? ?? <String, dynamic>{}),
      options:
          (json['options'] as Map<String, dynamic>? ?? <String, dynamic>{}).map(
        (String key, dynamic value) =>
            MapEntry<String, String>(key, value as String? ?? ''),
      ),
      logRetentionSeconds: json['log_retention_seconds'] as int? ?? 60,
      logLevel: json['log_level'] as String? ?? '',
      keepStats: json['keep_stats'] as bool? ?? false,
      watchdog: WatchdogPolicy.fromJson(
          json['watchdog'] as Map<String, dynamic>? ?? <String, dynamic>{}),
    );
  }

  final String id;
  final String name;
  final String inputUrl;
  final String outputUrl;
  final String sourceType;
  final String profileName;
  final bool enabled;
  final List<String> audioMaps;
  final bool disableAudio;
  final LogoOverlay logo;
  final Map<String, String> options;
  final int logRetentionSeconds;
  final String logLevel;
  final bool keepStats;
  final WatchdogPolicy watchdog;
}

class WatchdogPolicy {
  const WatchdogPolicy({
    required this.enabled,
    required this.progressTimeoutSeconds,
    required this.maxMemoryBytes,
    required this.memoryGraceSeconds,
  });

  factory WatchdogPolicy.fromJson(Map<String, dynamic> json) {
    return WatchdogPolicy(
      enabled: json['enabled'] as bool? ?? true,
      progressTimeoutSeconds: json['progress_timeout_seconds'] as int? ?? 120,
      maxMemoryBytes: (json['max_memory_bytes'] as num?)?.toInt() ?? 0,
      memoryGraceSeconds: json['memory_grace_seconds'] as int? ?? 30,
    );
  }

  final bool enabled;
  final int progressTimeoutSeconds;
  final int maxMemoryBytes;
  final int memoryGraceSeconds;
}

class LogoOverlay {
  const LogoOverlay({
    required this.enabled,
    required this.path,
    required this.x,
    required this.y,
  });

  factory LogoOverlay.fromJson(Map<String, dynamic> json) {
    return LogoOverlay(
      enabled: json['enabled'] as bool? ?? false,
      path: json['path'] as String? ?? '',
      x: json['x'] as int? ?? 0,
      y: json['y'] as int? ?? 0,
    );
  }

  final bool enabled;
  final String path;
  final int x;
  final int y;
}

class StreamState {
  const StreamState({
    required this.status,
    required this.pid,
    required this.errorCode,
    required this.lastError,
    required this.restartCount,
    required this.flapping,
    this.metrics,
    this.process,
  });

  factory StreamState.fromJson(Map<String, dynamic> json) {
    return StreamState(
      status: json['status'] as String? ?? 'stopped',
      pid: json['pid'] as int? ?? 0,
      errorCode: json['error_code'] as String? ?? '',
      lastError: json['last_error'] as String? ?? '',
      restartCount: json['restart_count'] as int? ?? 0,
      flapping: json['flapping'] as bool? ?? false,
      metrics: json['metrics'] is Map<String, dynamic>
          ? MediaMetrics.fromJson(json['metrics'] as Map<String, dynamic>)
          : null,
      process: json['process'] is Map<String, dynamic>
          ? ProcessMetrics.fromJson(json['process'] as Map<String, dynamic>)
          : null,
    );
  }

  final String status;
  final int pid;
  final String errorCode;
  final String lastError;
  final int restartCount;
  final bool flapping;
  final MediaMetrics? metrics;
  final ProcessMetrics? process;

  bool get isRunning => status == 'running';
  bool get hasError =>
      status == 'error' || status == 'flapping' || errorCode.isNotEmpty;
}

class MediaMetrics {
  const MediaMetrics({
    required this.frame,
    required this.fps,
    required this.bitrate,
    required this.speed,
    required this.outTime,
  });

  factory MediaMetrics.fromJson(Map<String, dynamic> json) {
    return MediaMetrics(
      frame: json['frame'] as int? ?? 0,
      fps: (json['fps'] as num?)?.toDouble() ?? 0,
      bitrate: json['bitrate'] as String? ?? '',
      speed: json['speed'] as String? ?? '',
      outTime: json['out_time'] as String? ?? '',
    );
  }

  final int frame;
  final double fps;
  final String bitrate;
  final String speed;
  final String outTime;
}

class ProcessMetrics {
  const ProcessMetrics({
    required this.cpuPercent,
    required this.memoryBytes,
  });

  factory ProcessMetrics.fromJson(Map<String, dynamic> json) {
    return ProcessMetrics(
      cpuPercent: (json['cpu_percent'] as num?)?.toDouble() ?? 0,
      memoryBytes: json['memory_bytes'] as int? ?? 0,
    );
  }

  final double cpuPercent;
  final int memoryBytes;
}

class Profile {
  const Profile({
    required this.name,
    required this.videoCodec,
    required this.videoPreset,
    required this.videoTune,
    required this.videoBitrate,
    required this.videoMaxrate,
    required this.videoBufsize,
    required this.audioCodec,
    required this.audioBitrate,
    required this.outputFormat,
    required this.templateArgs,
    required this.templateDefaults,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    final video = json['video'] as Map<String, dynamic>? ?? {};
    final audio = json['audio'] as Map<String, dynamic>? ?? {};
    final output = json['output'] as Map<String, dynamic>? ?? {};
    final template = json['template'] as Map<String, dynamic>? ?? {};
    return Profile(
      name: json['name'] as String? ?? '',
      videoCodec: video['codec'] as String? ?? '',
      videoPreset: video['preset'] as String? ?? '',
      videoTune: video['tune'] as String? ?? '',
      videoBitrate: video['bitrate'] as String? ?? '',
      videoMaxrate: video['maxrate'] as String? ?? '',
      videoBufsize: video['bufsize'] as String? ?? '',
      audioCodec: audio['codec'] as String? ?? '',
      audioBitrate: audio['bitrate'] as String? ?? '',
      outputFormat: output['format'] as String? ?? '',
      templateArgs:
          (template['args'] as List<dynamic>? ?? <dynamic>[]).cast<String>(),
      templateDefaults:
          (template['defaults'] as Map<String, dynamic>? ?? <String, dynamic>{})
              .map(
        (String key, dynamic value) =>
            MapEntry<String, String>(key, value as String? ?? ''),
      ),
    );
  }

  final String name;
  final String videoCodec;
  final String videoPreset;
  final String videoTune;
  final String videoBitrate;
  final String videoMaxrate;
  final String videoBufsize;
  final String audioCodec;
  final String audioBitrate;
  final String outputFormat;
  final List<String> templateArgs;
  final Map<String, String> templateDefaults;
}

class LogEntry {
  const LogEntry({
    required this.streamId,
    required this.level,
    required this.code,
    required this.message,
    required this.time,
  });

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      streamId: json['stream_id'] as String? ?? '',
      level: json['level'] as String? ?? '',
      code: json['code'] as String? ?? '',
      message: json['message'] as String? ?? '',
      time: json['time'] as String? ?? '',
    );
  }

  final String streamId;
  final String level;
  final String code;
  final String message;
  final String time;
}

class CommandPreview {
  const CommandPreview({
    required this.path,
    required this.args,
  });

  factory CommandPreview.fromJson(Map<String, dynamic> json) {
    return CommandPreview(
      path: json['path'] as String? ?? '',
      args: (json['args'] as List<dynamic>? ?? []).cast<String>(),
    );
  }

  final String path;
  final List<String> args;
}

class UserAccount {
  const UserAccount({
    required this.username,
    required this.mustChangePassword,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserAccount.fromJson(Map<String, dynamic> json) {
    return UserAccount(
      username: json['username'] as String? ?? '',
      mustChangePassword: json['must_change_password'] as bool? ?? false,
      createdAt: json['created_at'] as String? ?? '',
      updatedAt: json['updated_at'] as String? ?? '',
    );
  }

  final String username;
  final bool mustChangePassword;
  final String createdAt;
  final String updatedAt;
}

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.mustChangePassword,
    required this.user,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      accessToken: json['access_token'] as String? ?? '',
      refreshToken: json['refresh_token'] as String? ?? '',
      mustChangePassword: json['must_change_password'] as bool? ?? false,
      user: UserAccount.fromJson(
          json['user'] as Map<String, dynamic>? ?? <String, dynamic>{}),
    );
  }

  final String accessToken;
  final String refreshToken;
  final bool mustChangePassword;
  final UserAccount user;
}

class ServerStats {
  const ServerStats({
    this.cpuPercent = 0,
    this.loadAvg1 = 0,
    this.loadAvg5 = 0,
    this.loadAvg15 = 0,
    this.memoryUsedBytes = 0,
    this.memoryTotalBytes = 0,
    this.diskUsedBytes = 0,
    this.diskTotalBytes = 0,
    this.systemUptimeSeconds = 0,
    this.appUptimeSeconds = 0,
    this.cpuCores = 0,
    this.supported = false,
  });

  factory ServerStats.fromJson(Map<String, dynamic> json) {
    return ServerStats(
      cpuPercent: (json['cpu_percent'] as num?)?.toDouble() ?? 0,
      loadAvg1: (json['load_avg_1'] as num?)?.toDouble() ?? 0,
      loadAvg5: (json['load_avg_5'] as num?)?.toDouble() ?? 0,
      loadAvg15: (json['load_avg_15'] as num?)?.toDouble() ?? 0,
      memoryUsedBytes: (json['memory_used_bytes'] as num?)?.toInt() ?? 0,
      memoryTotalBytes: (json['memory_total_bytes'] as num?)?.toInt() ?? 0,
      diskUsedBytes: (json['disk_used_bytes'] as num?)?.toInt() ?? 0,
      diskTotalBytes: (json['disk_total_bytes'] as num?)?.toInt() ?? 0,
      systemUptimeSeconds:
          (json['system_uptime_seconds'] as num?)?.toInt() ?? 0,
      appUptimeSeconds: (json['app_uptime_seconds'] as num?)?.toInt() ?? 0,
      cpuCores: json['cpu_cores'] as int? ?? 0,
      supported: json['supported'] as bool? ?? false,
    );
  }

  final double cpuPercent;
  final double loadAvg1;
  final double loadAvg5;
  final double loadAvg15;
  final int memoryUsedBytes;
  final int memoryTotalBytes;
  final int diskUsedBytes;
  final int diskTotalBytes;
  final int systemUptimeSeconds;
  final int appUptimeSeconds;
  final int cpuCores;
  final bool supported;
}

class ServerInfo {
  const ServerInfo({
    required this.version,
    required this.commit,
    required this.date,
  });

  factory ServerInfo.fromJson(Map<String, dynamic> json) {
    return ServerInfo(
      version: json['version'] as String? ?? '',
      commit: json['commit'] as String? ?? '',
      date: json['date'] as String? ?? '',
    );
  }

  final String version;
  final String commit;
  final String date;
}

class ApiEvent {
  const ApiEvent({
    required this.type,
    this.streamId = '',
    this.relayId = '',
    this.streamState,
    this.srtRelayState,
    this.srtSession,
    this.srtAuditEvent,
  });

  factory ApiEvent.fromJson(Map<String, dynamic> json) {
    final Object? payload = json['payload'];
    return ApiEvent(
      type: json['type'] as String? ?? '',
      streamId: json['stream_id'] as String? ?? '',
      relayId: json['relay_id'] as String? ?? '',
      streamState:
          payload is Map<String, dynamic> && json['type'] == 'stream_state'
              ? StreamState.fromJson(payload)
              : null,
      srtRelayState: payload is Map<String, dynamic> &&
              const <String>{
                'srt_relay_state',
                'srt_relay_ready',
                'srt_relay_metrics',
                'srt_relay_error',
              }.contains(json['type'])
          ? SrtRelayState.fromJson(payload)
          : null,
      srtSession: payload is Map<String, dynamic> &&
              const <String>{
                'srt_session_connected',
                'srt_session_stats',
                'srt_session_disconnected',
              }.contains(json['type']) &&
              payload['session'] is Map<String, dynamic>
          ? SrtSession.fromJson(payload['session'] as Map<String, dynamic>)
          : null,
      srtAuditEvent:
          payload is Map<String, dynamic> && json['type'] == 'srt_audit'
              ? SrtAuditEvent.fromJson(payload)
              : null,
    );
  }

  final String type;
  final String streamId;
  final String relayId;
  final StreamState? streamState;
  final SrtRelayState? srtRelayState;
  final SrtSession? srtSession;
  final SrtAuditEvent? srtAuditEvent;
}

class ProbeResult {
  const ProbeResult({
    required this.formatName,
    required this.bitRate,
    required this.streams,
  });

  factory ProbeResult.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> format =
        json['format'] as Map<String, dynamic>? ?? <String, dynamic>{};
    return ProbeResult(
      formatName: format['format_name'] as String? ?? '',
      bitRate: format['bit_rate'] as String? ?? '',
      streams: (json['streams'] as List<dynamic>? ?? <dynamic>[])
          .map((dynamic item) =>
              ProbeStream.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  final String formatName;
  final String bitRate;
  final List<ProbeStream> streams;
}

class ProbeStream {
  const ProbeStream({
    required this.index,
    required this.codecType,
    required this.codecName,
    required this.width,
    required this.height,
    required this.bitRate,
    required this.avgFrameRate,
    required this.channels,
    required this.channelLayout,
    required this.tags,
  });

  factory ProbeStream.fromJson(Map<String, dynamic> json) {
    return ProbeStream(
      index: json['index'] as int? ?? 0,
      codecType: json['codec_type'] as String? ?? '',
      codecName: json['codec_name'] as String? ?? '',
      width: json['width'] as int? ?? 0,
      height: json['height'] as int? ?? 0,
      bitRate: json['bit_rate'] as String? ?? '',
      avgFrameRate: json['avg_frame_rate'] as String? ?? '',
      channels: json['channels'] as int? ?? 0,
      channelLayout: json['channel_layout'] as String? ?? '',
      tags: (json['tags'] as Map<String, dynamic>? ?? <String, dynamic>{}).map(
        (String key, dynamic value) =>
            MapEntry<String, String>(key, value?.toString() ?? ''),
      ),
    );
  }

  final int index;
  final String codecType;
  final String codecName;
  final int width;
  final int height;
  final String bitRate;
  final String avgFrameRate;
  final int channels;
  final String channelLayout;
  final Map<String, String> tags;
}
