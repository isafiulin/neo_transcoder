class StreamView {
  const StreamView({
    required this.config,
    required this.state,
  });

  final StreamConfig config;
  final StreamState state;

  factory StreamView.fromJson(Map<String, dynamic> json) {
    return StreamView(
      config: StreamConfig.fromJson(json['config'] as Map<String, dynamic>? ?? {}),
      state: StreamState.fromJson(json['state'] as Map<String, dynamic>? ?? {}),
    );
  }
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
  });

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

  factory StreamConfig.fromJson(Map<String, dynamic> json) {
    return StreamConfig(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      inputUrl: json['input_url'] as String? ?? '',
      outputUrl: json['output_url'] as String? ?? '',
      sourceType: json['source_type'] as String? ?? 'multicast',
      profileName: json['profile_name'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? false,
      audioMaps: (json['audio_maps'] as List<dynamic>? ?? <dynamic>[]).cast<String>(),
      disableAudio: json['disable_audio'] as bool? ?? false,
      logo: LogoOverlay.fromJson(json['logo'] as Map<String, dynamic>? ?? <String, dynamic>{}),
      options: (json['options'] as Map<String, dynamic>? ?? <String, dynamic>{}).map(
        (String key, dynamic value) => MapEntry<String, String>(key, value as String? ?? ''),
      ),
      logRetentionSeconds: json['log_retention_seconds'] as int? ?? 60,
    );
  }
}

class LogoOverlay {
  const LogoOverlay({
    required this.enabled,
    required this.path,
    required this.x,
    required this.y,
  });

  final bool enabled;
  final String path;
  final int x;
  final int y;

  factory LogoOverlay.fromJson(Map<String, dynamic> json) {
    return LogoOverlay(
      enabled: json['enabled'] as bool? ?? false,
      path: json['path'] as String? ?? '',
      x: json['x'] as int? ?? 0,
      y: json['y'] as int? ?? 0,
    );
  }
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

  final String status;
  final int pid;
  final String errorCode;
  final String lastError;
  final int restartCount;
  final bool flapping;
  final MediaMetrics? metrics;
  final ProcessMetrics? process;

  bool get isRunning => status == 'running';
  bool get hasError => status == 'error' || status == 'flapping' || errorCode.isNotEmpty;

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
}

class MediaMetrics {
  const MediaMetrics({
    required this.frame,
    required this.fps,
    required this.bitrate,
    required this.speed,
    required this.outTime,
  });

  final int frame;
  final double fps;
  final String bitrate;
  final String speed;
  final String outTime;

  factory MediaMetrics.fromJson(Map<String, dynamic> json) {
    return MediaMetrics(
      frame: json['frame'] as int? ?? 0,
      fps: (json['fps'] as num?)?.toDouble() ?? 0,
      bitrate: json['bitrate'] as String? ?? '',
      speed: json['speed'] as String? ?? '',
      outTime: json['out_time'] as String? ?? '',
    );
  }
}

class ProcessMetrics {
  const ProcessMetrics({
    required this.cpuPercent,
    required this.memoryBytes,
  });

  final double cpuPercent;
  final int memoryBytes;

  factory ProcessMetrics.fromJson(Map<String, dynamic> json) {
    return ProcessMetrics(
      cpuPercent: (json['cpu_percent'] as num?)?.toDouble() ?? 0,
      memoryBytes: json['memory_bytes'] as int? ?? 0,
    );
  }
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
      templateArgs: (template['args'] as List<dynamic>? ?? <dynamic>[]).cast<String>(),
      templateDefaults: (template['defaults'] as Map<String, dynamic>? ?? <String, dynamic>{}).map(
        (String key, dynamic value) => MapEntry<String, String>(key, value as String? ?? ''),
      ),
    );
  }
}

class LogEntry {
  const LogEntry({
    required this.streamId,
    required this.level,
    required this.code,
    required this.message,
    required this.time,
  });

  final String streamId;
  final String level;
  final String code;
  final String message;
  final String time;

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      streamId: json['stream_id'] as String? ?? '',
      level: json['level'] as String? ?? '',
      code: json['code'] as String? ?? '',
      message: json['message'] as String? ?? '',
      time: json['time'] as String? ?? '',
    );
  }
}

class CommandPreview {
  const CommandPreview({
    required this.path,
    required this.args,
  });

  final String path;
  final List<String> args;

  factory CommandPreview.fromJson(Map<String, dynamic> json) {
    return CommandPreview(
      path: json['path'] as String? ?? '',
      args: (json['args'] as List<dynamic>? ?? []).cast<String>(),
    );
  }
}

class UserAccount {
  const UserAccount({
    required this.username,
    required this.mustChangePassword,
    required this.createdAt,
    required this.updatedAt,
  });

  final String username;
  final bool mustChangePassword;
  final String createdAt;
  final String updatedAt;

  factory UserAccount.fromJson(Map<String, dynamic> json) {
    return UserAccount(
      username: json['username'] as String? ?? '',
      mustChangePassword: json['must_change_password'] as bool? ?? false,
      createdAt: json['created_at'] as String? ?? '',
      updatedAt: json['updated_at'] as String? ?? '',
    );
  }
}

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.mustChangePassword,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final bool mustChangePassword;
  final UserAccount user;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      accessToken: json['access_token'] as String? ?? '',
      refreshToken: json['refresh_token'] as String? ?? '',
      mustChangePassword: json['must_change_password'] as bool? ?? false,
      user: UserAccount.fromJson(json['user'] as Map<String, dynamic>? ?? <String, dynamic>{}),
    );
  }
}

class ApiEvent {
  const ApiEvent({
    required this.type,
    this.streamId = '',
  });

  final String type;
  final String streamId;

  factory ApiEvent.fromJson(Map<String, dynamic> json) {
    return ApiEvent(
      type: json['type'] as String? ?? '',
      streamId: json['stream_id'] as String? ?? '',
    );
  }
}

class ProbeResult {
  const ProbeResult({
    required this.formatName,
    required this.bitRate,
    required this.streams,
  });

  final String formatName;
  final String bitRate;
  final List<ProbeStream> streams;

  factory ProbeResult.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> format = json['format'] as Map<String, dynamic>? ?? <String, dynamic>{};
    return ProbeResult(
      formatName: format['format_name'] as String? ?? '',
      bitRate: format['bit_rate'] as String? ?? '',
      streams: (json['streams'] as List<dynamic>? ?? <dynamic>[])
          .map((dynamic item) => ProbeStream.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
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
  });

  final int index;
  final String codecType;
  final String codecName;
  final int width;
  final int height;
  final String bitRate;
  final String avgFrameRate;

  factory ProbeStream.fromJson(Map<String, dynamic> json) {
    return ProbeStream(
      index: json['index'] as int? ?? 0,
      codecType: json['codec_type'] as String? ?? '',
      codecName: json['codec_name'] as String? ?? '',
      width: json['width'] as int? ?? 0,
      height: json['height'] as int? ?? 0,
      bitRate: json['bit_rate'] as String? ?? '',
      avgFrameRate: json['avg_frame_rate'] as String? ?? '',
    );
  }
}
