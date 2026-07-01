import 'package:flutter/material.dart';

import '../../core/widgets/neo_panel.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Settings', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 18),
        NeoPanel(
          title: 'Runtime',
          child: Wrap(
            spacing: 18,
            runSpacing: 12,
            children: const <Widget>[
              _SettingValue(label: 'Config', value: '/etc/neotranscoder/config.json'),
              _SettingValue(label: 'State', value: '/var/lib/neotranscoder/state.json'),
              _SettingValue(label: 'Logs', value: 'journald + in-memory recent logs'),
              _SettingValue(label: 'Service', value: 'neotranscoder.service'),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingValue extends StatelessWidget {
  const _SettingValue({
    required this.label,
    required this.value,
    super.key,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          SelectableText(value),
        ],
      ),
    );
  }
}
