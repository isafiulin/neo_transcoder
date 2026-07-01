import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:neotranscoder_ui/core/api/api_client.dart';
import 'package:neotranscoder_ui/core/api/models.dart';
import 'package:neotranscoder_ui/core/state/load_status.dart';
import 'package:neotranscoder_ui/data/repositories/transcoder_repository.dart';

class LogsState extends Equatable {
  const LogsState({
    this.status = LoadStatus.initial,
    this.logs = const <LogEntry>[],
    this.streams = const <StreamView>[],
    this.streamId = '',
    this.query = '',
    this.error = '',
  });

  final LoadStatus status;
  final List<LogEntry> logs;
  final List<StreamView> streams;
  final String streamId;
  final String query;
  final String error;

  List<LogEntry> get filtered {
    final String value = query.trim().toLowerCase();
    if (value.isEmpty) {
      return logs;
    }
    return logs.where((LogEntry log) {
      return log.streamId.toLowerCase().contains(value) ||
          log.message.toLowerCase().contains(value) ||
          log.code.toLowerCase().contains(value);
    }).toList();
  }

  LogsState copyWith({
    LoadStatus? status,
    List<LogEntry>? logs,
    List<StreamView>? streams,
    String? streamId,
    String? query,
    String? error,
  }) {
    return LogsState(
      status: status ?? this.status,
      logs: logs ?? this.logs,
      streams: streams ?? this.streams,
      streamId: streamId ?? this.streamId,
      query: query ?? this.query,
      error: error ?? this.error,
    );
  }

  @override
  List<Object?> get props =>
      <Object?>[status, logs, streams, streamId, query, error];
}

class LogsCubit extends Cubit<LogsState> {
  LogsCubit({required TranscoderRepository repository})
      : _repository = repository,
        super(const LogsState());

  final TranscoderRepository _repository;
  StreamSubscription<ApiEvent>? _events;
  Timer? _refreshThrottle;
  // Falls back to a plain periodic reload independent of the SSE stream, so
  // the log view keeps updating even if live-tail events stop arriving for
  // some reason the reconnect logic in ApiClient.events() doesn't catch.
  Timer? _pollTimer;
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
      final String? streamId = state.streamId.isEmpty ? null : state.streamId;
      final List<Object> results = await Future.wait(<Future<Object>>[
        _repository.logs(streamId: streamId),
        _repository.streams(),
      ]);
      if (isClosed) {
        return;
      }
      emit(state.copyWith(
        status: LoadStatus.ready,
        logs: results[0] as List<LogEntry>,
        streams: results[1] as List<StreamView>,
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

  void setStreamId(String value) {
    emit(state.copyWith(streamId: value));
    unawaited(load());
  }

  Future<void> clear() async {
    final String? streamId = state.streamId.isEmpty ? null : state.streamId;
    await _repository.clearLogs(streamId: streamId);
    await load();
  }

  void subscribe() {
    _events ??= _repository.events().listen((ApiEvent event) {
      if (event.type == 'stream_log') {
        _scheduleRefresh();
      }
    });
    _pollTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(load());
    });
  }

  void _scheduleRefresh() {
    if (_refreshThrottle != null || isClosed) {
      return;
    }
    _refreshThrottle = Timer(const Duration(milliseconds: 500), () {
      _refreshThrottle = null;
      unawaited(load());
    });
  }

  @override
  Future<void> close() async {
    _refreshThrottle?.cancel();
    _pollTimer?.cancel();
    await _events?.cancel();
    return super.close();
  }
}
