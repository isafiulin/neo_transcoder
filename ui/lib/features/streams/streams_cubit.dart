import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/state/load_status.dart';
import '../../data/repositories/transcoder_repository.dart';

class StreamsState extends Equatable {
  const StreamsState({
    this.status = LoadStatus.initial,
    this.streams = const <StreamView>[],
    this.profiles = const <Profile>[],
    this.query = '',
    this.error = '',
  });

  final LoadStatus status;
  final List<StreamView> streams;
  final List<Profile> profiles;
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
          item.config.profileName.toLowerCase().contains(value);
    }).toList();
  }

  StreamsState copyWith({
    LoadStatus? status,
    List<StreamView>? streams,
    List<Profile>? profiles,
    String? query,
    String? error,
  }) {
    return StreamsState(
      status: status ?? this.status,
      streams: streams ?? this.streams,
      profiles: profiles ?? this.profiles,
      query: query ?? this.query,
      error: error ?? this.error,
    );
  }

  @override
  List<Object?> get props => <Object?>[status, streams, profiles, query, error];
}

class StreamsCubit extends Cubit<StreamsState> {
  StreamsCubit({required TranscoderRepository repository})
      : _repository = repository,
        super(const StreamsState());

  final TranscoderRepository _repository;

  Future<void> load() async {
    emit(state.copyWith(status: LoadStatus.loading, error: ''));
    try {
      final List<StreamView> streams = await _repository.streams();
      final List<Profile> profiles = await _repository.profiles();
      emit(state.copyWith(status: LoadStatus.ready, streams: streams, profiles: profiles));
    } on Object catch (error) {
      emit(state.copyWith(status: LoadStatus.failure, error: apiErrorMessage(error)));
    }
  }

  void setQuery(String value) {
    emit(state.copyWith(query: value));
  }

  Future<void> saveStream(Map<String, Object?> body, {String? id}) async {
    if (id == null) {
      await _repository.saveStream(body);
    } else {
      await _repository.updateStream(id, body);
    }
    await load();
  }

  Future<void> deleteStream(String id) async {
    await _repository.deleteStream(id);
    await load();
  }

  Future<void> start(String id) async {
    await _repository.startStream(id);
    await load();
  }

  Future<void> stop(String id) async {
    await _repository.stopStream(id);
    await load();
  }

  Future<void> restart(String id) async {
    await _repository.restartStream(id);
    await load();
  }

  Future<CommandPreview> command(String id) {
    return _repository.command(id);
  }

  Future<ProbeResult> probe(String inputUrl) {
    return _repository.probe(inputUrl);
  }
}
