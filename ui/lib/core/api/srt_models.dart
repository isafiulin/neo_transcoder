class SrtRelayView {
  const SrtRelayView({
    required this.config,
    required this.state,
    this.passphrase = '',
  });

  factory SrtRelayView.fromJson(Map<String, dynamic> json) {
    return SrtRelayView(
      config: SrtRelay.fromJson(
        json['config'] as Map<String, dynamic>? ?? <String, dynamic>{},
      ),
      state: SrtRelayState.fromJson(
        json['state'] as Map<String, dynamic>? ?? <String, dynamic>{},
      ),
      passphrase: json['passphrase'] as String? ?? '',
    );
  }

  final SrtRelay config;
  final SrtRelayState state;
  final String passphrase;
}

class SrtRelay {
  const SrtRelay({
    required this.id,
    required this.name,
    required this.direction,
    required this.inputUrl,
    required this.networkInterface,
    required this.bindAddress,
    required this.port,
    required this.destinationAddress,
    required this.destinationPort,
    required this.streamId,
    required this.encryptionMode,
    required this.keyVersion,
    required this.latencyMs,
    required this.payloadSize,
    required this.maxClients,
    required this.inputTimeoutSeconds,
    required this.enabled,
    this.allowMissingStreamId = false,
    this.defaultClientId = '',
  });

  factory SrtRelay.fromJson(Map<String, dynamic> json) {
    return SrtRelay(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      direction: json['direction'] as String? ?? 'listener',
      inputUrl: json['input_url'] as String? ?? '',
      networkInterface: json['network_interface'] as String? ?? '',
      bindAddress: json['bind_address'] as String? ?? '0.0.0.0',
      port: (json['port'] as num?)?.toInt() ?? 0,
      destinationAddress: json['destination_address'] as String? ?? '',
      destinationPort: (json['destination_port'] as num?)?.toInt() ?? 0,
      streamId: json['stream_id'] as String? ?? '',
      encryptionMode: json['encryption_mode'] as String? ?? 'aes-256',
      keyVersion: (json['key_version'] as num?)?.toInt() ?? 1,
      latencyMs: (json['latency_ms'] as num?)?.toInt() ?? 800,
      payloadSize: (json['payload_size'] as num?)?.toInt() ?? 1316,
      maxClients: (json['max_clients'] as num?)?.toInt() ?? 16,
      inputTimeoutSeconds:
          (json['input_timeout_seconds'] as num?)?.toInt() ?? 10,
      allowMissingStreamId: json['allow_missing_stream_id'] as bool? ?? false,
      defaultClientId: json['default_client_id'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? false,
    );
  }

  final String id;
  final String name;
  final String direction;
  final String inputUrl;
  final String networkInterface;
  final String bindAddress;
  final int port;
  final String destinationAddress;
  final int destinationPort;
  final String streamId;
  final String encryptionMode;
  final int keyVersion;
  final int latencyMs;
  final int payloadSize;
  final int maxClients;
  final int inputTimeoutSeconds;
  final bool enabled;
  final bool allowMissingStreamId;
  final String defaultClientId;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'direction': direction,
      'input_url': inputUrl,
      'network_interface': networkInterface,
      'bind_address': bindAddress,
      'port': port,
      'destination_address': destinationAddress,
      'destination_port': destinationPort,
      'stream_id': streamId,
      'encryption_mode': encryptionMode,
      'key_version': keyVersion,
      'latency_ms': latencyMs,
      'payload_size': payloadSize,
      'max_clients': maxClients,
      'input_timeout_seconds': inputTimeoutSeconds,
      'allow_missing_stream_id': allowMissingStreamId,
      'default_client_id': defaultClientId,
      'enabled': enabled,
    };
  }
}

class SrtRelayState {
  const SrtRelayState({
    required this.status,
    required this.pid,
    required this.activeClients,
    required this.inputBitrateBps,
    required this.outputBitrateBps,
    required this.inputPackets,
    required this.continuityErrors,
    required this.restartCount,
    required this.flapping,
    required this.lastError,
    required this.updatedAt,
  });

  factory SrtRelayState.fromJson(Map<String, dynamic> json) {
    return SrtRelayState(
      status: json['status'] as String? ?? 'stopped',
      pid: (json['pid'] as num?)?.toInt() ?? 0,
      activeClients: (json['active_clients'] as num?)?.toInt() ?? 0,
      inputBitrateBps: (json['input_bitrate_bps'] as num?)?.toInt() ?? 0,
      outputBitrateBps: (json['output_bitrate_bps'] as num?)?.toInt() ?? 0,
      inputPackets: (json['input_packets'] as num?)?.toInt() ?? 0,
      continuityErrors: (json['continuity_errors'] as num?)?.toInt() ?? 0,
      restartCount: (json['restart_count'] as num?)?.toInt() ?? 0,
      flapping: json['flapping'] as bool? ?? false,
      lastError: json['last_error'] as String? ?? '',
      updatedAt: json['updated_at'] as String? ?? '',
    );
  }

  final String status;
  final int pid;
  final int activeClients;
  final int inputBitrateBps;
  final int outputBitrateBps;
  final int inputPackets;
  final int continuityErrors;
  final int restartCount;
  final bool flapping;
  final String lastError;
  final String updatedAt;

  bool get isRunning =>
      status == 'running' || status == 'starting' || status == 'degraded';
  bool get hasError =>
      status == 'error' || status == 'flapping' || status == 'degraded';
}

