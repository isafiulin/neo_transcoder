import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:neotranscoder_ui/app/app_routes.dart';
import 'package:neotranscoder_ui/core/api/api_error.dart';
import 'package:neotranscoder_ui/core/api/models.dart';
import 'package:neotranscoder_ui/core/api/srt_models.dart';
import 'package:neotranscoder_ui/core/design_system/status.dart';
import 'package:neotranscoder_ui/core/state/load_status.dart';
import 'package:neotranscoder_ui/core/widgets/metric_tile.dart';
import 'package:neotranscoder_ui/core/widgets/neo_badge.dart';
import 'package:neotranscoder_ui/core/widgets/neo_panel.dart';
import 'package:neotranscoder_ui/core/widgets/neo_search_field.dart';
import 'package:neotranscoder_ui/core/widgets/neo_state.dart';
import 'package:neotranscoder_ui/features/srt/srt_format.dart';
import 'dashboard_cubit.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _status = 'all';
  String _sort = 'name';
  bool _descending = false;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DashboardCubit, DashboardState>(
      builder: (BuildContext context, DashboardState state) {
        final List<StreamView> filtered = _sorted(_filtered(state.filtered));
        final List<SrtRelayView> srtRelays =
            _sortedSrt(_filteredSrt(state.filteredSrtRelays));
        final int running = state.streams
            .where((StreamView item) => item.state.isRunning)
            .length;
        final int errors = state.streams
            .where((StreamView item) => item.state.hasError)
            .length;
        final int srtErrors = state.srtRelays
            .where((SrtRelayView item) => item.state.hasError)
            .length;
        final int activeSrtClients = state.activeSrtSessions.length;
        final int stalledSrtInputs = state.srtRelays
            .where((SrtRelayView item) => item.state.status == 'degraded')
            .length;
        final int srtOutputBitrate = state.srtRelays.fold<int>(
          0,
          (int sum, SrtRelayView item) => sum + item.state.outputBitrateBps,
        );
        final double cpu = state.streams.fold<double>(
          0,
          (double sum, StreamView item) =>
              sum + (item.state.process?.cpuPercent ?? 0),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _Header(
              onSearch: context.read<DashboardCubit>().setQuery,
              status: _status,
              sort: _sort,
              descending: _descending,
              onStatusChanged: (String value) =>
                  setState(() => _status = value),
              onSortChanged: (String value) => setState(() => _sort = value),
              onDirectionChanged: () =>
                  setState(() => _descending = !_descending),
            ),
            const SizedBox(height: 18),
            _ServerPanel(server: state.server),
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final int columns = constraints.maxWidth > 1100
                    ? 4
                    : (constraints.maxWidth > 620 ? 2 : 1);
                return GridView.count(
                  crossAxisCount: columns,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 4.2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: <Widget>[
                    MetricTile(
                        label: 'Encoding streams',
                        value: '${state.streams.length}',
                        icon: Icons.stream_outlined),
                    MetricTile(
                        label: 'SRT relays',
                        value: '${state.srtRelays.length}',
                        icon: Icons.cell_tower_outlined),
                    MetricTile(
                        label: 'Running encoders',
                        value: '$running',
                        icon: Icons.play_circle_outline),
                    MetricTile(
                        label: 'FFmpeg CPU',
                        value: '${cpu.toStringAsFixed(1)}%',
                        icon: Icons.memory_outlined),
                    MetricTile(
                        label: 'SRT sessions',
                        value: '$activeSrtClients',
                        icon: Icons.headset_outlined),
                    MetricTile(
                        label: 'Errors',
                        value: '${errors + srtErrors}',
                        icon: Icons.error_outline),
                    MetricTile(
                        label: 'Stalled inputs',
                        value: '$stalledSrtInputs',
                        icon:
                            Icons.signal_cellular_connected_no_internet_0_bar),
                    MetricTile(
                      label: 'SRT output',
                      value: formatBitrate(srtOutputBitrate),
                      icon: Icons.upload_outlined,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            NeoPanel(
              title: 'Encoding streams',
              child: _DashboardContent(
                state: state,
                streams: filtered,
                onAction: _runAction,
              ),
            ),
            const SizedBox(height: 18),
            NeoPanel(
              title: 'SRT relays',
              child: _SrtDashboardContent(
                state: state,
                relays: srtRelays,
                sessions: state.activeSrtSessions,
                onAction: _runSrtAction,
              ),
            ),
          ],
        );
      },
    );
  }

  List<StreamView> _filtered(List<StreamView> streams) {
    if (_status == 'all') {
      return streams;
    }
    if (_status == 'error') {
      return streams.where((StreamView item) => item.state.hasError).toList();
    }
    return streams
        .where((StreamView item) => item.state.status == _status)
        .toList();
  }

  List<StreamView> _sorted(List<StreamView> streams) {
    final List<StreamView> out = streams.toList();
    out.sort((StreamView a, StreamView b) {
      final int result = switch (_sort) {
        'bitrate' => _bitrate(a).compareTo(_bitrate(b)),
        'cpu' => (a.state.process?.cpuPercent ?? 0)
            .compareTo(b.state.process?.cpuPercent ?? 0),
        'memory' => (a.state.process?.memoryBytes ?? 0)
            .compareTo(b.state.process?.memoryBytes ?? 0),
        'status' => a.state.status.compareTo(b.state.status),
        _ => _label(a).compareTo(_label(b)),
      };
      return _descending ? -result : result;
    });
    return out;
  }

  List<SrtRelayView> _filteredSrt(List<SrtRelayView> relays) {
    if (_status == 'all') {
      return relays;
    }
    if (_status == 'error') {
      return relays.where((SrtRelayView item) => item.state.hasError).toList();
    }
    return relays
        .where((SrtRelayView item) => item.state.status == _status)
        .toList();
  }

  List<SrtRelayView> _sortedSrt(List<SrtRelayView> relays) {
    final List<SrtRelayView> out = relays.toList();
    out.sort((SrtRelayView a, SrtRelayView b) {
      final int result = switch (_sort) {
        'bitrate' =>
          a.state.outputBitrateBps.compareTo(b.state.outputBitrateBps),
        'status' => a.state.status.compareTo(b.state.status),
        _ => _srtLabel(a).compareTo(_srtLabel(b)),
      };
      return _descending ? -result : result;
    });
    return out;
  }

  Future<void> _runAction(String action, StreamView stream) async {
    final DashboardCubit cubit = context.read<DashboardCubit>();
    try {
      switch (action) {
        case 'start':
          await cubit.startStream(stream.config.id);
          return;
        case 'stop':
          await cubit.stopStream(stream.config.id);
          return;
        case 'restart':
          await cubit.restartStream(stream.config.id);
          return;
      }
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(error))),
      );
    }
  }

  Future<void> _runSrtAction(String action, SrtRelayView relay) async {
    final DashboardCubit cubit = context.read<DashboardCubit>();
    try {
      switch (action) {
        case 'start':
          await cubit.startSrtRelay(relay.config.id);
          return;
        case 'stop':
          await cubit.stopSrtRelay(relay.config.id);
          return;
        case 'restart':
          await cubit.restartSrtRelay(relay.config.id);
          return;
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiErrorMessage(error))),
        );
      }
    }
  }
}

