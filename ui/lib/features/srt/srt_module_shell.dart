import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:neotranscoder_ui/app/app_routes.dart';
import 'package:neotranscoder_ui/app/theme.dart';

class SrtModuleShell extends StatelessWidget {
  const SrtModuleShell({
    required this.location,
    required this.child,
    super.key,
  });

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          spacing: NeoSpacing.lg,
          runSpacing: NeoSpacing.md,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('SRT Relay',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: NeoSpacing.xs),
                Text(
                  'Secure MPEG-TS delivery over SRT',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
            _SrtNavigation(location: location),
          ],
        ),
        const SizedBox(height: NeoSpacing.xl),
        child,
      ],
    );
  }
}

class _SrtNavigation extends StatelessWidget {
  const _SrtNavigation({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      showSelectedIcon: false,
      segments: const <ButtonSegment<String>>[
        ButtonSegment<String>(
          value: AppRoutes.srtRelays,
          label: Text('Relays'),
          icon: Icon(Icons.cell_tower_outlined, size: 18),
        ),
        ButtonSegment<String>(
          value: AppRoutes.srtClients,
          label: Text('Clients'),
          icon: Icon(Icons.key_outlined, size: 18),
        ),
        ButtonSegment<String>(
          value: AppRoutes.srtSessions,
          label: Text('Sessions'),
          icon: Icon(Icons.link_outlined, size: 18),
        ),
        ButtonSegment<String>(
          value: AppRoutes.srtAudit,
          label: Text('Audit'),
          icon: Icon(Icons.receipt_long_outlined, size: 18),
        ),
      ],
      selected: <String>{_selectedPath},
      onSelectionChanged: (Set<String> value) => context.go(value.first),
    );
  }

  String get _selectedPath {
    if (location.startsWith(AppRoutes.srtClients)) {
      return AppRoutes.srtClients;
    }
    if (location.startsWith(AppRoutes.srtSessions)) {
      return AppRoutes.srtSessions;
    }
    if (location.startsWith(AppRoutes.srtAudit)) {
      return AppRoutes.srtAudit;
    }
    return AppRoutes.srtRelays;
  }
}
