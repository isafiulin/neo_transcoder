import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neotranscoder_ui/app/theme.dart';
import 'package:neotranscoder_ui/core/api/models.dart';
import 'package:neotranscoder_ui/core/api/srt_models.dart';
import 'package:neotranscoder_ui/data/repositories/dashboard_repository.dart';
import 'package:neotranscoder_ui/features/dashboard/dashboard_cubit.dart';
import 'package:neotranscoder_ui/features/dashboard/dashboard_screen.dart';

void main() {
  test('dashboard patches SRT metrics and sessions without polling', () async {
    final _FakeDashboardRepository repository = _FakeDashboardRepository();
    final DashboardCubit cubit = DashboardCubit(repository: repository);
    await cubit.load();
    cubit.subscribe();
    final int loadsBeforeEvents = repository.srtRelayLoads;

    repository.addEvent(ApiEvent(
      type: 'srt_relay_metrics',
      relayId: 'news-srt',
      srtRelayState: _relayState(inputBitrateBps: 4000000),
    ));
    repository.addEvent(ApiEvent(
      type: 'srt_session_connected',
      relayId: 'news-srt',
      srtSession: _session(),
    ));
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state.srtRelays.single.state.inputBitrateBps, 4000000);
    expect(cubit.state.activeSrtSessions.single.clientId, 'partner-a');
    expect(repository.srtRelayLoads, loadsBeforeEvents);
    await cubit.close();
    await repository.close();
  });

  testWidgets('dashboard renders SRT relay on a narrow viewport',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final _FakeDashboardRepository repository = _FakeDashboardRepository();
    final DashboardCubit cubit = DashboardCubit(repository: repository);
    await cubit.load();
    addTearDown(cubit.close);
    addTearDown(repository.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: NeoTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: BlocProvider<DashboardCubit>.value(
              value: cubit,
              child: const DashboardScreen(),
            ),
          ),
        ),
      ),
    );

    expect(find.text('News SRT'), findsOneWidget);
    expect(find.text('4.00 Mb/s'), findsOneWidget);
    expect(find.text('AES-256 · 1 active'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeDashboardRepository implements DashboardRepository {
  final StreamController<ApiEvent> _events =
      StreamController<ApiEvent>.broadcast();
  int srtRelayLoads = 0;

  void addEvent(ApiEvent event) => _events.add(event);

  Future<void> close() => _events.close();

  @override
  Stream<ApiEvent> events() => _events.stream;

  @override
  Future<List<StreamView>> metrics() async => <StreamView>[];

  @override
  Future<ServerStats> system() async => const ServerStats();

  @override
  Future<List<SrtRelayView>> srtRelays() async {
    srtRelayLoads++;
    return <SrtRelayView>[
      SrtRelayView(
        config: SrtRelay.fromJson(<String, dynamic>{
          'id': 'news-srt',
          'name': 'News SRT',
          'input_url': 'udp://239.10.10.1:1234',
          'bind_address': '0.0.0.0',
          'port': 9000,
          'enabled': true,
        }),
        state: _relayState(inputBitrateBps: 4000000),
      ),
    ];
  }

  @override
  Future<List<SrtSession>> srtSessions({bool activeOnly = false}) async =>
      <SrtSession>[_session()];

  @override
  Future<void> restartSrtRelay(String id) async {}

  @override
  Future<void> restartStream(String id) async {}

  @override
  Future<void> startSrtRelay(String id) async {}

  @override
  Future<void> startStream(String id) async {}

  @override
  Future<void> stopSrtRelay(String id) async {}

  @override
  Future<void> stopStream(String id) async {}
}

SrtRelayState _relayState({int inputBitrateBps = 0}) =>
    SrtRelayState.fromJson(<String, dynamic>{
      'status': 'running',
      'active_clients': 1,
      'input_bitrate_bps': inputBitrateBps,
      'output_bitrate_bps': 4000000,
    });

SrtSession _session() => SrtSession.fromJson(<String, dynamic>{
      'id': 'session-1',
      'relay_id': 'news-srt',
      'client_id': 'partner-a',
      'remote_ip': '203.0.113.10',
      'encrypted': true,
      'connected_at': '2026-07-13T10:00:00Z',
    });