class _ServerPanel extends StatelessWidget {
  const _ServerPanel({required this.server});

  final ServerStats server;

  @override
  Widget build(BuildContext context) {
    if (!server.supported) {
      return NeoPanel(
        title: 'Server',
        child: Text(
          'Server resource metrics are not available on this platform.',
          style: Theme.of(context).textTheme.labelMedium,
        ),
      );
    }
    final TextStyle? label = Theme.of(context).textTheme.labelMedium;
    final TextStyle? value = Theme.of(context).textTheme.titleSmall;
    return NeoPanel(
      title: 'Server',
      child: Wrap(
        spacing: 24,
        runSpacing: 16,
        children: <Widget>[
          _StatColumn(
            label: 'CPU usage',
            value: '${server.cpuPercent.toStringAsFixed(1)}%',
            labelStyle: label,
            valueStyle: value,
          ),
          _StatColumn(
            label: 'Load average',
            value: '${server.loadAvg1.toStringAsFixed(2)}, '
                '${server.loadAvg5.toStringAsFixed(2)}, '
                '${server.loadAvg15.toStringAsFixed(2)}',
            labelStyle: label,
            valueStyle: value,
          ),
          _StatColumn(
            label: 'CPU cores',
            value: '${server.cpuCores}',
            labelStyle: label,
            valueStyle: value,
          ),
          _StatColumn(
            label: 'System uptime',
            value: _formatDuration(server.systemUptimeSeconds),
            labelStyle: label,
            valueStyle: value,
          ),
          _StatColumn(
            label: 'App uptime',
            value: _formatDuration(server.appUptimeSeconds),
            labelStyle: label,
            valueStyle: value,
          ),
          SizedBox(
            width: 220,
            child: _UsageBar(
              label: 'Memory',
              used: server.memoryUsedBytes,
              total: server.memoryTotalBytes,
              labelStyle: label,
            ),
          ),
          SizedBox(
            width: 220,
            child: _UsageBar(
              label: 'Disk',
              used: server.diskUsedBytes,
              total: server.diskTotalBytes,
              labelStyle: label,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({
    required this.label,
    required this.value,
    required this.labelStyle,
    required this.valueStyle,
  });

  final String label;
  final String value;
  final TextStyle? labelStyle;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: labelStyle),
        const SizedBox(height: 4),
        Text(value, style: valueStyle),
      ],
    );
  }
}

class _UsageBar extends StatelessWidget {
  const _UsageBar({
    required this.label,
    required this.used,
    required this.total,
    required this.labelStyle,
  });

  final String label;
  final int used;
  final int total;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    final double fraction = total <= 0 ? 0 : (used / total).clamp(0, 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(label, style: labelStyle),
            Text('${_bytes(used)} / ${_bytes(total)}', style: labelStyle),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: fraction, minHeight: 6),
        ),
      ],
    );
  }
}

