import 'package:flutter_test/flutter_test.dart';
import 'package:neotranscoder_ui/core/api/models.dart';

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
}
