import 'package:flutter/material.dart';

import '../../app/theme.dart';

enum NeoStatusTone {
  neutral,
  success,
  warning,
  danger,
  info,
}

Color statusColor(NeoStatusTone tone) {
  switch (tone) {
    case NeoStatusTone.success:
      return NeoColors.success;
    case NeoStatusTone.warning:
      return NeoColors.warning;
    case NeoStatusTone.danger:
      return NeoColors.danger;
    case NeoStatusTone.info:
      return NeoColors.blue;
    case NeoStatusTone.neutral:
      return NeoColors.muted;
  }
}

NeoStatusTone streamTone(String status, bool hasError) {
  if (status == 'running' && !hasError) {
    return NeoStatusTone.success;
  }
  if (status == 'restarting' || status == 'stopping') {
    return NeoStatusTone.warning;
  }
  if (status == 'error' || status == 'flapping' || hasError) {
    return NeoStatusTone.danger;
  }
  return NeoStatusTone.neutral;
}
