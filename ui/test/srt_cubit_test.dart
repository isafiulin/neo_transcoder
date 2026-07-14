import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neotranscoder_ui/app/theme.dart';
import 'package:neotranscoder_ui/core/api/models.dart';
import 'package:neotranscoder_ui/core/api/srt_models.dart';
import 'package:neotranscoder_ui/core/state/load_status.dart';
import 'package:neotranscoder_ui/data/repositories/srt_repository.dart';
import 'package:neotranscoder_ui/features/srt/srt_client_editor_screen.dart';
import 'package:neotranscoder_ui/features/srt/srt_cubit.dart';
import 'package:neotranscoder_ui/features/srt/srt_relay_editor_screen.dart';

void main() {
  test('SRT client payload defaults old data to AES and reads no-key mode', () {
    final SrtClient legacy = SrtClient.fromJson(<String, dynamic>{
      'id': 'legacy-payload',
    });
    final SrtClient noKey = SrtClient.fromJson(<String, dynamic>{
      'id': 'no-key',
      'encryption_mode': 'none',
    });
    expect(legacy.encryptionMode, 'aes-256');
    expect(noKey.encryptionMode, 'none');
  });

  testWidgets('client editor exposes IP ACL only mode on a narrow screen',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final _FakeSrtRepository repository = _FakeSrtRepository()
      ..relays = <SrtRelayView>[_relayView()];
    final SrtCubit cubit = SrtCubit(repository: repository);
    await cubit.load();
    addTearDown(cubit.close);
    addTearDown(repository.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: NeoTheme.light(),
        home: Scaffold(
          body: BlocProvider<SrtCubit>.value(
            value: cubit,
            child: const SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: SrtClientEditorScreen(),
            ),
          ),
        ),
      ),
    );

    expect(find.text('AES-256 + IP ACL'), findsOneWidget);
    await tester.tap(find.text('IP ACL only'));
    await tester.pump();
    expect(find.textContaining('Media is sent without encryption'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'listener editor exposes an explicit compatibility default client',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final _FakeSrtRepository repository = _FakeSrtRepository()
      ..relays = <SrtRelayView>[_relayView(allowMissingStreamId: true)]
      ..clients = <SrtClient>[
        SrtClient.fromJson(<String, dynamic>{
          'id': 'vlc-client',
          'name': 'VLC client',
          'enabled': true,
          'allowed_relay_ids': <String>['news-srt'],
          'allowed_cidrs': <String>['203.0.113.10/32'],
          'max_sessions': 1,
        }),
      ];
    final SrtCubit cubit = SrtCubit(repository: repository);
    await cubit.load();
    addTearDown(cubit.close);
    addTearDown(repository.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: NeoTheme.light(),
        home: Scaffold(
          body: BlocProvider<SrtCubit>.value(
            value: cubit,
            child: const SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: SrtRelayEditorScreen(relayId: 'news-srt'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Allow connections without Stream ID'), findsOneWidget);
    expect(find.text('Default client'), findsOneWidget);
    expect(find.text('VLC client'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('load reports API failure instead of leaving loading state', () async {
    final _FakeSrtRepository repository = _FakeSrtRepository()
      ..loadError = StateError('backend unavailable');
    final SrtCubit cubit = SrtCubit(repository: repository);
    await cubit.load();
    expect(cubit.state.status, LoadStatus.failure);
    expect(cubit.state.error, contains('backend unavailable'));
    await cubit.close();
  });

  test('SSE patches metrics and sessions without polling configuration',
      () async {
    final _FakeSrtRepository repository = _FakeSrtRepository()
      ..relays = <SrtRelayView>[_relayView()];
    final SrtCubit cubit = SrtCubit(repository: repository);
    await cubit.load();
    cubit.subscribe();
    final int loadsBeforeEvents = repository.relayLoads;

    repository.addEvent(ApiEvent(
      type: 'srt_relay_metrics',
      relayId: 'news-srt',
      srtRelayState: _relayState(status: 'degraded', inputBitrate: 0),
    ));
    repository.addEvent(ApiEvent(
      type: 'srt_session_connected',
      relayId: 'news-srt',
      srtSession: _session(),
    ));
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state.relay('news-srt')?.state.status, 'degraded');
    expect(cubit.state.sessions.single.id, 'session-1');
    expect(repository.relayLoads, loadsBeforeEvents);
    await cubit.close();
    await repository.close();
  });

  test('configuration SSE coalesces reloads', () async {
    final _FakeSrtRepository repository = _FakeSrtRepository()
      ..relays = <SrtRelayView>[_relayView()];
    final SrtCubit cubit = SrtCubit(repository: repository);
    await cubit.load();
    cubit.subscribe();
    final int before = repository.relayLoads;
    repository.addEvent(const ApiEvent(type: 'srt_relay_saved'));
    repository.addEvent(const ApiEvent(type: 'srt_client_saved'));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(repository.relayLoads, before + 1);
    await cubit.close();
    await repository.close();
  });

  test('audit SSE obeys active filters and caps retained events', () async {
    final _FakeSrtRepository repository = _FakeSrtRepository();
    final SrtCubit cubit = SrtCubit(repository: repository);
    await cubit.load();
    await cubit.reloadAudit(relayId: 'news-srt');
    cubit.subscribe();
    repository.addEvent(ApiEvent(
      type: 'srt_audit',
      srtAuditEvent: _audit('other-relay'),
    ));
    repository.addEvent(ApiEvent(
      type: 'srt_audit',
      srtAuditEvent: _audit('news-srt'),
    ));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(cubit.state.audit, hasLength(1));
    expect(cubit.state.audit.single.relayId, 'news-srt');
    await cubit.close();
    await repository.close();
  });

  test('audit SSE batches bursts and keeps a bounded visible window', () async {
    final _FakeSrtRepository repository = _FakeSrtRepository();
    final SrtCubit cubit = SrtCubit(repository: repository);
    await cubit.load();
    cubit.subscribe();
    for (int index = 0; index < 600; index++) {
      repository.addEvent(ApiEvent(
        type: 'srt_audit',
        srtAuditEvent: SrtAuditEvent.fromJson(<String, dynamic>{
          'id': 'audit-$index',
          'time': '2026-07-14T00:00:00Z',
          'type': 'connection_rejected',
          'level': 'warning',
          'relay_id': 'news-srt',
        }),
      ));
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(cubit.state.audit, hasLength(500));
    expect(cubit.state.audit.first.id, 'audit-599');
    expect(cubit.state.audit.last.id, 'audit-100');
    await cubit.close();
    await repository.close();
  });

  test('failed command clears busy state and rethrows', () async {
    final _FakeSrtRepository repository = _FakeSrtRepository()
      ..operationError = StateError('worker failed');
    final SrtCubit cubit = SrtCubit(repository: repository);
    await expectLater(cubit.startRelay('news-srt'), throwsStateError);
    expect(cubit.state.busyIds, isEmpty);
    expect(cubit.state.error, contains('worker failed'));
    await cubit.close();
    await repository.close();
  });

  test('late load completion does not emit after Cubit close', () async {
    final Completer<List<SrtRelayView>> pending =
        Completer<List<SrtRelayView>>();
    final _FakeSrtRepository repository = _FakeSrtRepository()
      ..pendingRelays = pending;
    final SrtCubit cubit = SrtCubit(repository: repository);
    final Future<void> load = cubit.load();
    await cubit.close();
    pending.complete(<SrtRelayView>[]);
    await expectLater(load, completes);
    await repository.close();
  });
}

class _FakeSrtRepository implements SrtRepository {
  final StreamController<ApiEvent> _events =
      StreamController<ApiEvent>.broadcast();
  List<SrtRelayView> relays = <SrtRelayView>[];
  List<SrtClient> clients = <SrtClient>[];
  List<SrtSession> sessions = <SrtSession>[];
  List<SrtAuditEvent> audit = <SrtAuditEvent>[];
  Object? loadError;
  Object? operationError;
  Completer<List<SrtRelayView>>? pendingRelays;
  int relayLoads = 0;

  void addEvent(ApiEvent event) => _events.add(event);

  Future<void> close() => _events.close();

  @override
  Stream<ApiEvent> events() => _events.stream;

  @override
  Future<List<SrtRelayView>> srtRelays() {
    relayLoads++;
    if (loadError case final Object error) {
      return Future<List<SrtRelayView>>.error(error);
    }
    return pendingRelays?.future ?? Future<List<SrtRelayView>>.value(relays);
  }

  @override
  Future<List<SrtClient>> srtClients() =>
      _load<List<SrtClient>>(List<SrtClient>.of(clients));

  @override
  Future<List<SrtSession>> srtSessions({bool activeOnly = false}) =>
      _load<List<SrtSession>>(List<SrtSession>.of(sessions));

  @override
  Future<List<SrtAuditEvent>> srtAudit({
    String relayId = '',
    String clientId = '',
    String type = '',
  }) =>
      _load<List<SrtAuditEvent>>(List<SrtAuditEvent>.of(audit));

  @override
  Future<void> clearSrtAudit({
    String relayId = '',
    String clientId = '',
    String type = '',
  }) {
    audit = <SrtAuditEvent>[];
    return _operate();
  }

  Future<T> _load<T>(T value) {
    if (loadError case final Object error) {
      return Future<T>.error(error);
    }
    return Future<T>.value(value);
  }

  Future<void> _operate() {
    if (operationError case final Object error) {
      return Future<void>.error(error);
    }
    return Future<void>.value();
  }

  @override
  Future<void> deleteSrtClient(String id) => _operate();

  @override
  Future<void> deleteSrtRelay(String id) => _operate();

  @override
  Future<void> restartSrtRelay(String id) => _operate();

  @override
  Future<SrtClientCredential> rotateSrtClientKey(String id) =>
      throw UnimplementedError();

  @override
  Future<SrtClientCredential> saveSrtClient(
    Map<String, Object?> body, {
    String? id,
  }) =>
      throw UnimplementedError();

  @override
  Future<SrtRelayView> saveSrtRelay(Map<String, Object?> body, {String? id}) =>
      throw UnimplementedError();

  @override
  Future<void> startSrtRelay(String id) => _operate();

  @override
  Future<void> stopSrtRelay(String id) => _operate();
}

SrtRelayView _relayView({bool allowMissingStreamId = false}) => SrtRelayView(
      config: SrtRelay.fromJson(<String, dynamic>{
        'id': 'news-srt',
        'name': 'News SRT',
        'input_url': 'udp://239.10.10.1:1234',
        'bind_address': '0.0.0.0',
        'port': 9000,
        'allow_missing_stream_id': allowMissingStreamId,
        'default_client_id': allowMissingStreamId ? 'vlc-client' : '',
        'enabled': true,
      }),
      state: _relayState(),
    );

SrtRelayState _relayState({
  String status = 'running',
  int inputBitrate = 4000000,
}) =>
    SrtRelayState.fromJson(<String, dynamic>{
      'status': status,
      'pid': 123,
      'input_bitrate_bps': inputBitrate,
    });

SrtSession _session() => SrtSession.fromJson(<String, dynamic>{
      'id': 'session-1',
      'relay_id': 'news-srt',
      'client_id': 'partner-a',
      'remote_ip': '203.0.113.10',
      'encrypted': true,
      'connected_at': '2026-07-13T10:00:00Z',
    });

SrtAuditEvent _audit(String relayId) =>
    SrtAuditEvent.fromJson(<String, dynamic>{
      'id': 'audit-$relayId',
      'type': 'connection_rejected',
      'relay_id': relayId,
    });
