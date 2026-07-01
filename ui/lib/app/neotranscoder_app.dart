import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../core/api/api_client.dart';
import '../data/repositories/transcoder_repository.dart';
import 'router.dart';
import 'session_cubit.dart';
import 'theme.dart';

class NeoTranscoderApp extends StatefulWidget {
  const NeoTranscoderApp({super.key});

  @override
  State<NeoTranscoderApp> createState() => _NeoTranscoderAppState();
}

class _NeoTranscoderAppState extends State<NeoTranscoderApp> {
  late final ApiClient _api = ApiClient();
  late final TranscoderRepository _repository = TranscoderRepository(api: _api);
  late final SessionCubit _session = SessionCubit(api: _api)..bootstrap();
  late final GoRouter router = createRouter(_session);

  @override
  void initState() {
    super.initState();
    _api.onUnauthorized = _session.requireLogin;
  }

  @override
  void dispose() {
    _session.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: <RepositoryProvider<dynamic>>[
        RepositoryProvider<TranscoderRepository>.value(value: _repository),
      ],
      child: BlocProvider<SessionCubit>.value(
        value: _session,
        child: MaterialApp.router(
          title: 'NeoTranscoder',
          debugShowCheckedModeBanner: false,
          theme: NeoTheme.light(),
          routerConfig: router,
        ),
      ),
    );
  }
}
