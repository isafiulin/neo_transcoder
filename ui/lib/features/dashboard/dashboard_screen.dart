import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/design_system/status.dart';
import '../../core/widgets/metric_tile.dart';
import '../../core/widgets/neo_badge.dart';
import '../../core/widgets/neo_panel.dart';
import '../../core/widgets/neo_search_field.dart';
import '../../core/widgets/neo_state.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ApiClient _api = ApiClient();
  List<StreamView> _streams = <StreamView>[];
  String _query = '';
  bool _loading = true;
  String? _error;
  StreamSubscription<ApiEvent>? _events;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _events = _api.events().listen((ApiEvent event) {
      if (event.type.startsWith('stream_')) {
        unawaited(_load());
      }
    });
  }

  @override
  void dispose() {
    unawaited(_events?.cancel());
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final List<StreamView> streams = await _api.metrics();
      if (!mounted) {
        return;
      }
      setState(() {
        _streams = streams;
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
    final List<StreamView> filtered = _streams.where(_matchesQuery).toList();
    final int running = _streams.where((StreamView item) => item.state.isRunning).length;
    final int errors = _streams.where((StreamView item) => item.state.hasError).length;
    final double cpu = _streams.fold<double>(
      0,
      (double sum, StreamView item) => sum + (item.state.process?.cpuPercent ?? 0),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Header(onSearch: (String value) => setState(() => _query = value)),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final int columns = constraints.maxWidth > 1100 ? 4 : 2;
            return GridView.count(
              crossAxisCount: columns,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 4.2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: <Widget>[
                MetricTile(label: 'Streams', value: '${_streams.length}', icon: Icons.stream_outlined),
                MetricTile(label: 'Running', value: '$running', icon: Icons.play_circle_outline),
                MetricTile(label: 'Errors', value: '$errors', icon: Icons.error_outline),
                MetricTile(label: 'FFmpeg CPU', value: '${cpu.toStringAsFixed(1)}%', icon: Icons.memory_outlined),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        NeoPanel(
          title: 'Live streams',
          child: _content(filtered),
        ),
      ],
    );
  }

  Widget _content(List<StreamView> streams) {
    final String? error = _error;
    if (_loading) {
      return const NeoLoadingState(label: 'Loading streams');
    }
    if (error != null) {
      return NeoErrorState(message: error, onRetry: _load);
    }
    if (streams.isEmpty) {
      return const NeoEmptyState(
        title: 'No streams',
        message: 'Create a stream or adjust the filter.',
      );
    }
    return _StreamGrid(streams: streams);
  }

  bool _matchesQuery(StreamView item) {
    final String value = _query.trim().toLowerCase();
    if (value.isEmpty) {
      return true;
    }
    return item.config.name.toLowerCase().contains(value) ||
        item.config.id.toLowerCase().contains(value) ||
        item.config.inputUrl.toLowerCase().contains(value) ||
        item.config.outputUrl.toLowerCase().contains(value);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onSearch, super.key});

  final ValueChanged<String> onSearch;

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
            Text('Multicast transcoding overview', style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
        NeoSearchField(onChanged: onSearch, hintText: 'Filter streams'),
      ],
    );
  }
}

class _StreamGrid extends StatelessWidget {
  const _StreamGrid({required this.streams, super.key});

  final List<StreamView> streams;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool table = constraints.maxWidth >= 860;
        if (!table) {
          return Column(
            children: streams.map((StreamView item) => _StreamCard(item: item)).toList(),
          );
        }
        return DataTable(
          headingRowHeight: 38,
          dataRowMinHeight: 44,
          dataRowMaxHeight: 52,
          columns: const <DataColumn>[
            DataColumn(label: Text('Name')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Bitrate')),
            DataColumn(label: Text('FPS')),
            DataColumn(label: Text('CPU')),
            DataColumn(label: Text('Error')),
          ],
          rows: streams.map(_row).toList(),
        );
      },
    );
  }

  DataRow _row(StreamView item) {
    final StreamState state = item.state;
    return DataRow(
      cells: <DataCell>[
        DataCell(Text(item.config.name.isEmpty ? item.config.id : item.config.name)),
        DataCell(NeoBadge(label: state.status, tone: streamTone(state.status, state.hasError))),
        DataCell(Text(state.metrics?.bitrate ?? '-')),
        DataCell(Text((state.metrics?.fps ?? 0).toStringAsFixed(1))),
        DataCell(Text('${(state.process?.cpuPercent ?? 0).toStringAsFixed(1)}%')),
        DataCell(Text(state.errorCode.isEmpty ? '-' : state.errorCode)),
      ],
    );
  }
}

class _StreamCard extends StatelessWidget {
  const _StreamCard({required this.item, super.key});

  final StreamView item;

  @override
  Widget build(BuildContext context) {
    final StreamState state = item.state;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(child: Text(item.config.name, style: Theme.of(context).textTheme.titleMedium)),
                  NeoBadge(label: state.status, tone: streamTone(state.status, state.hasError)),
                ],
              ),
              const SizedBox(height: 8),
              Text('Bitrate ${state.metrics?.bitrate ?? '-'} · CPU ${(state.process?.cpuPercent ?? 0).toStringAsFixed(1)}%'),
              if (state.errorCode.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(state.errorCode),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
