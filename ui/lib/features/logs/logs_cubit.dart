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
    this.query = '',
    this.error = '',
  });

  final LoadStatus status;
  final List<LogEntry> logs;
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
    String? query,
    String? error,
  }) {
    return LogsState(
      status: status ?? this.status,
      logs: logs ?? this.logs,
      query: query ?? this.query,
      error: error ?? this.error,
    );
  }

  @override
  List<Object?> get props => <Object?>[status, logs, query, error];
}

class LogsCubit extends Cubit<LogsState> {
  LogsCubit({required TranscoderRepository repository})
      : _repository = repository,
        super(const LogsState());

  final TranscoderRepository _repository;
  StreamSubscription<ApiEvent>? _events;
  Timer? _refreshThrottle;
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
      final List<LogEntry> logs = await _repository.logs();
      if (isClosed) {
        return;
      }
      emit(state.copyWith(status: LoadStatus.ready, logs: logs));
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
      if (event.type == 'stream_log') {
        _scheduleRefresh();
      }
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
    await _events?.cancel();
    return super.close();
  }
}
