import 'package:neotranscoder_ui/core/api/api_client.dart';
import 'package:neotranscoder_ui/core/api/models.dart';

class TranscoderRepository {
  TranscoderRepository({required ApiClient api}) : _api = api;

  final ApiClient _api;

  ApiClient get api {
    return _api;
  }

  Future<List<StreamView>> streams() {
    return _api.streams();
  }

  Future<List<StreamView>> metrics() {
    return _api.metrics();
  }

  Future<List<Profile>> profiles() {
    return _api.profiles();
  }

  Future<List<LogEntry>> logs() {
    return _api.logs();
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

  Future<void> startStream(String id) {
    return _api.startStream(id);
  }

  Future<void> stopStream(String id) {
    return _api.stopStream(id);
  }

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

  Stream<ApiEvent> events() {
    return _api.events();
  }
}
