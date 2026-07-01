import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/api/api_client.dart';
import '../core/api/models.dart';

enum SessionStatus {
  checking,
  authenticated,
  unauthenticated,
}

class SessionState extends Equatable {
  const SessionState({
    required this.status,
    this.user,
    this.mustChangePassword = false,
  });

  const SessionState.checking() : this(status: SessionStatus.checking);

  const SessionState.unauthenticated() : this(status: SessionStatus.unauthenticated);

  final SessionStatus status;
  final UserAccount? user;
  final bool mustChangePassword;

  bool get isChecking => status == SessionStatus.checking;

  bool get isAuthenticated => status == SessionStatus.authenticated;

  @override
  List<Object?> get props => <Object?>[status, user, mustChangePassword];
}

class SessionCubit extends Cubit<SessionState> {
  SessionCubit({required ApiClient api})
      : _api = api,
        super(const SessionState.checking());

  final ApiClient _api;

  Future<void> bootstrap() async {
    if (!AuthStore.isAuthenticated) {
      emit(const SessionState.unauthenticated());
      return;
    }
    try {
      final UserAccount user = await _api.verify();
      emit(
        SessionState(
          status: SessionStatus.authenticated,
          user: user,
          mustChangePassword: user.mustChangePassword || AuthStore.mustChangePassword,
        ),
      );
    } on Object {
      AuthStore.clear();
      emit(const SessionState.unauthenticated());
    }
  }

  Future<AuthSession> login(String username, String password) async {
    final AuthSession session = await _api.login(username, password);
    emit(
      SessionState(
        status: SessionStatus.authenticated,
        user: session.user,
        mustChangePassword: session.mustChangePassword,
      ),
    );
    return session;
  }

  void logout() {
    AuthStore.clear();
    emit(const SessionState.unauthenticated());
  }

  void requireLogin() {
    AuthStore.clear();
    emit(const SessionState.unauthenticated());
  }
}
