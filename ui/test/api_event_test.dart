import 'package:flutter_test/flutter_test.dart';
import 'package:neotranscoder_ui/core/api/models.dart';
import 'package:neotranscoder_ui/core/api/srt_models.dart';

void main() {
  test('ApiEvent parses stream_state payload', () {
    final ApiEvent event = ApiEvent.fromJson(<String, dynamic>{
      'type': 'stream_state',
      'stream_id': 'channel_1',
      'payload': <String, dynamic>{
        'status': 'running',
        'pid': 1234,
        'metrics': <String, dynamic>{
          'fps': 25,
          'bitrate': '3900kbits/s',
        },
        'process': <String, dynamic>{
          'cpu_percent': 42.5,
          'memory_bytes': 1048576,
        },
      },
    });

    expect(event.streamId, 'channel_1');
    expect(event.streamState?.status, 'running');
    expect(event.streamState?.pid, 1234);
    expect(event.streamState?.metrics?.bitrate, '3900kbits/s');
    expect(event.streamState?.process?.cpuPercent, 42.5);
  });

  test('StreamConfig parses watchdog policy', () {
    final StreamConfig config = StreamConfig.fromJson(<String, dynamic>{
      'id': 'channel_1',
      'input_url': 'udp://239.1.1.1:1234',
      'output_url': 'udp://239.2.2.2:1234',
      'watchdog': <String, dynamic>{
        'enabled': true,
        'progress_timeout_seconds': 45,
        'max_memory_bytes': 2147483648,
        'memory_grace_seconds': 10,
      },
    });

    expect(config.watchdog.progressTimeoutSeconds, 45);
    expect(config.watchdog.maxMemoryBytes, 2147483648);
    expect(config.watchdog.memoryGraceSeconds, 10);
  });

  test('SRT relay model preserves watchdog and degraded state', () {
    final SrtRelay relay = SrtRelay.fromJson(<String, dynamic>{
      'id': 'news-srt',
      'input_url': 'udp://239.1.1.1:1234',
      'port': 9000,
      'input_timeout_seconds': 45,
      'enabled': true,
    });
    final SrtRelayState state = SrtRelayState.fromJson(<String, dynamic>{
      'status': 'degraded',
      'last_error': 'multicast input has no packets',
    });
    expect(relay.inputTimeoutSeconds, 45);
    expect(relay.toJson()['input_timeout_seconds'], 45);
    expect(state.isRunning, isTrue);
    expect(state.hasError, isTrue);
  });

  test('ApiEvent parses SRT state only for runtime event types', () {
    final Map<String, dynamic> payload = <String, dynamic>{
      'status': 'running',
      'input_bitrate_bps': 4000000,
    };
    final ApiEvent metrics = ApiEvent.fromJson(<String, dynamic>{
      'type': 'srt_relay_metrics',
      'relay_id': 'news-srt',
      'payload': payload,
    });
    final ApiEvent saved = ApiEvent.fromJson(<String, dynamic>{
      'type': 'srt_relay_saved',
      'relay_id': 'news-srt',
      'payload': payload,
    });
    expect(metrics.srtRelayState?.inputBitrateBps, 4000000);
    expect(saved.srtRelayState, isNull);
  });

  test('ApiEvent does not expose connection attempts as active sessions', () {
    final Map<String, dynamic> session = <String, dynamic>{
      'remote_ip': '176.123.227.54',
      'remote_port': 2153,
      'stream_id': '',
    };
    final ApiEvent attempt = ApiEvent.fromJson(<String, dynamic>{
      'type': 'srt_connection_attempt',
      'relay_id': 'news-srt',
      'payload': <String, dynamic>{'session': session},
    });
    final ApiEvent rejected = ApiEvent.fromJson(<String, dynamic>{
      'type': 'srt_connection_rejected',
      'relay_id': 'news-srt',
      'payload': <String, dynamic>{'session': session},
    });
    final ApiEvent connected = ApiEvent.fromJson(<String, dynamic>{
      'type': 'srt_session_connected',
      'relay_id': 'news-srt',
      'payload': <String, dynamic>{
        'session': <String, dynamic>{
          ...session,
          'id': 'srt_1',
          'relay_id': 'news-srt',
          'client_id': 'partner-a',
          'stream_id': 'partner-a',
          'encrypted': true,
          'connected_at': '2026-07-14T01:00:00Z',
        },
      },
    });

    expect(attempt.srtSession, isNull);
    expect(rejected.srtSession, isNull);
    expect(connected.srtSession?.id, 'srt_1');
    expect(connected.srtSession?.encrypted, isTrue);
  });
}
