import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'package:dio/dio.dart';

import 'models.dart';

class ApiClient {
  ApiClient()
      : _dio = Dio(
          BaseOptions(
            baseUrl: '/api',
            connectTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 20),
          ),
        ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          final String? token = AuthStore.token;
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (DioException error, ErrorInterceptorHandler handler) {
          handler.reject(
            DioException(
              requestOptions: error.requestOptions,
              response: error.response,
              type: error.type,
              error: ApiException(_messageFromDio(error)),
            ),
          );
        },
      ),
    );
  }

  final Dio _dio;

  Future<List<StreamView>> streams() async {
    final response = await _dio.get<List<dynamic>>('/streams');
    return (response.data ?? [])
        .map((item) => StreamView.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<Profile>> profiles() async {
    final response = await _dio.get<List<dynamic>>('/profiles');
    return (response.data ?? [])
        .map((item) => Profile.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveStream(Map<String, Object?> body) async {
    await _dio.post<void>('/streams', data: body);
  }

  Future<void> updateStream(String id, Map<String, Object?> body) async {
    await _dio.put<void>('/streams/$id', data: body);
  }

  Future<void> deleteStream(String id) async {
    await _dio.delete<void>('/streams/$id');
  }

  Future<void> saveProfile(Map<String, Object?> body) async {
    await _dio.post<void>('/profiles', data: body);
  }

  Future<void> updateProfile(String name, Map<String, Object?> body) async {
    await _dio.put<void>('/profiles/$name', data: body);
  }

  Future<void> deleteProfile(String name) async {
    await _dio.delete<void>('/profiles/$name');
  }

  Future<ProbeResult> probe(String inputUrl) async {
    final Response<Map<String, dynamic>> response = await _dio.post<Map<String, dynamic>>(
      '/probe',
      data: <String, Object?>{'input_url': inputUrl},
    );
    return ProbeResult.fromJson(response.data ?? <String, dynamic>{});
  }

  Future<List<LogEntry>> logs({String? streamId, int limit = 200}) async {
    final path = streamId == null ? '/logs' : '/streams/$streamId/logs';
    final response = await _dio.get<List<dynamic>>(
      path,
      queryParameters: {'limit': limit},
    );
    return (response.data ?? [])
        .map((item) => LogEntry.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<StreamView>> metrics() async {
    final response = await _dio.get<List<dynamic>>('/metrics');
    return (response.data ?? [])
        .map((item) => StreamView.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> startStream(String id) async {
    await _dio.post<void>('/streams/$id/start');
  }

  Future<void> stopStream(String id) async {
    await _dio.post<void>('/streams/$id/stop');
  }

  Future<void> restartStream(String id) async {
    await _dio.post<void>('/streams/$id/restart');
  }

  Future<CommandPreview> command(String id) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/streams/$id/ffmpeg-command',
    );
    return CommandPreview.fromJson(response.data ?? {});
  }

  Stream<ApiEvent> events() {
    final controller = StreamController<ApiEvent>.broadcast();
    final source = html.EventSource('/api/events');

    void handleEvent(html.Event event) {
      final html.MessageEvent message = event as html.MessageEvent;
      if (message.data == null) {
        return;
      }
      controller.add(
        ApiEvent.fromJson(
          jsonDecode(message.data as String) as Map<String, dynamic>,
        ),
      );
    }

    const List<String> eventTypes = <String>[
      'stream_saved',
      'stream_deleted',
      'stream_state',
      'stream_log',
      'profile_saved',
      'profile_deleted',
    ];
    for (final String type in eventTypes) {
      source.addEventListener(type, handleEvent);
    }
    final StreamSubscription<html.Event> errorSubscription = source.onError.listen((html.Event _) {
      controller.add(const ApiEvent(type: 'connection_error'));
    });
    controller.onCancel = () async {
      await errorSubscription.cancel();
      source.close();
    };
    return controller.stream;
  }
}

class AuthStore {
  static const String _key = 'neotranscoder.auth.token';
  static const String _openKey = 'neotranscoder.auth.open';

  static String? get token {
    return html.window.localStorage[_key];
  }

  static bool get isAuthenticated {
    final String? value = token;
    return html.window.localStorage[_openKey] == 'true' || (value != null && value.isNotEmpty);
  }

  static void save(String token) {
    html.window.localStorage.remove(_openKey);
    html.window.localStorage[_key] = token;
  }

  static void continueWithoutToken() {
    html.window.localStorage.remove(_key);
    html.window.localStorage[_openKey] = 'true';
  }

  static void clear() {
    html.window.localStorage.remove(_key);
    html.window.localStorage.remove(_openKey);
  }
}

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() {
    return message;
  }
}

String apiErrorMessage(Object error) {
  if (error is DioException && error.error is ApiException) {
    return (error.error! as ApiException).message;
  }
  if (error is ApiException) {
    return error.message;
  }
  return error.toString();
}

String _messageFromDio(DioException error) {
  final Object? data = error.response?.data;
  if (data is Map<String, dynamic>) {
    final Object? message = data['error'];
    if (message is String && message.isNotEmpty) {
      return message;
    }
  }
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.sendTimeout:
      return 'Request timed out';
    case DioExceptionType.connectionError:
      return 'Cannot connect to NeoTranscoder API';
    case DioExceptionType.badResponse:
      return 'NeoTranscoder API returned ${error.response?.statusCode ?? 'an error'}';
    case DioExceptionType.cancel:
      return 'Request was cancelled';
    case DioExceptionType.badCertificate:
      return 'Bad TLS certificate';
    case DioExceptionType.unknown:
      return 'Unexpected API error';
  }
}
