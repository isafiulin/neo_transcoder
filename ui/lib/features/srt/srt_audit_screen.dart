import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:neotranscoder_ui/app/theme.dart';
import 'package:neotranscoder_ui/core/api/srt_models.dart';
import 'package:neotranscoder_ui/core/design_system/status.dart';
import 'package:neotranscoder_ui/core/widgets/neo_badge.dart';
import 'package:neotranscoder_ui/core/widgets/neo_button.dart';
import 'package:neotranscoder_ui/core/widgets/neo_panel.dart';
import 'package:neotranscoder_ui/core/widgets/neo_state.dart';
import 'package:neotranscoder_ui/features/srt/srt_cubit.dart';
import 'package:neotranscoder_ui/features/srt/srt_format.dart';

class SrtAuditScreen extends StatefulWidget {
  const SrtAuditScreen({super.key});

  @override
  State<SrtAuditScreen> createState() => _SrtAuditScreenState();
}

class _SrtAuditScreenState extends State<SrtAuditScreen> {
  final ScrollController _horizontal = ScrollController();
  final ScrollController _vertical = ScrollController();
  String _relayId = '';
  String _clientId = '';
  String _type = '';
  bool _initialized = false;

  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SrtState state = context.watch<SrtCubit>().state;
    if (!_initialized) {
      _initialized = true;
      _relayId = GoRouterState.of(context).uri.queryParameters['relay'] ?? '';
      _clientId = GoRouterState.of(context).uri.queryParameters['client'] ?? '';
      if (_relayId.isNotEmpty || _clientId.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _applyFilters());
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          spacing: NeoSpacing.md,
          runSpacing: NeoSpacing.md,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text('Connection audit',
                style: Theme.of(context).textTheme.titleMedium),
            Wrap(
              spacing: NeoSpacing.md,
              runSpacing: NeoSpacing.sm,
              children: <Widget>[
                NeoButton(
                  label: 'Refresh',
                  icon: Icons.refresh,
                  onPressed: _applyFilters,
                ),
                NeoButton(
                  label: 'Clear audit',
                  icon: Icons.delete_sweep_outlined,
                  onPressed: () => _confirmClear(context),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: NeoSpacing.lg),
        NeoPanel(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double width = constraints.maxWidth >= 900
                  ? (constraints.maxWidth - NeoSpacing.lg * 2) / 3
                  : constraints.maxWidth;
              return Wrap(
                spacing: NeoSpacing.lg,
                runSpacing: NeoSpacing.md,
                children: <Widget>[
                  SizedBox(
                    width: width,
                    child: DropdownButtonFormField<String>(
                      initialValue: _relayId,
                      decoration: const InputDecoration(labelText: 'Relay'),
                      items: <DropdownMenuItem<String>>[
                        const DropdownMenuItem(
                            value: '', child: Text('All relays')),
                        ...state.relays
                            .map((SrtRelayView relay) => DropdownMenuItem(
                                  value: relay.config.id,
                                  child: Text(relay.config.name),
                                )),
                      ],
                      onChanged: (String? value) =>
                          setState(() => _relayId = value ?? ''),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: DropdownButtonFormField<String>(
                      initialValue: _clientId,
                      decoration: const InputDecoration(labelText: 'Client'),
                      items: <DropdownMenuItem<String>>[
                        const DropdownMenuItem(
                            value: '', child: Text('All clients')),
                        ...state.clients
                            .map((SrtClient client) => DropdownMenuItem(
                                  value: client.id,
                                  child: Text(client.name),
                                )),
                      ],
                      onChanged: (String? value) =>
                          setState(() => _clientId = value ?? ''),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: DropdownButtonFormField<String>(
                      initialValue: _type,
                      decoration:
                          const InputDecoration(labelText: 'Event type'),
                      items: const <DropdownMenuItem<String>>[
                        DropdownMenuItem(value: '', child: Text('All events')),
                        DropdownMenuItem(
                            value: 'connection_attempt',
                            child: Text('Connection attempts')),
                        DropdownMenuItem(
                            value: 'connection_rejected',
                            child: Text('Rejected connections')),
                        DropdownMenuItem(
                            value: 'session_connected',
                            child: Text('Connected sessions')),
                        DropdownMenuItem(
                            value: 'session_disconnected',
                            child: Text('Disconnected sessions')),
                        DropdownMenuItem(
                            value: 'input_stalled',
                            child: Text('Multicast input stalled')),
                        DropdownMenuItem(
                            value: 'input_restored',
                            child: Text('Multicast input restored')),
                        DropdownMenuItem(
                            value: 'relay_error', child: Text('Relay errors')),
                        DropdownMenuItem(
                            value: 'relay_worker_exited',
                            child: Text('Worker failures')),
                      ],
                      onChanged: (String? value) =>
                          setState(() => _type = value ?? ''),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: NeoSpacing.lg),
        if (state.audit.isEmpty)
          const NeoPanel(
            child: NeoEmptyState(
              title: 'No audit records',
              message: 'Connection attempts and operator actions appear here.',
              icon: Icons.receipt_long_outlined,
            ),
          )
        else
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) =>
                constraints.maxWidth < 900
                    ? _cards(state.audit)
                    : _table(state.audit),
          ),
      ],
    );
  }

  Widget _cards(List<SrtAuditEvent> events) {
    return SizedBox(
      height: 620,
      child: ListView.separated(
        controller: _vertical,
        itemCount: events.length,
        separatorBuilder: (_, __) => const SizedBox(height: NeoSpacing.md),
        itemBuilder: (BuildContext context, int index) {
          final SrtAuditEvent event = events[index];
          return NeoPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(_eventLabel(event.type),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    _levelBadge(event.level),
                  ],
                ),
                const SizedBox(height: NeoSpacing.sm),
                Text(
                    '${event.remoteIp}${event.remotePort == 0 ? '' : ':${event.remotePort}'}'
                    '  •  ${event.clientId.isEmpty ? 'unknown client' : event.clientId}'
                    '  •  ${event.relayId}'),
                if (event.reason.isNotEmpty) ...<Widget>[
                  const SizedBox(height: NeoSpacing.sm),
                  Text(event.reason),
                ],
                const SizedBox(height: NeoSpacing.sm),
                Text(formatTimestamp(event.time),
                    style: Theme.of(context).textTheme.labelMedium),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _table(List<SrtAuditEvent> events) {
    const List<double> widths = <double>[
      180,
      128,
      180,
      110,
      110,
      190,
      180,
      310,
    ];
    const double tableWidth = 1388;
    return NeoPanel(
      child: Scrollbar(
        controller: _horizontal,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _horizontal,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            height: 620,
            child: Column(
              children: <Widget>[
                const _AuditTableRow(
                  widths: widths,
                  header: true,
                  cells: <Widget>[
                    Text('Time'),
                    Text('Level'),
                    Text('Event'),
                    Text('Relay'),
                    Text('Client'),
                    Text('Remote address'),
                    Text('Stream ID'),
                    Text('Reason / actor'),
                  ],
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    controller: _vertical,
                    itemCount: events.length,
                    itemExtent: 48,
                    itemBuilder: (BuildContext context, int index) {
                      final SrtAuditEvent event = events[index];
                      final String reason =
                          event.reason.isNotEmpty ? event.reason : event.actor;
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: Theme.of(context).dividerColor,
                            ),
                          ),
                        ),
                        child: _AuditTableRow(
                          widths: widths,
                          cells: <Widget>[
                            Text(formatTimestamp(event.time)),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: _levelBadge(event.level),
                            ),
                            Text(_eventLabel(event.type)),
                            Text(event.relayId),
                            Text(event.clientId),
                            Text(event.remoteIp.isEmpty
                                ? '—'
                                : '${event.remoteIp}:${event.remotePort}'),
                            Text(event.streamId),
                            Tooltip(
                              message: reason,
                              child: Text(
                                reason,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _applyFilters() => context.read<SrtCubit>().reloadAudit(
        relayId: _relayId,
        clientId: _clientId,
        type: _type,
      );

  Future<void> _confirmClear(BuildContext context) async {
    final List<String> filters = <String>[
      if (_relayId.isNotEmpty) 'relay $_relayId',
      if (_clientId.isNotEmpty) 'client $_clientId',
      if (_type.isNotEmpty) _eventLabel(_type).toLowerCase(),
    ];
    final String target =
        filters.isEmpty ? 'all SRT audit records' : filters.join(', ');
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Clear audit'),
        content: Text('Delete stored audit records for $target?'),
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
      await context.read<SrtCubit>().clearAudit(
            relayId: _relayId,
            clientId: _clientId,
            type: _type,
          );
    }
  }
}

class _AuditTableRow extends StatelessWidget {
  const _AuditTableRow({
    required this.widths,
    required this.cells,
    this.header = false,
  });

  final List<double> widths;
  final List<Widget> cells;
  final bool header;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: header ? 40 : 47,
      child: Row(
        children: List<Widget>.generate(cells.length, (int index) {
          return SizedBox(
            width: widths[index],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: NeoSpacing.sm),
              child: DefaultTextStyle.merge(
                style: header
                    ? const TextStyle(fontWeight: FontWeight.w600)
                    : null,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                child: cells[index],
              ),
            ),
          );
        }),
      ),
    );
  }
}

NeoBadge _levelBadge(String level) {
  final NeoStatusTone tone = switch (level) {
    'error' => NeoStatusTone.danger,
    'warning' => NeoStatusTone.warning,
    _ => NeoStatusTone.info,
  };
  return NeoBadge(label: level.toUpperCase(), tone: tone);
}

String _eventLabel(String value) => value
    .split('_')
    .map((String word) =>
        word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}')
    .join(' ');