class SrtClient {
  const SrtClient({
    required this.id,
    required this.name,
    required this.enabled,
    required this.encryptionMode,
    required this.allowedRelayIds,
    required this.allowedCidrs,
    required this.maxSessions,
    required this.keyVersion,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SrtClient.fromJson(Map<String, dynamic> json) {
    return SrtClient(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? false,
      encryptionMode: json['encryption_mode'] as String? ?? 'aes-256',
      allowedRelayIds:
          (json['allowed_relay_ids'] as List<dynamic>? ?? <dynamic>[])
              .cast<String>(),
      allowedCidrs: (json['allowed_cidrs'] as List<dynamic>? ?? <dynamic>[])
          .cast<String>(),
      maxSessions: (json['max_sessions'] as num?)?.toInt() ?? 1,
      keyVersion: (json['key_version'] as num?)?.toInt() ?? 1,
      createdAt: json['created_at'] as String? ?? '',
      updatedAt: json['updated_at'] as String? ?? '',
    );
  }

  final String id;
  final String name;
  final bool enabled;
  final String encryptionMode;
  final List<String> allowedRelayIds;
  final List<String> allowedCidrs;
  final int maxSessions;
  final int keyVersion;
  final String createdAt;
  final String updatedAt;
}

class SrtClientCredential {
  const SrtClientCredential({required this.client, required this.passphrase});

  factory SrtClientCredential.fromJson(Map<String, dynamic> json) {
    return SrtClientCredential(
      client: SrtClient.fromJson(
        json['client'] as Map<String, dynamic>? ?? <String, dynamic>{},
      ),
      passphrase: json['passphrase'] as String? ?? '',
    );
  }

  final SrtClient client;
  final String passphrase;
}

class SrtSession {
  const SrtSession({
    required this.id,
    required this.relayId,
    required this.clientId,
    required this.remoteIp,
    required this.remotePort,
    required this.streamId,
    required this.peerVersion,
    required this.encrypted,
    required this.connectedAt,
    required this.disconnectedAt,
    required this.disconnectReason,
    required this.stats,
  });

  factory SrtSession.fromJson(Map<String, dynamic> json) {
    return SrtSession(
      id: json['id'] as String? ?? '',
      relayId: json['relay_id'] as String? ?? '',
      clientId: json['client_id'] as String? ?? '',
      remoteIp: json['remote_ip'] as String? ?? '',
      remotePort: (json['remote_port'] as num?)?.toInt() ?? 0,
      streamId: json['stream_id'] as String? ?? '',
      peerVersion: json['peer_version'] as String? ?? '',
      encrypted: json['encrypted'] as bool? ?? false,
      connectedAt: json['connected_at'] as String? ?? '',
      disconnectedAt: json['disconnected_at'] as String? ?? '',
      disconnectReason: json['disconnect_reason'] as String? ?? '',
      stats: SrtSessionStats.fromJson(
        json['stats'] as Map<String, dynamic>? ?? <String, dynamic>{},
      ),
    );
  }

  final String id;
  final String relayId;
  final String clientId;
  final String remoteIp;
  final int remotePort;
  final String streamId;
  final String peerVersion;
  final bool encrypted;
  final String connectedAt;
  final String disconnectedAt;
  final String disconnectReason;
  final SrtSessionStats stats;

  bool get isActive => disconnectedAt.isEmpty;
}

class SrtSessionStats {
  const SrtSessionStats({
    required this.bytesSent,
    required this.packetsSent,
    required this.packetsLost,
    required this.packetsRetransmitted,
    required this.packetsDropped,
    required this.bitrateBps,
    required this.rttMs,
    required this.latencyMs,
  });

  factory SrtSessionStats.fromJson(Map<String, dynamic> json) {
    return SrtSessionStats(
      bytesSent: (json['bytes_sent'] as num?)?.toInt() ?? 0,
      packetsSent: (json['packets_sent'] as num?)?.toInt() ?? 0,
      packetsLost: (json['packets_lost'] as num?)?.toInt() ?? 0,
      packetsRetransmitted:
          (json['packets_retransmitted'] as num?)?.toInt() ?? 0,
      packetsDropped: (json['packets_dropped'] as num?)?.toInt() ?? 0,
      bitrateBps: (json['bitrate_bps'] as num?)?.toInt() ?? 0,
      rttMs: (json['rtt_ms'] as num?)?.toDouble() ?? 0,
      latencyMs: (json['latency_ms'] as num?)?.toInt() ?? 0,
    );
  }

  final int bytesSent;
  final int packetsSent;
  final int packetsLost;
  final int packetsRetransmitted;
  final int packetsDropped;
  final int bitrateBps;
  final double rttMs;
  final int latencyMs;
}

class SrtAuditEvent {
  const SrtAuditEvent({
    required this.id,
    required this.time,
    required this.type,
    required this.level,
    required this.relayId,
    required this.clientId,
    required this.sessionId,
    required this.remoteIp,
    required this.remotePort,
    required this.streamId,
    required this.reason,
    required this.actor,
  });

  factory SrtAuditEvent.fromJson(Map<String, dynamic> json) {
    return SrtAuditEvent(
      id: json['id'] as String? ?? '',
      time: json['time'] as String? ?? '',
      type: json['type'] as String? ?? '',
      level: json['level'] as String? ?? 'info',
      relayId: json['relay_id'] as String? ?? '',
      clientId: json['client_id'] as String? ?? '',
      sessionId: json['session_id'] as String? ?? '',
      remoteIp: json['remote_ip'] as String? ?? '',
      remotePort: (json['remote_port'] as num?)?.toInt() ?? 0,
      streamId: json['stream_id'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
      actor: json['actor'] as String? ?? '',
    );
  }

  final String id;
  final String time;
  final String type;
  final String level;
  final String relayId;
  final String clientId;
  final String sessionId;
  final String remoteIp;
  final int remotePort;
  final String streamId;
  final String reason;
  final String actor;
}
