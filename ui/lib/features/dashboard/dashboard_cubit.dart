import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/state/load_status.dart';
import '../../data/repositories/transcoder_repository.dart';

class DashboardState extends Equatable {
  const DashboardState({
    this.status = LoadStatus.initial,
    this.streams = const <StreamView>[],
    this.query = '',
    this.error = '',
  });

  final LoadStatus status;
  final List<StreamView> streams;
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
    String? query,
    String? error,
  }) {
    return DashboardState(
      status: status ?? this.status,
      streams: streams ?? this.streams,
      query: query ?? this.query,
      error: error ?? this.error,
    );
  }

  @override
  List<Object?> get props => <Object?>[status, streams, query, error];
}

class DashboardCubit extends Cubit<DashboardState> {
  DashboardCubit({required TranscoderRepository repository})
      : _repository = repository,
        super(const DashboardState());

  final TranscoderRepository _repository;
  StreamSubscription<ApiEvent>? _events;

  Future<void> load() async {
    emit(state.copyWith(status: LoadStatus.loading, error: ''));
    try {
      final List<StreamView> streams = await _repository.metrics();
      emit(state.copyWith(status: LoadStatus.ready, streams: streams));
    } on Object catch (error) {
      emit(state.copyWith(status: LoadStatus.failure, error: apiErrorMessage(error)));
    }
  }

  void setQuery(String value) {
    emit(state.copyWith(query: value));
  }

  void subscribe() {
    _events ??= _repository.events().listen((ApiEvent event) {
      if (event.type.startsWith('stream_')) {
        load();
      }
    });
  }

  @override
  Future<void> close() async {
    await _events?.cancel();
    return super.close();
  }
}
