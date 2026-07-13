import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:neotranscoder_ui/core/api/api_error.dart';
import 'package:neotranscoder_ui/core/api/models.dart';
import 'package:neotranscoder_ui/core/api/srt_models.dart';
import 'package:neotranscoder_ui/core/state/load_status.dart';
import 'package:neotranscoder_ui/data/repositories/dashboard_repository.dart';

class DashboardState extends Equatable {
  const DashboardState({
    this.status = LoadStatus.initial,
    this.streams = const <StreamView>[],
    this.srtRelays = const <SrtRelayView>[],
    this.srtSessions = const <SrtSession>[],
    this.server = const ServerStats(),
    this.query = '',
    this.error = '',
  });

  final LoadStatus status;
  final List<StreamView> streams;
  final List<SrtRelayView> srtRelays;
  final List<SrtSession> srtSessions;
  final ServerStats server;
  final String query;
  final String error;

  List<StreamView> get filtered {
    final String value = query.trim().toLowerCase();
    if (value.isEmpty) {
      return streams;
    }
    return streams.where((StreamView item) {
      return item.config.name.toLowerCase().contains(value) ||
          item.config.id.toLowerCase().contains(value) ||
          item.config.inputUrl.toLowerCase().contains(value) ||
          item.config.outputUrl.toLowerCase().contains(value);
    }).toList();
  }

  List<SrtRelayView> get filteredSrtRelays {
    final String value = query.trim().toLowerCase();
    if (value.isEmpty) {
      return srtRelays;
    }
    return srtRelays.where((SrtRelayView item) {
      return item.config.name.toLowerCase().contains(value) ||
          item.config.id.toLowerCase().contains(value) ||
          item.config.inputUrl.toLowerCase().contains(value) ||
          item.config.bindAddress.toLowerCase().contains(value) ||
          '${item.config.port}'.contains(value);
    }).toList();
  }

  List<SrtSession> get activeSrtSessions =>
      srtSessions.where((SrtSession session) => session.isActive).toList();

  DashboardState copyWith({
    LoadStatus? status,
    List<StreamView>? streams,
    List<SrtRelayView>? srtRelays,
    List<SrtSession>? srtSessions,
    ServerStats? server,
    String? query,
    String? error,
  }) {
    return DashboardState(
      status: status ?? this.status,
      streams: streams ?? this.streams,
      srtRelays: srtRelays ?? this.srtRelays,
      srtSessions: srtSessions ?? this.srtSessions,
      server: server ?? this.server,
      query: query ?? this.query,
      error: error ?? this.error,
    );
  }

  @override
  List<Object?> get props => <Object?>[
        status,
        streams,
        srtRelays,
        srtSessions,
        server,
        query,
        error,
      ];
}

class DashboardCubit extends Cubit<DashboardState> {
  DashboardCubit({required DashboardRepository repository})
      : _repository = repository,
        super(const DashboardState());

  final DashboardRepository _repository;
  StreamSubscription<ApiEvent>? _events;
  bool _loading = false;
  bool _reloadQueued = false;

  Future<void> load() async {
    if (isClosed) {
      return;
    }
    if (_loading) {
      _reloadQueued = true;
      return;
    }
    _loading = true;
    final LoadStatus status =
        state.status == LoadStatus.initial || state.status == LoadStatus.failure
            ? LoadStatus.loading
            : state.status;
    emit(state.copyWith(status: status, error: ''));
    try {
      final List<Object> results = await Future.wait(<Future<Object>>[
        _repository.metrics(),
        _repository.system(),
        _repository.srtRelays(),
        _repository.srtSessions(activeOnly: true),
      ]);
      if (isClosed) {
        return;
      }
      emit(state.copyWith(
        status: LoadStatus.ready,
        streams: results[0] as List<StreamView>,
        server: results[1] as ServerStats,
        srtRelays: results[2] as List<SrtRelayView>,
        srtSessions: results[3] as List<SrtSession>,
      ));
    } on Object catch (error) {
      if (isClosed) {
        return;
      }
      emit(state.copyWith(
          status: LoadStatus.failure, error: apiErrorMessage(error)));
    } finally {
      _loading = false;
      if (_reloadQueued && !isClosed) {
        _reloadQueued = false;
        unawaited(load());
      }
    }
  }

  void setQuery(String value) {
    emit(state.copyWith(query: value));
  }

  void subscribe() {
    _events ??= _repository.events().listen((ApiEvent event) {
      if (event.type == 'stream_state') {
        _applyStreamState(event);
      } else if (event.srtRelayState != null) {
        _applySrtRelayState(event);
      } else if (event.srtSession != null) {
        _applySrtSession(event.srtSession!);
      } else if (_refreshEvents.contains(event.type)) {
        load();
      }
    });
  }

  void _applySrtRelayState(ApiEvent event) {
    final SrtRelayState relayState = event.srtRelayState!;
    final int index = state.srtRelays.indexWhere(
      (SrtRelayView item) => item.config.id == event.relayId,
    );
    if (index == -1) {
      unawaited(load());
      return;
    }
    final List<SrtRelayView> relays = List<SrtRelayView>.of(state.srtRelays);
    relays[index] = SrtRelayView(
      config: relays[index].config,
      state: relayState,
    );
    emit(state.copyWith(status: LoadStatus.ready, srtRelays: relays));
  }

  void _applySrtSession(SrtSession session) {
    final List<SrtSession> sessions = List<SrtSession>.of(state.srtSessions);
    final int index = sessions.indexWhere(
      (SrtSession item) => item.id == session.id,
    );
    if (index == -1) {
      sessions.insert(0, session);
    } else {
      sessions[index] = session;
    }
    emit(state.copyWith(srtSessions: sessions));
  }

  void _applyStreamState(ApiEvent event) {
    final StreamState? streamState = event.streamState;
    if (streamState == null || event.streamId.isEmpty || isClosed) {
      return;
    }
    final int index = state.streams.indexWhere(
      (StreamView item) => item.config.id == event.streamId,
    );
    if (index == -1) {
      return;
    }
    final List<StreamView> streams = List<StreamView>.of(state.streams);
    streams[index] = StreamView(
      config: streams[index].config,
      state: streamState,
    );
    emit(state.copyWith(status: LoadStatus.ready, streams: streams));
  }

  Future<void> startStream(String id) async {
    await _repository.startStream(id);
    await load();
  }

  Future<void> stopStream(String id) async {
    await _repository.stopStream(id);
    await load();
  }

  Future<void> restartStream(String id) async {
    await _repository.restartStream(id);
    await load();
  }

  Future<void> startSrtRelay(String id) async {
    await _repository.startSrtRelay(id);
    await load();
  }

  Future<void> stopSrtRelay(String id) async {
    await _repository.stopSrtRelay(id);
    await load();
  }

  Future<void> restartSrtRelay(String id) async {
    await _repository.restartSrtRelay(id);
    await load();
  }

  @override
  Future<void> close() async {
    await _events?.cancel();
    return super.close();
  }
}

const Set<String> _refreshEvents = <String>{
  'stream_saved',
  'stream_deleted',
  'srt_relay_saved',
  'srt_relay_deleted',
};
