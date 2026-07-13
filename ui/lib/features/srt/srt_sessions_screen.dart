import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:neotranscoder_ui/app/theme.dart';
import 'package:neotranscoder_ui/core/api/srt_models.dart';
import 'package:neotranscoder_ui/core/design_system/status.dart';
import 'package:neotranscoder_ui/core/widgets/neo_badge.dart';
import 'package:neotranscoder_ui/core/widgets/neo_panel.dart';
import 'package:neotranscoder_ui/core/widgets/neo_search_field.dart';
import 'package:neotranscoder_ui/core/widgets/neo_state.dart';
import 'package:neotranscoder_ui/features/srt/srt_cubit.dart';
import 'package:neotranscoder_ui/features/srt/srt_format.dart';

class SrtSessionsScreen extends StatefulWidget {
  const SrtSessionsScreen({super.key});

  @override
  State<SrtSessionsScreen> createState() => _SrtSessionsScreenState();
}

class _SrtSessionsScreenState extends State<SrtSessionsScreen> {
  String _query = '';
  bool _activeOnly = true;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SrtCubit, SrtState>(
      builder: (BuildContext context, SrtState state) {
        final List<SrtSession> sessions =
            state.sessions.where((SrtSession item) {
          if (_activeOnly && !item.isActive) {
            return false;
          }
          final String searchable = '${item.clientId} ${item.relayId} '
                  '${item.remoteIp} ${item.streamId}'
              .toLowerCase();
          return _query.isEmpty || searchable.contains(_query);
        }).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Wrap(
              spacing: NeoSpacing.md,
              runSpacing: NeoSpacing.md,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text('Sessions',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(width: NeoSpacing.md),
                    NeoBadge(
                      label:
                          '${state.sessions.where((SrtSession s) => s.isActive).length} ACTIVE',
                      tone: NeoStatusTone.success,
                    ),
                  ],
                ),
                Wrap(
                  spacing: NeoSpacing.md,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    SizedBox(
                      width: 280,
                      child: NeoSearchField(
                        hintText: 'Client, relay or remote IP',
                        onChanged: (String value) =>
                            setState(() => _query = value.toLowerCase()),
                      ),
                    ),
                    FilterChip(
                      label: const Text('Active only'),
                      selected: _activeOnly,
                      onSelected: (bool value) =>
                          setState(() => _activeOnly = value),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: NeoSpacing.lg),
            if (sessions.isEmpty)
              const NeoPanel(
                child: NeoEmptyState(
                  title: 'No matching sessions',
                  message: 'Connected receivers appear here in real time.',
                  icon: Icons.link_off_outlined,
                ),
              )
            else
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) =>
                    constraints.maxWidth < 880
                        ? _cards(sessions)
                        : _table(sessions),
              ),
          ],
        );
      },
    );
  }

  Widget _cards(List<SrtSession> sessions) {
    return Column(
      children: sessions
          .map((SrtSession session) => Padding(
                padding: const EdgeInsets.only(bottom: NeoSpacing.md),
                child: NeoPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(session.clientId,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                          ),
                          _sessionBadge(session),
                        ],
                      ),
                      const SizedBox(height: NeoSpacing.sm),
                      Text('${session.remoteIp}:${session.remotePort}  •  '
                          '${session.relayId}'),
                      const SizedBox(height: NeoSpacing.sm),
                      Text('${formatBitrate(session.stats.bitrateBps)}  •  '
                          '${session.stats.rttMs.toStringAsFixed(1)} ms RTT  •  '
                          '${session.stats.packetsLost} lost'),
                      const SizedBox(height: NeoSpacing.sm),
                      Text(
                        session.isActive
                            ? 'Connected ${formatTimestamp(session.connectedAt)}'
                            : 'Disconnected ${formatTimestamp(session.disconnectedAt)}: '
                                '${session.disconnectReason}',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                  ),
                ),
              ))
          .toList(),
    );
  }

  Widget _table(List<SrtSession> sessions) {
    return NeoPanel(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 40,
          columns: const <DataColumn>[
            DataColumn(label: Text('State')),
            DataColumn(label: Text('Client')),
            DataColumn(label: Text('Relay')),
            DataColumn(label: Text('Remote address')),
            DataColumn(label: Text('Encryption')),
            DataColumn(label: Text('Bitrate')),
            DataColumn(label: Text('RTT')),
            DataColumn(label: Text('Lost / retransmitted')),
            DataColumn(label: Text('Connected')),
            DataColumn(label: Text('Disconnect reason')),
          ],
          rows: sessions
              .map((SrtSession session) => DataRow(cells: <DataCell>[
                    DataCell(_sessionBadge(session)),
                    DataCell(Text(session.clientId)),
                    DataCell(Text(session.relayId)),
                    DataCell(Text('${session.remoteIp}:${session.remotePort}')),
                    DataCell(Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          session.encrypted ? Icons.lock : Icons.lock_open,
                          size: 16,
                          color: session.encrypted
                              ? NeoColors.success
                              : NeoColors.danger,
                        ),
                        const SizedBox(width: NeoSpacing.xs),
                        Text(session.encrypted ? 'AES-256' : 'No'),
                      ],
                    )),
                    DataCell(Text(formatBitrate(session.stats.bitrateBps))),
                    DataCell(
                        Text('${session.stats.rttMs.toStringAsFixed(1)} ms')),
                    DataCell(Text('${session.stats.packetsLost} / '
                        '${session.stats.packetsRetransmitted}')),
                    DataCell(Text(formatTimestamp(session.connectedAt))),
                    DataCell(SizedBox(
                      width: 190,
                      child: Text(session.disconnectReason,
                          overflow: TextOverflow.ellipsis),
                    )),
                  ]))
              .toList(),
        ),
      ),
    );
  }
}

NeoBadge _sessionBadge(SrtSession session) => NeoBadge(
      label: session.isActive ? 'CONNECTED' : 'CLOSED',
      tone: session.isActive ? NeoStatusTone.success : NeoStatusTone.neutral,
    );
