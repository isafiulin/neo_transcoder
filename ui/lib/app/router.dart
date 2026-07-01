import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/api/api_client.dart';
import '../core/widgets/app_shell.dart';
import '../features/auth/login_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/logs/logs_screen.dart';
import '../features/profiles/profiles_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/streams/streams_screen.dart';

final router = GoRouter(
  initialLocation: '/',
  redirect: (BuildContext context, GoRouterState state) {
    final bool loggingIn = state.uri.path == '/login';
    if (!AuthStore.isAuthenticated && !loggingIn) {
      return '/login';
    }
    if (AuthStore.isAuthenticated && loggingIn) {
      return '/';
    }
    return null;
  },
  routes: [
    GoRoute(
      path: '/login',
      pageBuilder: (context, state) => const NoTransitionPage(
        child: LoginScreen(),
      ),
    ),
    ShellRoute(
      builder: (context, state, child) => AppShell(
        location: state.uri.path,
        child: child,
      ),
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: DashboardScreen(),
          ),
        ),
        GoRoute(
          path: '/streams',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: StreamsScreen(),
          ),
        ),
        GoRoute(
          path: '/profiles',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ProfilesScreen(),
          ),
        ),
        GoRoute(
          path: '/logs',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: LogsScreen(),
          ),
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: SettingsScreen(),
          ),
        ),
      ],
    ),
  ],
  errorBuilder: (context, state) => const Scaffold(
    body: Center(child: Text('Page not found')),
  ),
);
