import 'package:flutter/material.dart';

import 'package:neotranscoder_ui/app/theme.dart';

class NeoPanel extends StatelessWidget {
  const NeoPanel({
    required this.child,
    this.title,
    this.trailing,
    super.key,
  });

  final String? title;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final String? title = this.title;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(NeoSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (title != null || trailing != null) ...<Widget>[
              Row(
                children: <Widget>[
                  if (title != null)
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    )
                  else
                    const Spacer(),
                  if (trailing != null) trailing!,
                ],
              ),
              const SizedBox(height: NeoSpacing.lg),
            ],
            child,
          ],
        ),
      ),
    );
  }
}
