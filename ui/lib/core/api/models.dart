import 'package:neotranscoder_ui/core/api/srt_models.dart';

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
    this.relayId = '',
    this.srtRelayState,
    this.srtSession,
    this.srtAuditEvent,
  });

  factory ApiEvent.fromJson(Map<String, dynamic> json) {
    final Object? payload = json['payload'];
    return ApiEvent(
      type: json['type'] as String? ?? '',
      relayId: json['relay_id'] as String? ?? '',
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
  final String relayId;
  final SrtRelayState? srtRelayState;
  final SrtSession? srtSession;
  final SrtAuditEvent? srtAuditEvent;
}
