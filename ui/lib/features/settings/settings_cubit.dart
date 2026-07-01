import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:neotranscoder_ui/core/api/api_client.dart';
import 'package:neotranscoder_ui/core/api/models.dart';
import 'package:neotranscoder_ui/core/state/load_status.dart';
import 'package:neotranscoder_ui/data/repositories/transcoder_repository.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SettingsState extends Equatable {
  const SettingsState({
    this.status = LoadStatus.initial,
    this.users = const <UserAccount>[],
    this.frontendVersion = '',
    this.server = const ServerInfo(version: '', commit: '', date: ''),
    this.error = '',
  });

  final LoadStatus status;
  final List<UserAccount> users;
  final String frontendVersion;
  final ServerInfo server;
  final String error;

  SettingsState copyWith({
    LoadStatus? status,
    List<UserAccount>? users,
    String? frontendVersion,
    ServerInfo? server,
    String? error,
  }) {
    return SettingsState(
      status: status ?? this.status,
      users: users ?? this.users,
      frontendVersion: frontendVersion ?? this.frontendVersion,
      server: server ?? this.server,
      error: error ?? this.error,
    );
  }

  @override
  List<Object?> get props =>
      <Object?>[status, users, frontendVersion, server, error];
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
      final ServerInfo server = await _repository.health();
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      emit(state.copyWith(
        status: LoadStatus.ready,
        users: users,
        server: server,
        frontendVersion: packageInfo.version,
      ));
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
