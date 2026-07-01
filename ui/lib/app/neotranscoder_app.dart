import 'package:flutter/material.dart';

import 'router.dart';
import 'theme.dart';

class NeoTranscoderApp extends StatelessWidget {
  const NeoTranscoderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'NeoTranscoder',
      debugShowCheckedModeBanner: false,
      theme: NeoTheme.light(),
      routerConfig: router,
    );
  }
}
