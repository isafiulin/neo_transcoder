import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:neotranscoder_ui/app/app_routes.dart';
import 'package:neotranscoder_ui/app/theme.dart';
import 'package:neotranscoder_ui/core/api/srt_models.dart';
import 'package:neotranscoder_ui/core/design_system/status.dart';
import 'package:neotranscoder_ui/core/state/load_status.dart';
import 'package:neotranscoder_ui/core/widgets/neo_badge.dart';
import 'package:neotranscoder_ui/core/widgets/neo_button.dart';
import 'package:neotranscoder_ui/core/widgets/neo_panel.dart';
import 'package:neotranscoder_ui/core/widgets/neo_search_field.dart';
import 'package:neotranscoder_ui/core/widgets/neo_state.dart';
import 'package:neotranscoder_ui/features/srt/srt_cubit.dart';
import 'package:neotranscoder_ui/features/srt/srt_format.dart';

class SrtRelaysScreen extends StatefulWidget {
  const SrtRelaysScreen({super.key});

  @override
  State<SrtRelaysScreen> createState() => _SrtRelaysScreenState();
}

class _SrtRelaysScreenState extends State<SrtRelaysScreen> {
  String _query = '';
  String _status = 'all';

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SrtCubit, SrtState>(
      listenWhen: (SrtState previous, SrtState current) =>
          previous.error != current.error && current.error.isNotEmpty,
      listener: (BuildContext context, SrtState state) =>
          _showError(context, state.error),
      builder: (BuildContext context, SrtState state) {
        final List<SrtRelayView> relays = state.relays.where(_matches).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Wrap(
              spacing: NeoSpacing.md,
              runSpacing: NeoSpacing.md,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text('Relays', style: Theme.of(context).textTheme.titleMedium),
                Wrap(
                  spacing: NeoSpacing.md,
                  runSpacing: NeoSpacing.md,
                  children: <Widget>[
                    SizedBox(
                      width: 250,
                      child: NeoSearchField(
                        hintText: 'Search relays',
                        onChanged: (String value) =>
                            setState(() => _query = value.toLowerCase()),
                      ),
                    ),
                    SizedBox(
                      width: 150,
                      child: DropdownButtonFormField<String>(
                        initialValue: _status,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: const <DropdownMenuItem<String>>[
                          DropdownMenuItem(value: 'all', child: Text('All')),
                          DropdownMenuItem(
                              value: 'running', child: Text('Running')),
                          DropdownMenuItem(
                              value: 'stopped', child: Text('Stopped')),
                          DropdownMenuItem(
                              value: 'error', child: Text('Error')),
                        ],
                        onChanged: (String? value) =>
                            setState(() => _status = value ?? 'all'),
                      ),
                    ),
                    NeoButton(
                      label: 'New relay',
                      icon: Icons.add,
                      primary: true,
                      onPressed: () => context.go(AppRoutes.srtRelayNew),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: NeoSpacing.lg),
            _content(state, relays),
          ],
        );
      },
    );
  }

