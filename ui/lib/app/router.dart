import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:neotranscoder_ui/core/widgets/app_shell.dart';
import 'package:neotranscoder_ui/data/repositories/service_repository.dart';
import 'package:neotranscoder_ui/features/auth/login_screen.dart';
import 'package:neotranscoder_ui/features/settings/settings_cubit.dart';
import 'package:neotranscoder_ui/features/settings/settings_screen.dart';
import 'package:neotranscoder_ui/features/splash/splash_screen.dart';
import 'package:neotranscoder_ui/features/srt/srt_audit_screen.dart';
import 'package:neotranscoder_ui/features/srt/srt_client_editor_screen.dart';
import 'package:neotranscoder_ui/features/srt/srt_clients_screen.dart';
import 'package:neotranscoder_ui/features/srt/srt_cubit.dart';
import 'package:neotranscoder_ui/features/srt/srt_module_shell.dart';
import 'package:neotranscoder_ui/features/srt/srt_relay_editor_screen.dart';
import 'package:neotranscoder_ui/features/srt/srt_relays_screen.dart';
import 'package:neotranscoder_ui/features/srt/srt_sessions_screen.dart';
import 'app_routes.dart';
import 'session_cubit.dart';

GoRouter createRouter(SessionCubit session) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: GoRouterRefreshStream(session.stream),
    redirect: (BuildContext context, GoRouterState state) {
      final SessionState sessionState = session.state;
      final String path = state.uri.path;
      final bool onSplash = path == AppRoutes.splash;
      final bool onLogin = path == AppRoutes.login;
      final String current = state.uri.toString();
      final String from =
          state.uri.queryParameters['from'] ?? AppRoutes.dashboard;

      if (sessionState.isChecking) {
        return onSplash ? null : _withFrom(AppRoutes.splash, current);
      }
      if (!sessionState.isAuthenticated) {
        if (onLogin) {
          return null;
        }
        return _withFrom(AppRoutes.login, onSplash ? from : current);
      }
      if (sessionState.mustChangePassword && path != AppRoutes.settings) {
        return AppRoutes.settings;
      }
      if (onSplash || onLogin) {
        return _safeFrom(from);
      }
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.splash,
        pageBuilder: (BuildContext context, GoRouterState state) => _fadePage(
          state: state,
          child: const SplashScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.login,
        pageBuilder: (BuildContext context, GoRouterState state) => _fadePage(
          state: state,
          child: const LoginScreen(),
        ),
      ),
      ShellRoute(
        builder: (BuildContext context, GoRouterState state, Widget child) =>
            AppShell(
          location: state.uri.path,
          child: child,
        ),
        routes: <RouteBase>[
          GoRoute(
            path: AppRoutes.dashboard,
            redirect: (BuildContext context, GoRouterState state) =>
                AppRoutes.srtRelays,
          ),
          ShellRoute(
            builder:
                (BuildContext context, GoRouterState state, Widget child) =>
                    BlocProvider<SrtCubit>(
              create: (BuildContext context) => SrtCubit(
                repository: context.read<ServiceRepository>(),
              )
                ..load()
                ..subscribe(),
              child: SrtModuleShell(
                location: state.uri.path,
                child: child,
              ),
            ),
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.srt,
                redirect: (BuildContext context, GoRouterState state) =>
                    AppRoutes.srtRelays,
              ),
              GoRoute(
                path: AppRoutes.srtRelays,
                pageBuilder: (BuildContext context, GoRouterState state) =>
                    _slidePage(state: state, child: const SrtRelaysScreen()),
              ),
              GoRoute(
                path: AppRoutes.srtRelayNew,
                pageBuilder: (BuildContext context, GoRouterState state) =>
                    _slidePage(
                  state: state,
                  child: const SrtRelayEditorScreen(),
                ),
              ),
              GoRoute(
                path: '${AppRoutes.srtRelays}/:relayId/edit',
                pageBuilder: (BuildContext context, GoRouterState state) =>
                    _slidePage(
                  state: state,
                  child: SrtRelayEditorScreen(
                    relayId: state.pathParameters['relayId'],
                  ),
                ),
              ),
              GoRoute(
                path: AppRoutes.srtClients,
                pageBuilder: (BuildContext context, GoRouterState state) =>
                    _slidePage(state: state, child: const SrtClientsScreen()),
              ),
              GoRoute(
                path: AppRoutes.srtClientNew,
                pageBuilder: (BuildContext context, GoRouterState state) =>
                    _slidePage(
                  state: state,
                  child: const SrtClientEditorScreen(),
                ),
              ),
              GoRoute(
                path: '${AppRoutes.srtClients}/:clientId/edit',
                pageBuilder: (BuildContext context, GoRouterState state) =>
                    _slidePage(
                  state: state,
                  child: SrtClientEditorScreen(
                    clientId: state.pathParameters['clientId'],
                  ),
                ),
              ),
              GoRoute(
                path: AppRoutes.srtSessions,
                pageBuilder: (BuildContext context, GoRouterState state) =>
                    _slidePage(state: state, child: const SrtSessionsScreen()),
              ),
              GoRoute(
                path: AppRoutes.srtAudit,
                pageBuilder: (BuildContext context, GoRouterState state) =>
                    _slidePage(state: state, child: const SrtAuditScreen()),
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.settings,
            pageBuilder: (BuildContext context, GoRouterState state) =>
                _slidePage(
              state: state,
              child: BlocProvider<SettingsCubit>(
                create: (BuildContext context) => SettingsCubit(
                  repository: context.read<ServiceRepository>(),
                )..load(),
                child: const SettingsScreen(),
              ),
            ),
          ),
        ],
      ),
    ],
    errorBuilder: (BuildContext context, GoRouterState state) => const Scaffold(
      body: Center(child: Text('Page not found')),
    ),
  );
}

String _withFrom(String path, String from) {
  return Uri(path: path, queryParameters: <String, String>{'from': from})
      .toString();
}

String _safeFrom(String from) {
  final Uri uri = Uri.parse(from);
  if (!from.startsWith('/') ||
      uri.path == AppRoutes.splash ||
      uri.path == AppRoutes.login) {
    return AppRoutes.dashboard;
  }
  return from;
}

Page<void> _fadePage({
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    transitionsBuilder: (BuildContext context, Animation<double> animation,
        Animation<double> secondaryAnimation, Widget child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: child,
      );
    },
  );
}

Page<void> _slidePage({
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 240),
    reverseTransitionDuration: const Duration(milliseconds: 160),
    transitionsBuilder: (BuildContext context, Animation<double> animation,
        Animation<double> secondaryAnimation, Widget child) {
      final Animation<double> curved =
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.018, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription =
        stream.asBroadcastStream().listen((dynamic _) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
