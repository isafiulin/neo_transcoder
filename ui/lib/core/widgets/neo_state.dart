import 'package:flutter/material.dart';

import 'package:neotranscoder_ui/app/theme.dart';
import 'neo_button.dart';

class NeoLoadingState extends StatelessWidget {
  const NeoLoadingState({
    this.label = 'Loading',
    super.key,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: NeoSpacing.md),
            Text(label, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}

class NeoEmptyState extends StatelessWidget {
  const NeoEmptyState({
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    super.key,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: NeoColors.muted, size: 34),
            const SizedBox(height: NeoSpacing.md),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: NeoSpacing.xs),
            Text(message, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}

class NeoErrorState extends StatelessWidget {
  const NeoErrorState({
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline, color: NeoColors.danger, size: 34),
            const SizedBox(height: NeoSpacing.md),
            Text('Could not load data',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: NeoSpacing.xs),
            Text(message, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: NeoSpacing.lg),
            NeoButton(label: 'Retry', icon: Icons.refresh, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
