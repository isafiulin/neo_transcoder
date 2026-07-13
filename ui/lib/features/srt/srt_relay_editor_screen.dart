import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:neotranscoder_ui/app/app_routes.dart';
import 'package:neotranscoder_ui/app/theme.dart';
import 'package:neotranscoder_ui/core/api/srt_models.dart';
import 'package:neotranscoder_ui/core/widgets/neo_button.dart';
import 'package:neotranscoder_ui/core/widgets/neo_panel.dart';
import 'package:neotranscoder_ui/core/widgets/neo_state.dart';
import 'package:neotranscoder_ui/features/srt/srt_cubit.dart';
import 'package:neotranscoder_ui/features/srt/srt_relay_guide_dialog.dart';

class SrtRelayEditorScreen extends StatefulWidget {
  const SrtRelayEditorScreen({this.relayId, super.key});

  final String? relayId;

  @override
  State<SrtRelayEditorScreen> createState() => _SrtRelayEditorScreenState();
}

class _SrtRelayEditorScreenState extends State<SrtRelayEditorScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _id = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _input = TextEditingController();
  final TextEditingController _interface = TextEditingController();
  final TextEditingController _bind = TextEditingController(text: '0.0.0.0');
  final TextEditingController _port = TextEditingController(text: '9000');
  final TextEditingController _destination = TextEditingController();
  final TextEditingController _destinationPort =
      TextEditingController(text: '9000');
  final TextEditingController _streamId = TextEditingController();
  final TextEditingController _latency = TextEditingController(text: '800');
  final TextEditingController _payload = TextEditingController(text: '1316');
  final TextEditingController _maxClients = TextEditingController(text: '16');
  final TextEditingController _inputTimeout = TextEditingController(text: '10');
  bool _enabled = true;
  String _direction = 'publish';
  String _encryptionMode = 'aes-256';
  bool _allowMissingStreamId = false;
  String _defaultClientId = '';
  bool _initialized = false;
  bool _saving = false;

  bool get _editing => widget.relayId != null;

  @override
  void dispose() {
    _id.dispose();
    _name.dispose();
    _input.dispose();
    _interface.dispose();
    _bind.dispose();
    _port.dispose();
    _destination.dispose();
    _destinationPort.dispose();
    _streamId.dispose();
    _latency.dispose();
    _payload.dispose();
    _maxClients.dispose();
    _inputTimeout.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SrtCubit, SrtState>(
      builder: (BuildContext context, SrtState state) {
        final SrtRelayView? existing =
            widget.relayId == null ? null : state.relay(widget.relayId!);
        if (_editing && existing == null && state.status.name != 'ready') {
          return const NeoPanel(
            child: NeoLoadingState(label: 'Loading relay settings'),
          );
        }
        if (_editing && existing == null) {
          return NeoPanel(
            child: NeoErrorState(
              message: 'Relay ${widget.relayId} was not found.',
              onRetry: () => context.go(AppRoutes.srtRelays),
            ),
          );
        }
        if (!_initialized) {
          _initialize(existing?.config);
        }
        return Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _EditorHeader(
                title: _editing ? 'Edit relay' : 'New relay',
                saving: _saving,
                onCancel: () => context.go(AppRoutes.srtRelays),
                onSave: _save,
              ),
              const SizedBox(height: NeoSpacing.lg),
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final bool wide = constraints.maxWidth >= 940;
                  if (!wide) {
                    return Column(
                      children: <Widget>[
                        _identityPanel(),
                        const SizedBox(height: NeoSpacing.lg),
                        _transportPanel(state.clients),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(flex: 5, child: _identityPanel()),
                      const SizedBox(width: NeoSpacing.lg),
                      Expanded(flex: 4, child: _transportPanel(state.clients)),
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

  Widget _identityPanel() {
    return NeoPanel(
      title: 'Source and identity',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _field(
            controller: _id,
            label: 'Relay ID',
            hint: 'news-hd',
            enabled: !_editing,
            validator: (String? value) => _idValidator(value),
          ),
          const SizedBox(height: NeoSpacing.md),
          _field(
            controller: _name,
            label: 'Display name',
            hint: 'News HD internet delivery',
            validator: _required,
          ),
          const SizedBox(height: NeoSpacing.md),
          _field(
            controller: _input,
            label: 'Multicast input',
            hint: 'udp://239.10.10.1:1234',
            helper: 'UDP multicast MPEG-TS. Media is forwarded unchanged.',
            validator: (String? value) {
              final Uri? uri = Uri.tryParse(value?.trim() ?? '');
              if (uri == null ||
                  uri.scheme != 'udp' ||
                  uri.host.isEmpty ||
                  !uri.hasPort) {
                return 'Enter a UDP multicast URL with a port.';
              }
              return null;
            },
          ),
          const SizedBox(height: NeoSpacing.md),
          _field(
            controller: _interface,
            label: 'Input network interface',
            hint: 'eno1',
            helper:
                'Optional. Use the Linux interface that receives multicast.',
          ),
          const SizedBox(height: NeoSpacing.lg),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enabled'),
            subtitle: const Text(
              'Start automatically with the service and allow operator control.',
            ),
            value: _enabled,
            onChanged: (bool value) => setState(() => _enabled = value),
          ),
        ],
      ),
    );
  }

  Widget _transportPanel(List<SrtClient> clients) {
    final List<SrtClient> eligibleClients = clients
        .where((SrtClient client) =>
            client.enabled && client.allowedRelayIds.contains(_id.text.trim()))
        .toList();
    return NeoPanel(
      title: _direction == 'publish' ? 'Publish to partner' : 'SRT listener',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SegmentedButton<String>(
            segments: const <ButtonSegment<String>>[
              ButtonSegment(value: 'publish', label: Text('Publish · Caller')),
              ButtonSegment(
                  value: 'listener', label: Text('Accept · Listener')),
            ],
            selected: <String>{_direction},
            onSelectionChanged: (Set<String> value) =>
                setState(() => _direction = value.first),
          ),
          const SizedBox(height: NeoSpacing.lg),
          if (_direction == 'listener') ...<Widget>[
            _field(
              controller: _bind,
              label: 'Bind address',
              hint: '0.0.0.0',
              validator: _required,
            ),
            const SizedBox(height: NeoSpacing.md),
            _numberField(
                controller: _port, label: 'UDP port', min: 1, max: 65535),
            const SizedBox(height: NeoSpacing.lg),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Allow connections without Stream ID'),
              subtitle: Text(
                eligibleClients.isEmpty
                    ? 'Create and assign an enabled Access Client to this relay first.'
                    : 'Compatibility mode for VLC and legacy SRT 1.0+ '
                        'receivers. IP ACL and encryption still apply.',
              ),
              value: _allowMissingStreamId,
              onChanged: eligibleClients.isEmpty
                  ? null
                  : (bool value) => setState(() {
                        _allowMissingStreamId = value;
                        if (value &&
                            !eligibleClients.any((SrtClient client) =>
                                client.id == _defaultClientId)) {
                          _defaultClientId = eligibleClients.first.id;
                        }
                      }),
            ),
            if (_allowMissingStreamId) ...<Widget>[
              const SizedBox(height: NeoSpacing.md),
              DropdownButtonFormField<String>(
                key: ValueKey<String>(
                  'default-client-$_defaultClientId-${eligibleClients.map((SrtClient client) => client.id).join(',')}',
                ),
                initialValue:
                    _defaultClientId.isEmpty ? null : _defaultClientId,
                decoration: const InputDecoration(
                  labelText: 'Default client',
                  helperText:
                      'Connections without Stream ID use only this client policy.',
                  helperMaxLines: 2,
                ),
                items: eligibleClients
                    .map((SrtClient client) => DropdownMenuItem<String>(
                          value: client.id,
                          child: Text(client.name),
                        ))
                    .toList(),
                onChanged: (String? value) =>
                    setState(() => _defaultClientId = value ?? ''),
                validator: (String? value) =>
                    _allowMissingStreamId && (value == null || value.isEmpty)
                        ? 'Select a default client.'
                        : null,
              ),
            ],
          ] else ...<Widget>[
            _field(
              controller: _destination,
              label: 'Partner destination IP',
              hint: '203.0.113.50',
              validator: _required,
            ),
            const SizedBox(height: NeoSpacing.md),
            Row(children: <Widget>[
              Expanded(
                child: _numberField(
                  controller: _destinationPort,
                  label: 'Partner UDP port',
                  min: 1,
                  max: 65535,
                ),
              ),
              const SizedBox(width: NeoSpacing.md),
              Expanded(
                child: _field(
                  controller: _streamId,
                  label: 'Stream ID',
                  hint: 'channel-1',
                  validator: _required,
                ),
              ),
            ]),
            const SizedBox(height: NeoSpacing.md),
            SegmentedButton<String>(
              segments: const <ButtonSegment<String>>[
                ButtonSegment(value: 'aes-256', label: Text('AES-256')),
                ButtonSegment(value: 'none', label: Text('No key')),
              ],
              selected: <String>{_encryptionMode},
              onSelectionChanged: (Set<String> value) =>
                  setState(() => _encryptionMode = value.first),
            ),
          ],
          const SizedBox(height: NeoSpacing.md),
          _numberField(
            controller: _inputTimeout,
            label: 'Input loss timeout (seconds)',
            min: 3,
            max: 300,
            helper: 'Marks the relay as degraded when multicast packets stop.',
          ),
          const SizedBox(height: NeoSpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: _numberField(
                  controller: _latency,
                  label: 'Latency (ms)',
                  min: 20,
                  max: 60000,
                ),
              ),
            ],
          ),
          const SizedBox(height: NeoSpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: _numberField(
                  controller: _payload,
                  label: 'Payload size',
                  min: 188,
                  max: 1456,
                  extra: (int value) =>
                      value % 188 == 0 ? null : 'Must be a multiple of 188.',
                ),
              ),
              if (_direction == 'listener')
                const SizedBox(width: NeoSpacing.md),
              if (_direction == 'listener')
                Expanded(
                  child: _numberField(
                    controller: _maxClients,
                    label: 'Max clients',
                    min: 1,
                    max: 1000,
                  ),
                ),
            ],
          ),
          const SizedBox(height: NeoSpacing.lg),
          DecoratedBox(
            decoration: BoxDecoration(
              color: NeoColors.blue.withValues(alpha: .06),
              border: Border.all(color: NeoColors.blue.withValues(alpha: .25)),
              borderRadius: BorderRadius.circular(NeoRadius.sm),
            ),
            child: Padding(
              padding: const EdgeInsets.all(NeoSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(Icons.security_outlined,
                      color: NeoColors.blue, size: 20),
                  const SizedBox(width: NeoSpacing.md),
                  Expanded(
                    child: Text(
                      _direction == 'publish'
                          ? 'NeoTranscoder initiates one connection to the partner listener.'
                          : 'Encryption keys and IP access are assigned per client.',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  TextFormField _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    String? helper,
    bool enabled = true,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        helperMaxLines: 2,
      ),
      validator: validator,
    );
  }

  TextFormField _numberField({
    required TextEditingController controller,
    required String label,
    required int min,
    required int max,
    String? Function(int)? extra,
    String? helper,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 2,
      ),
      validator: (String? value) {
        final int? number = int.tryParse(value ?? '');
        if (number == null || number < min || number > max) {
          return 'Use $min–$max.';
        }
        return extra?.call(number);
      },
    );
  }

  void _initialize(SrtRelay? relay) {
    _initialized = true;
    if (relay == null) {
      return;
    }
    _id.text = relay.id;
    _name.text = relay.name;
    _direction = relay.direction;
    _input.text = relay.inputUrl;
    _interface.text = relay.networkInterface;
    _bind.text = relay.bindAddress;
    _port.text = '${relay.port}';
    _destination.text = relay.destinationAddress;
    _destinationPort.text =
        '${relay.destinationPort == 0 ? 9000 : relay.destinationPort}';
    _streamId.text = relay.streamId;
    _encryptionMode = relay.encryptionMode;
    _latency.text = '${relay.latencyMs}';
    _payload.text = '${relay.payloadSize}';
    _maxClients.text = '${relay.maxClients}';
    _inputTimeout.text = '${relay.inputTimeoutSeconds}';
    _allowMissingStreamId = relay.allowMissingStreamId;
    _defaultClientId = relay.defaultClientId;
    _enabled = relay.enabled;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _saving = true);
    try {
      final SrtRelayView saved = await context.read<SrtCubit>().saveRelay(
            SrtRelay(
              id: _id.text.trim(),
              name: _name.text.trim(),
              direction: _direction,
              inputUrl: _input.text.trim(),
              networkInterface: _interface.text.trim(),
              bindAddress: _bind.text.trim(),
              port: int.parse(_port.text),
              destinationAddress: _destination.text.trim(),
              destinationPort: int.parse(_destinationPort.text),
              streamId: _streamId.text.trim(),
              encryptionMode: _encryptionMode,
              keyVersion: 1,
              latencyMs: int.parse(_latency.text),
              payloadSize: int.parse(_payload.text),
              maxClients: int.parse(_maxClients.text),
              inputTimeoutSeconds: int.parse(_inputTimeout.text),
              allowMissingStreamId:
                  _direction == 'listener' && _allowMissingStreamId,
              defaultClientId: _direction == 'listener' && _allowMissingStreamId
                  ? _defaultClientId
                  : '',
              enabled: _enabled,
            ),
            originalId: widget.relayId,
          );
      if (mounted && saved.passphrase.isNotEmpty) {
        await _showPublishCredential(saved);
      }
      if (mounted) {
        context.go(AppRoutes.srtRelays);
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

  Future<void> _showPublishCredential(SrtRelayView relay) => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) => AlertDialog(
          icon: const Icon(Icons.key_outlined, color: NeoColors.blue),
          title: const Text('SRT publish key'),
          content: SizedBox(
            width: 560,
            child: SelectableText(
              relay.passphrase,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
          actions: <Widget>[
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('I stored the key'),
            ),
          ],
        ),
      );

  String? _required(String? value) =>
      (value?.trim().isEmpty ?? true) ? 'This field is required.' : null;

  String? _idValidator(String? value) {
    final String id = value?.trim() ?? '';
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{2,63}$').hasMatch(id)) {
      return 'Use 3–64 letters, numbers, dots, underscores or hyphens.';
    }
    return null;
  }
}

class _EditorHeader extends StatelessWidget {
  const _EditorHeader({
    required this.title,
    required this.saving,
    required this.onCancel,
    required this.onSave,
  });

  final String title;
  final bool saving;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
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
              tooltip: 'Back to relays',
              onPressed: onCancel,
              icon: const Icon(Icons.arrow_back),
            ),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(width: NeoSpacing.xs),
            const SrtRelayGuideButton(),
          ],
        ),
        Wrap(
          spacing: NeoSpacing.md,
          children: <Widget>[
            NeoButton(
              label: 'Cancel',
              icon: Icons.close,
              onPressed: saving ? null : onCancel,
            ),
            NeoButton(
              label: saving ? 'Saving' : 'Save relay',
              icon: Icons.save_outlined,
              primary: true,
              onPressed: saving ? null : onSave,
            ),
          ],
        ),
      ],
    );
  }
}
