import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/api/api_client.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _token = TextEditingController();

  @override
  void dispose() {
    _token.dispose();
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
                  Text('Enter management token', style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _token,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Bearer token',
                      prefixIcon: Icon(Icons.key_outlined),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.login),
                    label: const Text('Continue'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _continueWithoutToken,
                    child: const Text('Continue without token'),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Token is stored only in this browser.',
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

  void _submit() {
    final String value = _token.text.trim();
    if (value.isEmpty) {
      return;
    }
    AuthStore.save(value);
    context.go('/');
  }

  void _continueWithoutToken() {
    AuthStore.continueWithoutToken();
    context.go('/');
  }
}
