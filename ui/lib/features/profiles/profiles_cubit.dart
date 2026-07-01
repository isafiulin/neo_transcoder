import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/state/load_status.dart';
import '../../data/repositories/transcoder_repository.dart';

class ProfilesState extends Equatable {
  const ProfilesState({
    this.status = LoadStatus.initial,
    this.profiles = const <Profile>[],
    this.query = '',
    this.error = '',
  });

  final LoadStatus status;
  final List<Profile> profiles;
  final String query;
  final String error;

  List<Profile> get filtered {
    final String value = query.trim().toLowerCase();
    if (value.isEmpty) {
      return profiles;
    }
    return profiles.where((Profile profile) {
      return profile.name.toLowerCase().contains(value) ||
          profile.videoCodec.toLowerCase().contains(value) ||
          profile.audioCodec.toLowerCase().contains(value);
    }).toList();
  }

  ProfilesState copyWith({
    LoadStatus? status,
    List<Profile>? profiles,
    String? query,
    String? error,
  }) {
    return ProfilesState(
      status: status ?? this.status,
      profiles: profiles ?? this.profiles,
      query: query ?? this.query,
      error: error ?? this.error,
    );
  }

  @override
  List<Object?> get props => <Object?>[status, profiles, query, error];
}

class ProfilesCubit extends Cubit<ProfilesState> {
  ProfilesCubit({required TranscoderRepository repository})
      : _repository = repository,
        super(const ProfilesState());

  final TranscoderRepository _repository;

  Future<void> load() async {
    emit(state.copyWith(status: LoadStatus.loading, error: ''));
    try {
      final List<Profile> profiles = await _repository.profiles();
      emit(state.copyWith(status: LoadStatus.ready, profiles: profiles));
    } on Object catch (error) {
      emit(state.copyWith(status: LoadStatus.failure, error: apiErrorMessage(error)));
    }
  }

  void setQuery(String value) {
    emit(state.copyWith(query: value));
  }

  Future<void> saveProfile(Map<String, Object?> body, {String? name}) async {
    if (name == null) {
      await _repository.saveProfile(body);
    } else {
      await _repository.updateProfile(name, body);
    }
    await load();
  }

  Future<void> deleteProfile(String name) async {
    await _repository.deleteProfile(name);
    await load();
  }
}
