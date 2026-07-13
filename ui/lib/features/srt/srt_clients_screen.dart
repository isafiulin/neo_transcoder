import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:neotranscoder_ui/app/app_routes.dart';
import 'package:neotranscoder_ui/app/theme.dart';
import 'package:neotranscoder_ui/core/api/srt_models.dart';
import 'package:neotranscoder_ui/core/design_system/status.dart';
import 'package:neotranscoder_ui/core/widgets/neo_badge.dart';
import 'package:neotranscoder_ui/core/widgets/neo_button.dart';
import 'package:neotranscoder_ui/core/widgets/neo_panel.dart';
import 'package:neotranscoder_ui/core/widgets/neo_search_field.dart';
import 'package:neotranscoder_ui/core/widgets/neo_state.dart';
import 'package:neotranscoder_ui/features/srt/srt_cubit.dart';
import 'package:neotranscoder_ui/features/srt/srt_format.dart';

class SrtClientsScreen extends StatefulWidget {
  const SrtClientsScreen({super.key});

  @override
  State<SrtClientsScreen> createState() => _SrtClientsScreenState();
}

class _SrtClientsScreenState extends State<SrtClientsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SrtCubit, SrtState>(
      builder: (BuildContext context, SrtState state) {
        final List<SrtClient> clients = state.clients.where((SrtClient client) {
          return _query.isEmpty ||
              client.id.toLowerCase().contains(_query) ||
              client.name.toLowerCase().contains(_query) ||
              client.allowedCidrs.join(' ').toLowerCase().contains(_query);
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
                Text('Access clients',
                    style: Theme.of(context).textTheme.titleMedium),
                Wrap(
                  spacing: NeoSpacing.md,
                  children: <Widget>[
                    SizedBox(
                      width: 260,
                      child: NeoSearchField(
                        hintText: 'Search clients or IP',
                        onChanged: (String value) =>
                            setState(() => _query = value.toLowerCase()),
                      ),
                    ),
                    NeoButton(
                      label: 'New client',
                      icon: Icons.person_add_alt_1_outlined,
                      primary: true,
                      onPressed: state.relays.isEmpty
                          ? null
                          : () => context.go(AppRoutes.srtClientNew),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: NeoSpacing.lg),
            if (state.relays.isEmpty)
              const NeoPanel(
                child: NeoEmptyState(
                  title: 'Create a relay first',
                  message:
                      'Each client must be assigned to at least one relay.',
                  icon: Icons.key_off_outlined,
                ),
              )
            else if (clients.isEmpty)
              const NeoPanel(
                child: NeoEmptyState(
                  title: 'No access clients',
                  message: 'Create a client or adjust the search filter.',
                  icon: Icons.key_outlined,
                ),
              )
            else
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) =>
                    constraints.maxWidth < 820
                        ? _cards(clients)
                        : _table(clients),
              ),
          ],
        );
      },
    );
  }

  Widget _cards(List<SrtClient> clients) {
    return Column(
      children: clients
          .map((SrtClient client) => Padding(
                padding: const EdgeInsets.only(bottom: NeoSpacing.md),
                child: NeoPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(child: _name(client)),
                          _enabledBadge(client),
                        ],
                      ),
                      const SizedBox(height: NeoSpacing.md),
                      Text('Relays: ${client.allowedRelayIds.join(', ')}'),
                      const SizedBox(height: NeoSpacing.sm),
                      Text('IP ACL: ${client.allowedCidrs.join(', ')}'),
                      const SizedBox(height: NeoSpacing.sm),
                      Text('${_securityLabel(client)}  •  '
                          '${client.maxSessions} concurrent sessions'),
                      const SizedBox(height: NeoSpacing.md),
                      Align(
                        alignment: Alignment.centerRight,
                        child: _actions(client),
                      ),
                    ],
                  ),
                ),
              ))
          .toList(),
    );
  }

  Widget _table(List<SrtClient> clients) {
    return NeoPanel(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 40,
          dataRowMinHeight: 58,
          dataRowMaxHeight: 74,
          columns: const <DataColumn>[
            DataColumn(label: Text('Client')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Allowed relays')),
            DataColumn(label: Text('IP / CIDR ACL')),
            DataColumn(label: Text('Sessions')),
            DataColumn(label: Text('Security')),
            DataColumn(label: Text('Updated')),
            DataColumn(label: Text('Actions')),
          ],
          rows: clients
              .map((SrtClient client) => DataRow(cells: <DataCell>[
                    DataCell(_name(client)),
                    DataCell(_enabledBadge(client)),
                    DataCell(SizedBox(
                      width: 190,
                      child: Text(client.allowedRelayIds.join(', ')),
                    )),
                    DataCell(SizedBox(
                      width: 220,
                      child: Text(client.allowedCidrs.join(', ')),
                    )),
                    DataCell(Text('${client.maxSessions} max')),
                    DataCell(Text(_securityLabel(client))),
                    DataCell(Text(formatTimestamp(client.updatedAt))),
                    DataCell(_actions(client)),
                  ]))
              .toList(),
        ),
      ),
    );
  }

  Widget _name(SrtClient client) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(client.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        Text(client.id, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }

  Widget _enabledBadge(SrtClient client) => NeoBadge(
        label: client.enabled ? 'ENABLED' : 'DISABLED',
        tone: client.enabled ? NeoStatusTone.success : NeoStatusTone.neutral,
      );

  Widget _actions(SrtClient client) {
    final bool busy = context.select<SrtCubit, bool>(
      (SrtCubit cubit) => cubit.state.busyIds.contains(client.id),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          tooltip: 'Edit client',
          onPressed: busy
              ? null
              : () => context.go(AppRoutes.srtClientEdit(client.id)),
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          tooltip: client.encryptionMode == 'none'
              ? 'Encryption is disabled'
              : 'Rotate encryption key',
          onPressed: busy || client.encryptionMode == 'none'
              ? null
              : () => _rotate(client),
          icon: const Icon(Icons.autorenew_outlined),
        ),
        IconButton(
          tooltip: 'Delete client',
          onPressed: busy ? null : () => _delete(client),
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }

  String _securityLabel(SrtClient client) => client.encryptionMode == 'none'
      ? 'No encryption · IP ACL'
      : 'AES-256 · key v${client.keyVersion}';

  Future<void> _rotate(SrtClient client) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Rotate encryption key'),
        content: Text(
          'Existing key for ${client.name} will stop working. '
          'Assigned running relays and their connected sessions will restart.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Rotate key'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !mounted) {
      return;
    }
    try {
      final SrtClientCredential credential =
          await context.read<SrtCubit>().rotateClientKey(client.id);
      if (mounted) {
        await showSrtCredentialDialog(context, credential);
      }
    } on Object catch (error) {
      if (mounted) {
        _error('$error');
      }
    }
  }

  Future<void> _delete(SrtClient client) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Delete access client'),
        content: Text('Delete ${client.name}? Audit records are retained.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if ((confirmed ?? false) && mounted) {
      try {
        await context.read<SrtCubit>().deleteClient(client.id);
      } on Object catch (error) {
        if (mounted) {
          _error('$error');
        }
      }
    }
  }

  void _error(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<void> showSrtCredentialDialog(
  BuildContext context,
  SrtClientCredential credential,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) => AlertDialog(
      icon: const Icon(Icons.key_outlined, color: NeoColors.blue),
      title: const Text('New SRT encryption key'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              'This passphrase is shown once. Store it in the receiver secret '
              'manager before closing this window.',
            ),
            const SizedBox(height: NeoSpacing.lg),
            Text('Client ID', style: Theme.of(context).textTheme.labelMedium),
            SelectableText(credential.client.id),
            const SizedBox(height: NeoSpacing.md),
            Text('Passphrase', style: Theme.of(context).textTheme.labelMedium),
            DecoratedBox(
              decoration: BoxDecoration(
                color: NeoColors.page,
                border: Border.all(color: NeoColors.line),
                borderRadius: BorderRadius.circular(NeoRadius.sm),
              ),
              child: Padding(
                padding: const EdgeInsets.all(NeoSpacing.md),
                child: SelectableText(
                  credential.passphrase,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        OutlinedButton.icon(
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(text: credential.passphrase),
            );
          },
          icon: const Icon(Icons.copy_outlined, size: 18),
          label: const Text('Copy key'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('I stored the key'),
        ),
      ],
    ),
  );
}
