import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/design_system/status.dart';
import '../../core/widgets/neo_badge.dart';
import '../../core/widgets/neo_button.dart';
import '../../core/widgets/neo_panel.dart';
import '../../core/widgets/neo_search_field.dart';
import '../../core/widgets/neo_state.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  final ApiClient _api = ApiClient();
  List<LogEntry> _logs = <LogEntry>[];
  String _query = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final List<LogEntry> logs = await _api.logs();
      if (!mounted) {
        return;
      }
      setState(() {
        _logs = logs;
        _loading = false;
        _error = null;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = apiErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<LogEntry> logs = _logs.where(_matchesQuery).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text('Logs', style: Theme.of(context).textTheme.titleLarge),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                NeoSearchField(
                  onChanged: (String value) => setState(() => _query = value),
                  hintText: 'Filter logs',
                ),
                NeoButton(label: 'Refresh', icon: Icons.refresh, onPressed: _load),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),
        NeoPanel(
          child: _content(logs),
        ),
      ],
    );
  }

  Widget _content(List<LogEntry> logs) {
    final String? error = _error;
    if (_loading) {
      return const NeoLoadingState(label: 'Loading logs');
    }
    if (error != null) {
      return NeoErrorState(message: error, onRetry: _load);
    }
    if (logs.isEmpty) {
      return const NeoEmptyState(
        title: 'No logs',
        message: 'Recent FFmpeg logs will appear here.',
      );
    }
    return Column(
      children: logs.map((LogEntry item) => _LogRow(item: item)).toList(),
    );
  }

  bool _matchesQuery(LogEntry log) {
    final String value = _query.trim().toLowerCase();
    if (value.isEmpty) {
      return true;
    }
    return log.streamId.toLowerCase().contains(value) ||
        log.message.toLowerCase().contains(value) ||
        log.code.toLowerCase().contains(value);
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.item, super.key});

  final LogEntry item;

  @override
  Widget build(BuildContext context) {
    final NeoStatusTone tone = item.level == 'error'
        ? NeoStatusTone.danger
        : item.level == 'warn'
            ? NeoStatusTone.warning
            : NeoStatusTone.neutral;
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFDDE6EF))),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(width: 170, child: Text(item.time)),
            SizedBox(width: 120, child: Text(item.streamId.isEmpty ? '-' : item.streamId)),
            SizedBox(width: 96, child: NeoBadge(label: item.level, tone: tone)),
            if (item.code.isNotEmpty)
              SizedBox(width: 150, child: Text(item.code))
            else
              const SizedBox(width: 150, child: Text('-')),
            Expanded(child: Text(item.message)),
          ],
        ),
      ),
    );
  }
}
