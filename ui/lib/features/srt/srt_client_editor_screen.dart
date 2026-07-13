import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:neotranscoder_ui/app/app_routes.dart';
import 'package:neotranscoder_ui/app/theme.dart';
import 'package:neotranscoder_ui/core/api/srt_models.dart';
import 'package:neotranscoder_ui/core/widgets/neo_button.dart';
import 'package:neotranscoder_ui/core/widgets/neo_panel.dart';
import 'package:neotranscoder_ui/core/widgets/neo_state.dart';
import 'package:neotranscoder_ui/features/srt/srt_clients_screen.dart';
import 'package:neotranscoder_ui/features/srt/srt_cubit.dart';

class SrtClientEditorScreen extends StatefulWidget {
  const SrtClientEditorScreen({this.clientId, super.key});

  final String? clientId;

  @override
  State<SrtClientEditorScreen> createState() => _SrtClientEditorScreenState();
}

class _SrtClientEditorScreenState extends State<SrtClientEditorScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _id = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _cidrs = TextEditingController();
  final TextEditingController _maxSessions = TextEditingController(text: '1');
  final Set<String> _relayIds = <String>{};
  bool _enabled = true;
  String _encryptionMode = 'aes-256';
  bool _initialized = false;
  bool _saving = false;

  bool get _editing => widget.clientId != null;

  @override
  void dispose() {
    _id.dispose();
    _name.dispose();
    _cidrs.dispose();
    _maxSessions.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SrtCubit, SrtState>(
      builder: (BuildContext context, SrtState state) {
        final SrtClient? existing =
            widget.clientId == null ? null : state.client(widget.clientId!);
        if (_editing && existing == null && state.status.name != 'ready') {
          return const NeoPanel(
            child: NeoLoadingState(label: 'Loading client settings'),
          );
        }
        if (_editing && existing == null) {
          return NeoPanel(
            child: NeoErrorState(
              message: 'Client ${widget.clientId} was not found.',
              onRetry: () => context.go(AppRoutes.srtClients),
            ),
          );
        }
        if (!_initialized) {
          _initialize(existing);
        }
        return Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _header(),
              const SizedBox(height: NeoSpacing.lg),
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final List<Widget> panels = <Widget>[
                    Expanded(flex: 5, child: _identityPanel()),
                    const SizedBox(width: NeoSpacing.lg),
                    Expanded(flex: 4, child: _accessPanel(state.relays)),
                  ];
                  if (constraints.maxWidth >= 940) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: panels,
                    );
                  }
                  return Column(
                    children: <Widget>[
                      _identityPanel(),
                      const SizedBox(height: NeoSpacing.lg),
                      _accessPanel(state.relays),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _header() {
    return Wrap(
      spacing: NeoSpacing.md,
      runSpacing: NeoSpacing.md,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IconButton(
              tooltip: 'Back to clients',
              onPressed: () => context.go(AppRoutes.srtClients),
              icon: const Icon(Icons.arrow_back),
            ),
            Text(_editing ? 'Edit access client' : 'New access client',
                style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        Wrap(
          spacing: NeoSpacing.md,
          children: <Widget>[
            NeoButton(
              label: 'Cancel',
              icon: Icons.close,
              onPressed:
                  _saving ? null : () => context.go(AppRoutes.srtClients),
            ),
            NeoButton(
              label: _saving ? 'Saving' : 'Save client',
              icon: Icons.save_outlined,
              primary: true,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ],
    );
  }

  Widget _identityPanel() {
    return NeoPanel(
      title: 'Client identity',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextFormField(
            controller: _id,
            enabled: !_editing,
            decoration: const InputDecoration(
              labelText: 'Client ID / Stream ID',
              hintText: 'partner-a',
              helperText: 'Receiver sends this value as its SRT Stream ID.',
            ),
            validator: (String? value) => RegExp(
              r'^[A-Za-z0-9][A-Za-z0-9._-]{2,63}$',
            ).hasMatch(value?.trim() ?? '')
                ? null
                : 'Use 3–64 letters, numbers, dots, underscores or hyphens.',
          ),
          const SizedBox(height: NeoSpacing.md),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Display name',
              hintText: 'Distribution partner A',
            ),
            validator: (String? value) => (value?.trim().isEmpty ?? true)
                ? 'This field is required.'
                : null,
          ),
          const SizedBox(height: NeoSpacing.md),
          TextFormField(
            controller: _maxSessions,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Maximum concurrent sessions',
            ),
            validator: (String? value) {
              final int? number = int.tryParse(value ?? '');
              return number == null || number < 1 || number > 1000
                  ? 'Use 1–1000.'
                  : null;
            },
          ),
          const SizedBox(height: NeoSpacing.lg),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Client enabled'),
            subtitle: const Text('Disabled clients are rejected at handshake.'),
            value: _enabled,
            onChanged: (bool value) => setState(() => _enabled = value),
          ),
        ],
      ),
    );
  }

  Widget _accessPanel(List<SrtRelayView> relays) {
    return NeoPanel(
      title: 'Access policy',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('Transport security',
              style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: NeoSpacing.sm),
          SegmentedButton<String>(
            segments: const <ButtonSegment<String>>[
              ButtonSegment<String>(
                value: 'aes-256',
                icon: Icon(Icons.lock_outline),
                label: Text('AES-256 + IP ACL'),
              ),
              ButtonSegment<String>(
                value: 'none',
                icon: Icon(Icons.lock_open_outlined),
                label: Text('IP ACL only'),
              ),
            ],
            selected: <String>{_encryptionMode},
            onSelectionChanged: (Set<String> selection) => setState(() {
              _encryptionMode = selection.first;
              _formKey.currentState?.validate();
            }),
          ),
          const SizedBox(height: NeoSpacing.md),
          _securityModeNote(),
          const SizedBox(height: NeoSpacing.lg),
          Text('Allowed relays',
              style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: NeoSpacing.sm),
          Wrap(
            spacing: NeoSpacing.sm,
            runSpacing: NeoSpacing.sm,
            children: relays
                .map((SrtRelayView relay) => FilterChip(
                      label: Text(relay.config.name),
                      selected: _relayIds.contains(relay.config.id),
                      onSelected: (bool selected) {
                        setState(() {
                          if (selected) {
                            _relayIds.add(relay.config.id);
                          } else {
                            _relayIds.remove(relay.config.id);
                          }
                        });
                      },
                    ))
                .toList(),
          ),
          if (_relayIds.isEmpty) ...<Widget>[
            const SizedBox(height: NeoSpacing.xs),
            const Text(
              'Select at least one relay.',
              style: TextStyle(color: NeoColors.danger, fontSize: 12),
            ),
          ],
          const SizedBox(height: NeoSpacing.lg),
          TextFormField(
            controller: _cidrs,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Allowed IP addresses or CIDR networks',
              hintText: '203.0.113.8\n198.51.100.0/24',
              helperText:
                  'One value per line. A plain IP is stored as /32 or /128.',
              alignLabelWithHint: true,
            ),
            validator: (String? value) {
              final List<String> entries = _lines(value ?? '');
              if (entries.isEmpty) {
                return 'Add at least one source IP or CIDR.';
              }
              for (final String entry in entries) {
                if (!_looksLikeIpOrCidr(entry)) {
                  return 'Invalid IP or CIDR: $entry';
                }
                if (_encryptionMode == 'none' &&
                    _isUnrestrictedNetwork(entry)) {
                  return 'Global /0 networks require encryption.';
                }
              }
              return null;
            },
          ),
          const SizedBox(height: NeoSpacing.lg),
        ],
      ),
    );
  }

  Widget _securityModeNote() {
    final bool encrypted = _encryptionMode == 'aes-256';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: (encrypted ? NeoColors.blue : NeoColors.warning)
            .withValues(alpha: .08),
        border: Border.all(
          color: (encrypted ? NeoColors.blue : NeoColors.warning)
              .withValues(alpha: .3),
        ),
        borderRadius: BorderRadius.circular(NeoRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.all(NeoSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              encrypted ? Icons.lock_outline : Icons.warning_amber_outlined,
              size: 20,
              color: encrypted ? NeoColors.blue : NeoColors.warning,
            ),
            const SizedBox(width: NeoSpacing.md),
            Expanded(
              child: Text(
                encrypted
                    ? 'The server generates an AES-256 passphrase and shows it '
                        'once. The source IP/CIDR is checked independently.'
                    : 'Media is sent without encryption. Access relies on the '
                        'source IP/CIDR and Stream ID. Prefer a dedicated public '
                        'IP; callers behind the same NAT share the IP trust.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _initialize(SrtClient? client) {
    _initialized = true;
    if (client == null) {
      return;
    }
    _id.text = client.id;
    _name.text = client.name;
    _cidrs.text = client.allowedCidrs.join('\n');
    _maxSessions.text = '${client.maxSessions}';
    _relayIds.addAll(client.allowedRelayIds);
    _enabled = client.enabled;
    _encryptionMode = client.encryptionMode;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false) || _relayIds.isEmpty) {
      setState(() {});
      return;
    }
    setState(() => _saving = true);
    try {
      final SrtClientCredential credential =
          await context.read<SrtCubit>().saveClient(
        <String, Object?>{
          'id': _id.text.trim(),
          'name': _name.text.trim(),
          'enabled': _enabled,
          'encryption_mode': _encryptionMode,
          'allowed_relay_ids': _relayIds.toList()..sort(),
          'allowed_cidrs': _lines(_cidrs.text),
          'max_sessions': int.parse(_maxSessions.text),
        },
        originalId: widget.clientId,
      );
      if (!mounted) {
        return;
      }
      if (credential.passphrase.isNotEmpty) {
        await showSrtCredentialDialog(context, credential);
      }
      if (mounted) {
        context.go(AppRoutes.srtClients);
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}

List<String> _lines(String value) => value
    .split(RegExp(r'[\n,;]+'))
    .map((String item) => item.trim())
    .where((String item) => item.isNotEmpty)
    .toList();

bool _looksLikeIpOrCidr(String value) {
  final String address = value.split('/').first;
  if (address.contains(':')) {
    return RegExp(r'^[0-9A-Fa-f:]+$').hasMatch(address);
  }
  final List<String> parts = address.split('.');
  return parts.length == 4 &&
      parts.every((String part) {
        final int? number = int.tryParse(part);
        return number != null && number >= 0 && number <= 255;
      });
}

bool _isUnrestrictedNetwork(String value) {
  final List<String> parts = value.split('/');
  return parts.length == 2 && parts.last == '0';
}
