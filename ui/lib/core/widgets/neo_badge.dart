import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../design_system/status.dart';

class NeoBadge extends StatelessWidget {
  const NeoBadge({
    required this.label,
    required this.tone,
    super.key,
  });

  final String label;
  final NeoStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final Color color = statusColor(tone);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        border: Border.all(color: color.withOpacity(0.28)),
        borderRadius: BorderRadius.circular(NeoRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