String _formatDuration(int totalSeconds) {
  final int days = totalSeconds ~/ 86400;
  final int hours = (totalSeconds % 86400) ~/ 3600;
  final int minutes = (totalSeconds % 3600) ~/ 60;
  final int seconds = totalSeconds % 60;
  final StringBuffer buffer = StringBuffer();
  if (days > 0) {
    buffer.write('${days}d ');
  }
  buffer.write('${hours}h ${minutes}m ${seconds}s');
  return buffer.toString();
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({
    required this.state,
    required this.streams,
    required this.onAction,
  });

  final DashboardState state;
  final List<StreamView> streams;
  final StreamActionCallback onAction;

  @override
  Widget build(BuildContext context) {
    if (state.status == LoadStatus.loading ||
        state.status == LoadStatus.initial) {
      return const NeoLoadingState(label: 'Loading streams');
    }
    if (state.status == LoadStatus.failure) {
      return NeoErrorState(
        message: state.error,
        onRetry: context.read<DashboardCubit>().load,
      );
    }
    if (streams.isEmpty) {
      return const NeoEmptyState(
        title: 'No streams',
        message: 'Create a stream or adjust the filter.',
      );
    }
    return _StreamGrid(streams: streams, onAction: onAction);
  }
}

typedef SrtRelayActionCallback = Future<void> Function(
    String action, SrtRelayView relay);

class _SrtDashboardContent extends StatelessWidget {
  const _SrtDashboardContent({
    required this.state,
    required this.relays,
    required this.sessions,
    required this.onAction,
  });

  final DashboardState state;
  final List<SrtRelayView> relays;
  final List<SrtSession> sessions;
  final SrtRelayActionCallback onAction;

  @override
  Widget build(BuildContext context) {
    if (state.status == LoadStatus.loading ||
        state.status == LoadStatus.initial) {
      return const NeoLoadingState(label: 'Loading SRT relays');
    }
    if (relays.isEmpty) {
      return const NeoEmptyState(
        title: 'No SRT relays',
        message: 'Create an SRT relay or adjust the dashboard filter.',
        icon: Icons.cell_tower_outlined,
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: relays.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 390,
        mainAxisExtent: 198,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemBuilder: (BuildContext context, int index) {
        final SrtRelayView relay = relays[index];
        return _SrtRelayCard(
          relay: relay,
          sessions: sessions
              .where((SrtSession session) =>
                  session.relayId == relay.config.id && session.isActive)
              .toList(),
          onAction: onAction,
        );
      },
    );
  }
}

class _SrtRelayCard extends StatelessWidget {
  const _SrtRelayCard({
    required this.relay,
    required this.sessions,
    required this.onAction,
  });

  final SrtRelayView relay;
  final List<SrtSession> sessions;
  final SrtRelayActionCallback onAction;

