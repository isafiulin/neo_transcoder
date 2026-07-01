import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_routes.dart';
import '../../app/session_cubit.dart';
import '../../app/theme.dart';
import '../../core/api/api_client.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _username = TextEditingController(text: 'admin');
  final TextEditingController _password = TextEditingController();
  bool _loading = false;
  String _error = '';

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 420,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Image.asset(
                    'assets/brand/neotelecom-logo.png',
                    height: 52,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 24),
                  Text('NeoTranscoder', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text('Sign in to management console', style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _username,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  if (_error.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(_error, style: const TextStyle(color: NeoColors.danger)),
                  ],
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    onPressed: _loading ? null : _submit,
                    icon: const Icon(Icons.login),
                    label: Text(_loading ? 'Signing in' : 'Sign in'),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Default first login is admin / 123456. The password must be changed after first sign in.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: NeoColors.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final String username = _username.text.trim();
    final String password = _password.text;
    if (username.isEmpty || password.isEmpty || _loading) {
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final AuthSession session = await context.read<SessionCubit>().login(username, password);
      if (!mounted) {
        return;
      }
      final String from = GoRouterState.of(context).uri.queryParameters['from'] ?? AppRoutes.dashboard;
      context.go(session.mustChangePassword ? AppRoutes.settings : _safeFrom(from));
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = apiErrorMessage(error);
      });
    }
  }

  String _safeFrom(String from) {
    final Uri uri = Uri.parse(from);
    if (!from.startsWith('/') || uri.path == AppRoutes.splash || uri.path == AppRoutes.login) {
      return AppRoutes.dashboard;
    }
    return from;
  }
}
