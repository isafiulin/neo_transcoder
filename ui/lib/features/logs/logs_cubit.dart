import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/state/load_status.dart';
import '../../data/repositories/transcoder_repository.dart';

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

  Future<void> load() async {
    emit(state.copyWith(status: LoadStatus.loading, error: ''));
    try {
      final List<LogEntry> logs = await _repository.logs();
      emit(state.copyWith(status: LoadStatus.ready, logs: logs));
    } on Object catch (error) {
      emit(state.copyWith(status: LoadStatus.failure, error: apiErrorMessage(error)));
    }
  }

  void setQuery(String value) {
    emit(state.copyWith(query: value));
  }
}