  @override
  Widget build(BuildContext context) {
    final SrtRelayState state = relay.state;
    final Color border = state.hasError
        ? Theme.of(context).colorScheme.error.withValues(alpha: .42)
        : Theme.of(context).dividerColor;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: state.hasError
            ? Theme.of(context).colorScheme.error.withValues(alpha: .04)
            : null,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    _srtLabel(relay),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(width: 8),
                NeoBadge(
                  label: state.status,
                  tone: _srtTone(state.status),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: <Widget>[
                _MetricChip(
                  label: 'in',
                  value: formatBitrate(state.inputBitrateBps),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                _MetricChip(
                  label: 'out',
                  value: formatBitrate(state.outputBitrateBps),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                _MetricChip(
                  label: 'clients',
                  value: '${state.activeClients}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                _MetricChip(
                  label: 'cc errors',
                  value: '${state.continuityErrors}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _sessionSecurity(sessions),
              style: Theme.of(context).textTheme.labelSmall,
            ),
            if (state.lastError.isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                state.lastError,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const Spacer(),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    _srtEndpoint(relay.config),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'View SRT audit',
                  onPressed: () => context.go(
                    '${AppRoutes.srtAudit}?relay='
                    '${Uri.encodeQueryComponent(relay.config.id)}',
                  ),
                  icon: const Icon(Icons.receipt_long_outlined),
                ),
                _SrtRelayActions(relay: relay, onAction: onAction),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SrtRelayActions extends StatelessWidget {
  const _SrtRelayActions({required this.relay, required this.onAction});

  final SrtRelayView relay;
  final SrtRelayActionCallback onAction;

  @override
  Widget build(BuildContext context) {
    final bool running = relay.state.isRunning;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          tooltip: 'Start SRT relay',
          onPressed: running ? null : () => onAction('start', relay),
          icon: const Icon(Icons.play_arrow),
        ),
        IconButton(
          tooltip: 'Stop SRT relay',
          onPressed: running ? () => onAction('stop', relay) : null,
          icon: const Icon(Icons.stop),
        ),
        IconButton(
          tooltip: 'Restart SRT relay',
          onPressed: () => onAction('restart', relay),
          icon: const Icon(Icons.restart_alt),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.onSearch,
    required this.status,
    required this.sort,
    required this.descending,
    required this.onStatusChanged,
    required this.onSortChanged,
    required this.onDirectionChanged,
  });

  final ValueChanged<String> onSearch;
  final String status;
  final String sort;
  final bool descending;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onSortChanged;
  final VoidCallback onDirectionChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Dashboard', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Transcoding and SRT delivery overview',
                style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            SizedBox(
                width: 240,
                child: NeoSearchField(
                    onChanged: onSearch, hintText: 'Filter streams')),
            DropdownButton<String>(
              value: status,
              onChanged: (String? value) => onStatusChanged(value ?? 'all'),
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(
                    value: 'all', child: Text('All statuses')),
                DropdownMenuItem<String>(
                    value: 'running', child: Text('Running')),
                DropdownMenuItem<String>(
                    value: 'stopped', child: Text('Stopped')),
                DropdownMenuItem<String>(
                    value: 'flapping', child: Text('Flapping')),
                DropdownMenuItem<String>(value: 'error', child: Text('Errors')),
              ],
            ),
            DropdownButton<String>(
              value: sort,
              onChanged: (String? value) => onSortChanged(value ?? 'name'),
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(value: 'name', child: Text('Name')),
                DropdownMenuItem<String>(
                    value: 'status', child: Text('Status')),
                DropdownMenuItem<String>(
                    value: 'bitrate', child: Text('Bitrate')),
                DropdownMenuItem<String>(value: 'cpu', child: Text('CPU')),
                DropdownMenuItem<String>(
                    value: 'memory', child: Text('Memory')),
              ],
            ),
            IconButton(
              tooltip: descending ? 'Descending' : 'Ascending',
              onPressed: onDirectionChanged,
              icon: Icon(descending ? Icons.south : Icons.north),
            ),
          ],
        ),
      ],
    );
  }
}

typedef StreamActionCallback = Future<void> Function(
    String action, StreamView stream);

class _StreamGrid extends StatelessWidget {
  const _StreamGrid({
    required this.streams,
    required this.onAction,
  });

