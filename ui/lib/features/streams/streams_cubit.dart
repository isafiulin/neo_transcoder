import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:neotranscoder_ui/core/api/api_client.dart';
import 'package:neotranscoder_ui/core/api/models.dart';
import 'package:neotranscoder_ui/core/state/load_status.dart';
import 'package:neotranscoder_ui/data/repositories/transcoder_repository.dart';

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
      final List<StreamView> streams = await _repository.streams();
      final List<Profile> profiles = await _repository.profiles();
      if (isClosed) {
        return;
      }
      emit(state.copyWith(
          status: LoadStatus.ready, streams: streams, profiles: profiles));
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

  @override
  Future<void> close() async {
    await _events?.cancel();
    return super.close();
  }
}

const Set<String> _refreshEvents = <String>{
  'stream_saved',
  'stream_deleted',
  'profile_saved',
  'profile_deleted',
};
