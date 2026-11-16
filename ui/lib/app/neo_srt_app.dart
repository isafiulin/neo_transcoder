import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:neotranscoder_ui/core/api/api_client.dart';
import 'package:neotranscoder_ui/data/repositories/service_repository.dart';
import 'router.dart';
import 'session_cubit.dart';
import 'theme.dart';

class NeoSrtApp extends StatefulWidget {
  const NeoSrtApp({super.key});

  @override
  State<NeoSrtApp> createState() => _NeoSrtAppState();
}

class _NeoSrtAppState extends State<NeoSrtApp> {
  late final ApiClient _api = ApiClient();
  late final ServiceRepository _repository = ServiceRepository(api: _api);
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
        RepositoryProvider<ServiceRepository>.value(value: _repository),
      ],
      child: BlocProvider<SessionCubit>.value(
        value: _session,
        child: MaterialApp.router(
          title: 'NeoSRT',
          debugShowCheckedModeBanner: false,
          theme: NeoTheme.light(),
          routerConfig: router,
        ),
      ),
    );
  }
}
