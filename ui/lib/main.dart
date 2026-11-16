import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'app/neo_srt_app.dart';

void main() {
  usePathUrlStrategy();
  runApp(const NeoSrtApp());
}
