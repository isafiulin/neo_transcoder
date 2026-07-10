import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:neotranscoder_ui/core/api/api_client.dart';
import 'package:neotranscoder_ui/core/api/models.dart';
import 'package:neotranscoder_ui/core/state/load_status.dart';
import 'package:neotranscoder_ui/data/repositories/transcoder_repository.dart';

class DashboardState extends Equatable {
  const DashboardState({
    this.status = LoadStatus.initial,
    this.streams = const <StreamView>[],
    this.server = const ServerStats(),
    this.query = '',
    this.error = '',
  });

  final LoadStatus status;
  final List<StreamView> streams;
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

  DashboardState copyWith({
    LoadStatus? status,
    List<StreamView>? streams,
    ServerStats? server,
    String? query,
    String? error,
  }) {
    return DashboardState(
      status: status ?? this.status,
      streams: streams ?? this.streams,
      server: server ?? this.server,
      query: query ?? this.query,
      error: error ?? this.error,
    );
  }

  @override
  List<Object?> get props => <Object?>[status, streams, server, query, error];
}

class DashboardCubit extends Cubit<DashboardState> {
  DashboardCubit({required TranscoderRepository repository})
      : _repository = repository,
        super(const DashboardState());

  final TranscoderRepository _repository;
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
      ]);
      if (isClosed) {
        return;
      }
      emit(state.copyWith(
        status: LoadStatus.ready,
        streams: results[0] as List<StreamView>,
        server: results[1] as ServerStats,
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
      } else if (_refreshEvents.contains(event.type)) {
        load();
      }
    });
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

  @override
  Future<void> close() async {
    await _events?.cancel();
    return super.close();
  }
}

const Set<String> _refreshEvents = <String>{
  'stream_saved',
  'stream_deleted',
};
