import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:neotranscoder_ui/core/api/api_client.dart';
import 'package:neotranscoder_ui/core/api/models.dart';
import 'package:neotranscoder_ui/core/state/load_status.dart';
import 'package:neotranscoder_ui/data/repositories/transcoder_repository.dart';

class SettingsState extends Equatable {
  const SettingsState({
    this.status = LoadStatus.initial,
    this.users = const <UserAccount>[],
    this.error = '',
  });

  final LoadStatus status;
  final List<UserAccount> users;
  final String error;

  SettingsState copyWith({
    LoadStatus? status,
    List<UserAccount>? users,
    String? error,
  }) {
    return SettingsState(
      status: status ?? this.status,
      users: users ?? this.users,
      error: error ?? this.error,
    );
  }

  @override
  List<Object?> get props => <Object?>[status, users, error];
}

class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit({required TranscoderRepository repository})
      : _repository = repository,
        super(const SettingsState());

  final TranscoderRepository _repository;

  Future<void> load() async {
    emit(state.copyWith(status: LoadStatus.loading, error: ''));
    try {
      final List<UserAccount> users = await _repository.users();
      emit(state.copyWith(status: LoadStatus.ready, users: users));
    } on Object catch (error) {
      emit(state.copyWith(
          status: LoadStatus.failure, error: apiErrorMessage(error)));
    }
  }

  Future<void> createUser(String username, String password) async {
    await _repository.createUser(username, password);
    await load();
  }

  Future<void> changeUserPassword(String username, String password) async {
    await _repository.changeUserPassword(username, password);
    await load();
  }

  Future<void> deleteUser(String username) async {
    await _repository.deleteUser(username);
    await load();
  }

  Future<void> changePassword(String currentPassword, String newPassword) {
    return _repository.changePassword(currentPassword, newPassword);
  }
}
