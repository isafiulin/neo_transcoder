import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:neotranscoder_ui/core/api/models.dart';
import 'package:neotranscoder_ui/core/design_system/status.dart';
import 'package:neotranscoder_ui/core/state/load_status.dart';
import 'package:neotranscoder_ui/core/widgets/neo_badge.dart';
import 'package:neotranscoder_ui/core/widgets/neo_button.dart';
import 'package:neotranscoder_ui/core/widgets/neo_panel.dart';
import 'package:neotranscoder_ui/core/widgets/neo_search_field.dart';
import 'package:neotranscoder_ui/core/widgets/neo_state.dart';
import 'logs_cubit.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LogsCubit, LogsState>(
      builder: (BuildContext context, LogsState state) {
        final List<LogEntry> logs = state.filtered;
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
                      onChanged: context.read<LogsCubit>().setQuery,
                      hintText: 'Filter logs',
                    ),
                    NeoButton(
                      label: 'Refresh',
                      icon: Icons.refresh,
                      onPressed: context.read<LogsCubit>().load,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            NeoPanel(
              child: _content(state, logs),
            ),
          ],
        );
      },
    );
  }

  Widget _content(LogsState state, List<LogEntry> logs) {
    final String? error = state.error.isEmpty ? null : state.error;
    if (state.status == LoadStatus.loading ||
        state.status == LoadStatus.initial) {
      return const NeoLoadingState(label: 'Loading logs');
    }
    if (error != null) {
      return NeoErrorState(
          message: error, onRetry: context.read<LogsCubit>().load);
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
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.item});

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
            SizedBox(
                width: 120,
                child: Text(item.streamId.isEmpty ? '-' : item.streamId)),
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