  Widget _content(SrtState state, List<SrtRelayView> relays) {
    if (state.status == LoadStatus.initial ||
        state.status == LoadStatus.loading) {
      return const NeoPanel(
          child: NeoLoadingState(label: 'Loading SRT relays'));
    }
    if (state.status == LoadStatus.failure) {
      return NeoPanel(
        child: NeoErrorState(
          message: state.error,
          onRetry: context.read<SrtCubit>().load,
        ),
      );
    }
    if (relays.isEmpty) {
      return const NeoPanel(
        child: NeoEmptyState(
          title: 'No relays found',
          message: 'Create a relay or adjust the current filters.',
          icon: Icons.cell_tower_outlined,
        ),
      );
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < 820) {
          return Column(
            children: relays
                .map((SrtRelayView relay) => Padding(
                      padding: const EdgeInsets.only(bottom: NeoSpacing.md),
                      child: _RelayCard(relay: relay, actions: this),
                    ))
                .toList(),
          );
        }
        return NeoPanel(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 40,
              dataRowMinHeight: 58,
              dataRowMaxHeight: 68,
              columns: const <DataColumn>[
                DataColumn(label: Text('Relay')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Input')),
                DataColumn(label: Text('SRT endpoint')),
                DataColumn(label: Text('Sessions')),
                DataColumn(label: Text('In / out')),
                DataColumn(label: Text('Errors')),
                DataColumn(label: Text('Actions')),
              ],
              rows: relays.map(_row).toList(),
            ),
          ),
        );
      },
    );
  }

  DataRow _row(SrtRelayView relay) {
    final SrtRelayState runtime = relay.state;
    return DataRow(
      color: runtime.hasError
          ? WidgetStatePropertyAll<Color>(
              NeoColors.danger.withValues(alpha: .04))
          : null,
      cells: <DataCell>[
        DataCell(_RelayName(relay: relay)),
        DataCell(_statusBadge(runtime)),
        DataCell(SizedBox(width: 220, child: Text(relay.config.inputUrl))),
        DataCell(Text(_relayEndpoint(relay.config))),
        DataCell(Text(relay.config.direction == 'publish'
            ? '${runtime.activeClients}/1'
            : '${runtime.activeClients}/${relay.config.maxClients}')),
        DataCell(Text('${formatBitrate(runtime.inputBitrateBps)} / '
            '${formatBitrate(runtime.outputBitrateBps)}')),
        DataCell(
          Tooltip(
            message: runtime.lastError,
            child: Text(
              runtime.lastError.isNotEmpty
                  ? runtime.lastError
                  : '${runtime.continuityErrors} continuity',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        DataCell(_RelayActions(relay: relay, actions: this)),
      ],
    );
  }

  bool _matches(SrtRelayView relay) {
    final bool queryMatches = _query.isEmpty ||
        relay.config.name.toLowerCase().contains(_query) ||
        relay.config.id.toLowerCase().contains(_query) ||
        relay.config.inputUrl.toLowerCase().contains(_query);
    if (!queryMatches || _status == 'all') {
      return queryMatches;
    }
    if (_status == 'running') {
      return relay.state.isRunning;
    }
    if (_status == 'error') {
      return relay.state.hasError;
    }
    return !relay.state.isRunning && !relay.state.hasError;
  }

  Future<void> toggle(SrtRelayView relay) async {
    try {
      if (relay.state.isRunning) {
        await context.read<SrtCubit>().stopRelay(relay.config.id);
      } else {
        await context.read<SrtCubit>().startRelay(relay.config.id);
      }
    } on Object {
      // Cubit exposes the server error through state.
    }
  }

  Future<void> restart(SrtRelayView relay) async {
    try {
      await context.read<SrtCubit>().restartRelay(relay.config.id);
    } on Object {
      return;
    }
  }

  Future<void> delete(SrtRelayView relay) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Delete relay'),
        content:
            Text('Delete ${relay.config.name}? Audit records are retained.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: relay.state.isRunning
                ? null
                : () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if ((confirmed ?? false) && mounted) {
      try {
        await context.read<SrtCubit>().deleteRelay(relay.config.id);
      } on Object {
        return;
      }
    }
  }
}

String _relayEndpoint(SrtRelay relay) => relay.direction == 'publish'
    ? 'Caller → ${relay.destinationAddress}:${relay.destinationPort}'
    : 'Listener ← ${relay.bindAddress}:${relay.port}';

class _RelayCard extends StatelessWidget {
  const _RelayCard({required this.relay, required this.actions});

  final SrtRelayView relay;
  final _SrtRelaysScreenState actions;

  @override
  Widget build(BuildContext context) {
    return NeoPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: _RelayName(relay: relay)),
              _statusBadge(relay.state),
            ],
          ),
          const SizedBox(height: NeoSpacing.md),
          Text(relay.config.inputUrl),
          const SizedBox(height: NeoSpacing.sm),
          Text(
            '${_relayEndpoint(relay.config)}  •  '
            '${relay.state.activeClients}/'
            '${relay.config.direction == 'publish' ? 1 : relay.config.maxClients} sessions',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: NeoSpacing.sm),
          Text('${formatBitrate(relay.state.inputBitrateBps)} in  /  '
              '${formatBitrate(relay.state.outputBitrateBps)} out'),
          if (relay.state.lastError.isNotEmpty) ...<Widget>[
            const SizedBox(height: NeoSpacing.sm),
            Text(relay.state.lastError,
                style: const TextStyle(color: NeoColors.danger)),
          ],
          const SizedBox(height: NeoSpacing.lg),
          Align(
            alignment: Alignment.centerRight,
            child: _RelayActions(relay: relay, actions: actions),
          ),
        ],
      ),
    );
  }
}

class _RelayName extends StatelessWidget {
  const _RelayName({required this.relay});

  final SrtRelayView relay;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(relay.config.name,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        Text(relay.config.id, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

class _RelayActions extends StatelessWidget {
  const _RelayActions({required this.relay, required this.actions});

  final SrtRelayView relay;
  final _SrtRelaysScreenState actions;

  @override
  Widget build(BuildContext context) {
    final bool busy = context.select<SrtCubit, bool>(
      (SrtCubit cubit) => cubit.state.busyIds.contains(relay.config.id),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          tooltip: relay.state.isRunning ? 'Stop relay' : 'Start relay',
          onPressed: busy || (!relay.config.enabled && !relay.state.isRunning)
              ? null
              : () => actions.toggle(relay),
          icon: Icon(relay.state.isRunning
              ? Icons.stop_circle_outlined
              : Icons.play_circle_outline),
        ),
        IconButton(
          tooltip: 'Restart relay',
          onPressed: busy || !relay.state.isRunning
              ? null
              : () => actions.restart(relay),
          icon: const Icon(Icons.restart_alt),
        ),
        IconButton(
          tooltip: 'Edit relay',
          onPressed: busy
              ? null
              : () => context.go(AppRoutes.srtRelayEdit(relay.config.id)),
          icon: const Icon(Icons.edit_outlined),
        ),
        PopupMenuButton<String>(
          tooltip: 'More actions',
          enabled: !busy,
          onSelected: (String value) {
            if (value == 'delete') {
              actions.delete(relay);
            } else if (value == 'audit') {
              context.go('${AppRoutes.srtAudit}?relay=${relay.config.id}');
            }
          },
          itemBuilder: (BuildContext context) => const <PopupMenuEntry<String>>[
            PopupMenuItem(value: 'audit', child: Text('Open audit log')),
            PopupMenuItem(value: 'delete', child: Text('Delete relay')),
          ],
        ),
      ],
    );
  }
}

NeoBadge _statusBadge(SrtRelayState state) {
  final NeoStatusTone tone = state.status == 'degraded'
      ? NeoStatusTone.warning
      : state.hasError
          ? NeoStatusTone.danger
          : state.isRunning
              ? NeoStatusTone.success
              : NeoStatusTone.neutral;
  return NeoBadge(label: state.status.toUpperCase(), tone: tone);
}

void _showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
