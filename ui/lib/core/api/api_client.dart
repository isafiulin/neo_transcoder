import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:dio/dio.dart';
import 'package:web/web.dart' as web;

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
          final String? token = AuthStore.accessToken;
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (DioException error, ErrorInterceptorHandler handler) async {
          if (await _refreshAndRetry(error, handler)) {
            return;
          }
          if (error.response?.statusCode == 401 &&
              !error.requestOptions.path.startsWith('/auth/')) {
            AuthStore.clear();
            onUnauthorized?.call();
          }
          handler.reject(_apiException(error));
        },
      ),
    );
  }

  final Dio _dio;
  void Function()? onUnauthorized;

  Future<bool> _refreshAndRetry(
      DioException error, ErrorInterceptorHandler handler) async {
    if (error.response?.statusCode != 401 ||
        error.requestOptions.extra['retried'] == true ||
        error.requestOptions.path.startsWith('/auth/')) {
      return false;
    }
    final String? refreshToken = AuthStore.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      return false;
    }
    try {
      final Dio refreshClient = Dio(BaseOptions(baseUrl: '/api'));
      final Response<Map<String, dynamic>> response =
          await refreshClient.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: <String, Object?>{'refresh_token': refreshToken},
      );
      final AuthSession session =
          AuthSession.fromJson(response.data ?? <String, dynamic>{});
      AuthStore.save(session);
      final RequestOptions request = error.requestOptions;
      request.extra['retried'] = true;
      request.headers['Authorization'] = 'Bearer ${session.accessToken}';
      handler.resolve(await _dio.fetch<dynamic>(request));
      return true;
    } on Object {
      AuthStore.clear();
      onUnauthorized?.call();
      return false;
    }
  }

  DioException _apiException(DioException error) {
    return DioException(
      requestOptions: error.requestOptions,
      response: error.response,
      type: error.type,
      error: ApiException(_messageFromDio(error)),
    );
  }

  Future<AuthSession> login(String username, String password) async {
    AuthStore.clear();
    final Response<Map<String, dynamic>> response =
        await _dio.post<Map<String, dynamic>>(
      '/auth/login',
      data: <String, Object?>{
        'username': username,
        'password': password,
      },
    );
    final AuthSession session =
        AuthSession.fromJson(response.data ?? <String, dynamic>{});
    AuthStore.save(session);
    return session;
  }

  Future<ServerInfo> health() async {
    final Response<Map<String, dynamic>> response =
        await _dio.get<Map<String, dynamic>>('/health');
    return ServerInfo.fromJson(response.data ?? <String, dynamic>{});
  }

  Future<UserAccount> verify() async {
    final Response<Map<String, dynamic>> response =
        await _dio.get<Map<String, dynamic>>('/auth/verify');
    return UserAccount.fromJson(
        response.data?['user'] as Map<String, dynamic>? ?? <String, dynamic>{});
  }

  Future<void> changePassword(
      String currentPassword, String newPassword) async {
    await _dio.post<void>(
      '/auth/change-password',
      data: <String, Object?>{
        'current_password': currentPassword,
        'new_password': newPassword,
      },
    );
    AuthStore.clear();
  }

  Future<List<UserAccount>> users() async {
    final Response<List<dynamic>> response =
        await _dio.get<List<dynamic>>('/users');
    return (response.data ?? <dynamic>[])
        .map((dynamic item) =>
            UserAccount.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> createUser(String username, String password) async {
    await _dio.post<void>(
      '/users',
      data: <String, Object?>{
        'username': username,
        'password': password,
      },
    );
  }

  Future<void> changeUserPassword(String username, String password) async {
    await _dio.put<void>(
      '/users/$username/password',
      data: <String, Object?>{'password': password},
    );
  }

  Future<void> deleteUser(String username) async {
    await _dio.delete<void>('/users/$username');
  }

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
    final Response<Map<String, dynamic>> response =
        await _dio.post<Map<String, dynamic>>(
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

  Future<void> clearLogs({String? streamId}) async {
    final path = streamId == null ? '/logs' : '/streams/$streamId/logs';
    await _dio.delete<void>(path);
  }

  Future<ServerStats> system() async {
    final Response<Map<String, dynamic>> response =
        await _dio.get<Map<String, dynamic>>('/system');
    return ServerStats.fromJson(response.data ?? <String, dynamic>{});
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

  static const List<String> _sseEventTypes = <String>[
    'stream_saved',
    'stream_deleted',
    'stream_state',
    'stream_log',
    'profile_saved',
    'profile_deleted',
  ];

  // The access token is embedded in the SSE URL because EventSource can't
  // send an Authorization header, and it's fixed for the life of that
  // connection. AccessTokenTTL is 15 minutes (see internal/auth/auth.go) -
  // if the connection ever drops and the browser's native retry reuses that
  // now-stale token, the server rejects it with 401 and EventSource treats
  // that as a terminal error (no further auto-retry), so the live tail dies
  // silently while the backend keeps working fine. Refreshing the token and
  // reconnecting proactively - both on error and on a timer well inside the
  // TTL - avoids ever hitting that dead end.
  Stream<ApiEvent> events() {
    final controller = StreamController<ApiEvent>.broadcast();
    web.EventSource? source;
    List<web.EventListener> listeners = <web.EventListener>[];
    web.EventListener? errorListener;
    Timer? reconnectTimer;
    bool cancelled = false;

    void handleEvent(web.Event event) {
      final web.MessageEvent message = event as web.MessageEvent;
      final JSAny? data = message.data;
      if (data == null) {
        return;
      }
      controller.add(
        ApiEvent.fromJson(
          jsonDecode((data as JSString).toDart) as Map<String, dynamic>,
        ),
      );
    }

    void teardown() {
      final web.EventSource? current = source;
      if (current == null) {
        return;
      }
      for (int index = 0; index < listeners.length; index++) {
        current.removeEventListener(_sseEventTypes[index], listeners[index]);
      }
      final web.EventListener? currentErrorListener = errorListener;
      if (currentErrorListener != null) {
        current.removeEventListener('error', currentErrorListener);
      }
      current.close();
      source = null;
    }

    // connect and scheduleReconnect call each other. Dart local functions
    // can't forward-reference one another the way top-level functions can,
    // so scheduleReconnect is declared as a `late` variable first - that
    // introduces the name for connect() to capture - and assigned after
    // connect() is declared.
    late void Function() scheduleReconnect;

    void connect() {
      teardown();
      final String token =
          Uri.encodeQueryComponent(AuthStore.accessToken ?? '');
      final web.EventSource newSource =
          web.EventSource('/api/events?access_token=$token');
      source = newSource;
      listeners = _sseEventTypes.map((_) => handleEvent.toJS).toList();
      for (int index = 0; index < _sseEventTypes.length; index++) {
        newSource.addEventListener(_sseEventTypes[index], listeners[index]);
      }
      errorListener = ((web.Event _) {
        controller.add(const ApiEvent(type: 'connection_error'));
        scheduleReconnect();
      }).toJS;
      newSource.addEventListener('error', errorListener);
    }

    scheduleReconnect = () {
      if (cancelled || reconnectTimer != null) {
        return;
      }
      reconnectTimer = Timer(const Duration(seconds: 3), () async {
        reconnectTimer = null;
        if (cancelled) {
          return;
        }
        final String? refreshToken = AuthStore.refreshToken;
        if (refreshToken != null && refreshToken.isNotEmpty) {
          try {
            final Dio refreshClient = Dio(BaseOptions(baseUrl: '/api'));
            final Response<Map<String, dynamic>> response =
                await refreshClient.post<Map<String, dynamic>>(
              '/auth/refresh',
              data: <String, Object?>{'refresh_token': refreshToken},
            );
            AuthStore.save(
                AuthSession.fromJson(response.data ?? <String, dynamic>{}));
          } on Object {
            // Keep whatever token we have; connect() will just trigger
            // another reconnect via the error listener if this one fails too.
          }
        }
        if (!cancelled) {
          connect();
        }
      });
    };

    connect();
    // Proactively rotate the connection with a fresh token well before the
    // 15-minute access token expires, instead of waiting for a drop to
    // reveal a stale one.
    final Timer refreshTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      if (!cancelled) {
        scheduleReconnect();
      }
    });

    controller.onCancel = () {
      cancelled = true;
      reconnectTimer?.cancel();
      refreshTimer.cancel();
      teardown();
    };
    return controller.stream;
  }
}

class AuthStore {
  static const String _accessKey = 'neotranscoder.auth.access_token';
  static const String _refreshKey = 'neotranscoder.auth.refresh_token';
  static const String _mustChangeKey =
      'neotranscoder.auth.must_change_password';
  static const String _usernameKey = 'neotranscoder.auth.username';

  static String? get accessToken {
    return web.window.localStorage.getItem(_accessKey);
  }

  static String? get refreshToken {
    return web.window.localStorage.getItem(_refreshKey);
  }

  static bool get isAuthenticated {
    final String? value = accessToken;
    return value != null && value.isNotEmpty;
  }

  static bool get mustChangePassword {
    return web.window.localStorage.getItem(_mustChangeKey) == 'true';
  }

  static String get username {
    return web.window.localStorage.getItem(_usernameKey) ?? '';
  }

  static void save(AuthSession session) {
    web.window.localStorage.setItem(_accessKey, session.accessToken);
    web.window.localStorage.setItem(_refreshKey, session.refreshToken);
    web.window.localStorage
        .setItem(_mustChangeKey, session.mustChangePassword ? 'true' : 'false');
    web.window.localStorage.setItem(_usernameKey, session.user.username);
  }

  static void clear() {
    web.window.localStorage.removeItem(_accessKey);
    web.window.localStorage.removeItem(_refreshKey);
    web.window.localStorage.removeItem(_mustChangeKey);
    web.window.localStorage.removeItem(_usernameKey);
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
    return (error.error as ApiException).message;
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
    case DioExceptionType.transformTimeout:
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
