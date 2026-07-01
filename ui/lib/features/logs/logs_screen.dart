import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:neotranscoder_ui/core/api/models.dart';
import 'package:neotranscoder_ui/core/design_system/status.dart';
import 'package:neotranscoder_ui/core/state/load_status.dart';
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
                    DropdownButton<String>(
                      value: state.streamId,
                      onChanged: (String? value) =>
                          context.read<LogsCubit>().setStreamId(value ?? ''),
                      items: <DropdownMenuItem<String>>[
                        const DropdownMenuItem<String>(
                            value: '', child: Text('All streams')),
                        ...state.streams.map(
                          (StreamView stream) => DropdownMenuItem<String>(
                            value: stream.config.id,
                            child: Text(stream.config.name),
                          ),
                        ),
                      ],
                    ),
                    NeoButton(
                      label: 'Refresh',
                      icon: Icons.refresh,
                      onPressed: context.read<LogsCubit>().load,
                    ),
                    NeoButton(
                      label: 'Clear log',
                      icon: Icons.delete_sweep_outlined,
                      onPressed: () => _confirmClear(context),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            NeoPanel(
              // ponytail: SelectionArea makes the whole log journal
              // copy/select-able in one shot instead of wrapping every Text
              // in the row with SelectableText.
              child: SelectionArea(child: _content(state, logs)),
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
    final bool showStream = state.streamId.isEmpty;
    return Column(
      children: logs
          .map((LogEntry item) => _LogRow(item: item, showStream: showStream))
          .toList(),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final LogsCubit cubit = context.read<LogsCubit>();
    final String streamId = cubit.state.streamId;
    final String target = streamId.isEmpty ? 'all streams' : streamId;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Clear log'),
        content: Text('Delete stored log entries for $target?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await cubit.clear();
    }
  }
}

String _formatTime(String iso) {
  final DateTime? parsed = DateTime.tryParse(iso);
  if (parsed == null) {
    return iso;
  }
  final DateTime local = parsed.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  String three(int value) => value.toString().padLeft(3, '0');
  return '${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}.${three(local.millisecond)}';
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.item, required this.showStream});

  final LogEntry item;
  final bool showStream;

  @override
  Widget build(BuildContext context) {
    final bool flagged = item.level == 'error' || item.level == 'warn';
    final Color accent = statusColor(
      item.level == 'error' ? NeoStatusTone.danger : NeoStatusTone.warning,
    );
    // Fixed-width boxes (not a monospace font, which Flutter Web doesn't
    // reliably render as an actual fixed-pitch font) keep every row's
    // message starting at the same x position regardless of how long the
    // timestamp/stream-id text happens to be.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(
              _formatTime(item.time),
              textAlign: TextAlign.left,
              style: TextStyle(
                  color: statusColor(NeoStatusTone.neutral), fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ),
          if (showStream)
            SizedBox(
              width: 80,
              child: Text(
                item.streamId.isEmpty ? '-' : item.streamId,
                textAlign: TextAlign.left,
                style: TextStyle(
                    color: statusColor(NeoStatusTone.neutral), fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 13),
                children: <InlineSpan>[
                  TextSpan(
                    text: item.message,
                    style: TextStyle(
                      color: flagged ? accent : null,
                      fontWeight: flagged ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  if (item.code.isNotEmpty)
                    TextSpan(
                      text: '  (${item.code})',
                      style: TextStyle(color: accent.withValues(alpha: 0.75)),
                    ),
                ],
              ),
              textAlign: TextAlign.left,
            ),
          ),
        ],
      ),
    );
  }
}