  final List<StreamView> streams;
  final StreamActionCallback onAction;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: streams.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 340,
        mainAxisExtent: 154,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemBuilder: (BuildContext context, int index) => _StreamCard(
        item: streams[index],
        onAction: onAction,
      ),
    );
  }
}

class _StreamCard extends StatelessWidget {
  const _StreamCard({
    required this.item,
    required this.onAction,
  });

  final StreamView item;
  final StreamActionCallback onAction;

  @override
  Widget build(BuildContext context) {
    final StreamState state = item.state;
    final Color border = state.hasError
        ? Colors.red.withValues(alpha: 0.42)
        : Theme.of(context).dividerColor;
    final TextStyle? metricStyle = Theme.of(context).textTheme.bodySmall;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: state.hasError ? Colors.red.withValues(alpha: 0.04) : null,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    _label(item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(width: 8),
                NeoBadge(
                    label: state.status,
                    tone: streamTone(state.status, state.hasError)),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: <Widget>[
                _MetricChip(
                    label: 'bitrate',
                    value: state.metrics?.bitrate ?? '-',
                    style: metricStyle),
                _MetricChip(
                    label: 'fps',
                    value: (state.metrics?.fps ?? 0).toStringAsFixed(1),
                    style: metricStyle),
                _MetricChip(
                  label: 'cpu',
                  value:
                      '${(state.process?.cpuPercent ?? 0).toStringAsFixed(1)}%',
                  style: metricStyle,
                ),
                _MetricChip(
                    label: 'ram',
                    value: _bytes(state.process?.memoryBytes ?? 0),
                    style: metricStyle),
              ],
            ),
            const Spacer(),
            if (state.errorCode.isNotEmpty)
              Text(
                state.errorCode,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    item.config.profileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                _StreamActions(item: item, onAction: onAction),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StreamActions extends StatelessWidget {
  const _StreamActions({
    required this.item,
    required this.onAction,
  });

  final StreamView item;
  final StreamActionCallback onAction;

  @override
  Widget build(BuildContext context) {
    final bool running = item.state.isRunning;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          tooltip: 'Start',
          onPressed: running ? null : () => onAction('start', item),
          icon: const Icon(Icons.play_arrow),
        ),
        IconButton(
          tooltip: 'Stop',
          onPressed: running ? () => onAction('stop', item) : null,
          icon: const Icon(Icons.stop),
        ),
        IconButton(
          tooltip: 'Restart',
          onPressed: () => onAction('restart', item),
          icon: const Icon(Icons.restart_alt),
        ),
      ],
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
    required this.style,
  });

  final String label;
  final String value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Text('$label $value', style: style);
  }
}

String _label(StreamView item) =>
    item.config.name.isEmpty ? item.config.id : item.config.name;

String _srtLabel(SrtRelayView item) =>
    item.config.name.isEmpty ? item.config.id : item.config.name;

String _srtEndpoint(SrtRelay relay) => relay.direction == 'publish'
    ? '→ ${relay.destinationAddress}:${relay.destinationPort}/udp'
    : '← ${relay.bindAddress}:${relay.port}/udp';

NeoStatusTone _srtTone(String status) => switch (status) {
      'running' => NeoStatusTone.success,
      'starting' || 'restarting' || 'degraded' => NeoStatusTone.warning,
      'error' || 'flapping' => NeoStatusTone.danger,
      _ => NeoStatusTone.neutral,
    };

String _sessionSecurity(List<SrtSession> sessions) {
  if (sessions.isEmpty) {
    return 'No active listeners';
  }
  final int encrypted =
      sessions.where((SrtSession session) => session.encrypted).length;
  if (encrypted == sessions.length) {
    return 'AES-256 · ${sessions.length} active';
  }
  if (encrypted == 0) {
    return 'No encryption · ${sessions.length} active';
  }
  return 'Mixed security · ${sessions.length} active';
}

double _bitrate(StreamView item) {
  final String value = item.state.metrics?.bitrate ?? '';
  final RegExpMatch? match = RegExp(r'([0-9.]+)').firstMatch(value);
  if (match == null) {
    return 0;
  }
  final double number = double.tryParse(match.group(1) ?? '') ?? 0;
  final String lower = value.toLowerCase();
  if (lower.contains('mb')) {
    return number * 1000;
  }
  return number;
}

String _bytes(int value) {
  if (value <= 0) {
    return '-';
  }
  if (value >= 1024 * 1024 * 1024) {
    return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
}
