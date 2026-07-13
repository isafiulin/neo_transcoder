import 'package:neotranscoder_ui/core/api/models.dart';
import 'package:neotranscoder_ui/core/api/srt_models.dart';

abstract interface class DashboardRepository {
  Future<List<StreamView>> metrics();

  Future<ServerStats> system();

  Future<List<SrtRelayView>> srtRelays();

  Future<List<SrtSession>> srtSessions({bool activeOnly = false});

  Stream<ApiEvent> events();

  Future<void> startStream(String id);

  Future<void> stopStream(String id);

  Future<void> restartStream(String id);

  Future<void> startSrtRelay(String id);

  Future<void> stopSrtRelay(String id);

  Future<void> restartSrtRelay(String id);
}
