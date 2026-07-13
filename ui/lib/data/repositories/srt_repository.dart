import 'package:neotranscoder_ui/core/api/models.dart';
import 'package:neotranscoder_ui/core/api/srt_models.dart';

abstract interface class SrtRepository {
  Future<List<SrtRelayView>> srtRelays();

  Future<SrtRelayView> saveSrtRelay(Map<String, Object?> body, {String? id});

  Future<void> deleteSrtRelay(String id);

  Future<void> startSrtRelay(String id);

  Future<void> stopSrtRelay(String id);

  Future<void> restartSrtRelay(String id);

  Future<List<SrtClient>> srtClients();

  Future<SrtClientCredential> saveSrtClient(
    Map<String, Object?> body, {
    String? id,
  });

  Future<SrtClientCredential> rotateSrtClientKey(String id);

  Future<void> deleteSrtClient(String id);

  Future<List<SrtSession>> srtSessions({bool activeOnly = false});

  Future<List<SrtAuditEvent>> srtAudit({
    String relayId = '',
    String clientId = '',
    String type = '',
  });

  Stream<ApiEvent> events();
}
