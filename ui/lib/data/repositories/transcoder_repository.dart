import 'package:neotranscoder_ui/core/api/api_client.dart';
import 'package:neotranscoder_ui/core/api/models.dart';
import 'package:neotranscoder_ui/core/api/srt_models.dart';
import 'package:neotranscoder_ui/data/repositories/dashboard_repository.dart';
import 'package:neotranscoder_ui/data/repositories/srt_repository.dart';

class TranscoderRepository implements DashboardRepository, SrtRepository {
  TranscoderRepository({required ApiClient api}) : _api = api;

  final ApiClient _api;

  ApiClient get api {
    return _api;
  }

  Future<ServerInfo> health() {
    return _api.health();
  }

  Future<List<StreamView>> streams() {
    return _api.streams();
  }

  @override
  Future<List<StreamView>> metrics() {
    return _api.metrics();
  }

  @override
  Future<ServerStats> system() {
    return _api.system();
  }

  Future<List<Profile>> profiles() {
    return _api.profiles();
  }

  Future<List<LogEntry>> logs({String? streamId}) {
    return _api.logs(streamId: streamId);
  }

  Future<void> clearLogs({String? streamId}) {
    return _api.clearLogs(streamId: streamId);
  }

  Future<void> saveStream(Map<String, Object?> body) {
    return _api.saveStream(body);
  }

  Future<void> updateStream(String id, Map<String, Object?> body) {
    return _api.updateStream(id, body);
  }

  Future<void> deleteStream(String id) {
    return _api.deleteStream(id);
  }

  @override
  Future<void> startStream(String id) {
    return _api.startStream(id);
  }

  @override
  Future<void> stopStream(String id) {
    return _api.stopStream(id);
  }

  @override
  Future<void> restartStream(String id) {
    return _api.restartStream(id);
  }

  Future<CommandPreview> command(String id) {
    return _api.command(id);
  }

  Future<ProbeResult> probe(String inputUrl) {
    return _api.probe(inputUrl);
  }

  Future<void> saveProfile(Map<String, Object?> body) {
    return _api.saveProfile(body);
  }

  Future<void> updateProfile(String name, Map<String, Object?> body) {
    return _api.updateProfile(name, body);
  }

  Future<void> deleteProfile(String name) {
    return _api.deleteProfile(name);
  }

  Future<List<UserAccount>> users() {
    return _api.users();
  }

  Future<void> createUser(String username, String password) {
    return _api.createUser(username, password);
  }

  Future<void> changeUserPassword(String username, String password) {
    return _api.changeUserPassword(username, password);
  }

  Future<void> deleteUser(String username) {
    return _api.deleteUser(username);
  }

  Future<void> changePassword(String currentPassword, String newPassword) {
    return _api.changePassword(currentPassword, newPassword);
  }

  @override
  Stream<ApiEvent> events() {
    return _api.events();
  }

  @override
  Future<List<SrtRelayView>> srtRelays() => _api.srtRelays();

  @override
  Future<SrtRelayView> saveSrtRelay(Map<String, Object?> body, {String? id}) =>
      _api.saveSrtRelay(body, id: id);

  @override
  Future<void> deleteSrtRelay(String id) => _api.deleteSrtRelay(id);

  @override
  Future<void> startSrtRelay(String id) => _api.startSrtRelay(id);

  @override
  Future<void> stopSrtRelay(String id) => _api.stopSrtRelay(id);

  @override
  Future<void> restartSrtRelay(String id) => _api.restartSrtRelay(id);

  @override
  Future<List<SrtClient>> srtClients() => _api.srtClients();

  @override
  Future<SrtClientCredential> saveSrtClient(
    Map<String, Object?> body, {
    String? id,
  }) =>
      _api.saveSrtClient(body, id: id);

  @override
  Future<SrtClientCredential> rotateSrtClientKey(String id) =>
      _api.rotateSrtClientKey(id);

  @override
  Future<void> deleteSrtClient(String id) => _api.deleteSrtClient(id);

  @override
  Future<List<SrtSession>> srtSessions({bool activeOnly = false}) =>
      _api.srtSessions(activeOnly: activeOnly);

  @override
  Future<List<SrtAuditEvent>> srtAudit({
    String relayId = '',
    String clientId = '',
    String type = '',
  }) =>
      _api.srtAudit(relayId: relayId, clientId: clientId, type: type);
}
