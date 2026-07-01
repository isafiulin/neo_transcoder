import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api/models.dart';
import '../../core/design_system/status.dart';
import '../../core/state/load_status.dart';
import '../../core/widgets/metric_tile.dart';
import '../../core/widgets/neo_badge.dart';
import '../../core/widgets/neo_panel.dart';
import '../../core/widgets/neo_search_field.dart';
import '../../core/widgets/neo_state.dart';
import 'dashboard_cubit.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DashboardCubit, DashboardState>(
      builder: (BuildContext context, DashboardState state) {
        final List<StreamView> filtered = state.filtered;
        final int running = state.streams.where((StreamView item) => item.state.isRunning).length;
        final int errors = state.streams.where((StreamView item) => item.state.hasError).length;
        final double cpu = state.streams.fold<double>(
          0,
          (double sum, StreamView item) => sum + (item.state.process?.cpuPercent ?? 0),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _Header(
              onSearch: context.read<DashboardCubit>().setQuery,
            ),
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
                    MetricTile(label: 'Streams', value: '${state.streams.length}', icon: Icons.stream_outlined),
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
              child: _DashboardContent(state: state, streams: filtered),
            ),
          ],
        );
      },
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({
    required this.state,
    required this.streams,
    super.key,
  });

  final DashboardState state;
  final List<StreamView> streams;

  @override
  Widget build(BuildContext context) {
    if (state.status == LoadStatus.loading || state.status == LoadStatus.initial) {
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
    return _StreamGrid(streams: streams);
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
