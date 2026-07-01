import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/design_system/status.dart';
import '../../core/widgets/neo_badge.dart';
import '../../core/widgets/neo_button.dart';
import '../../core/widgets/neo_panel.dart';
import '../../core/widgets/neo_search_field.dart';
import '../../core/widgets/neo_state.dart';

class StreamsScreen extends StatefulWidget {
  const StreamsScreen({super.key});

  @override
  State<StreamsScreen> createState() => _StreamsScreenState();
}

class _StreamsScreenState extends State<StreamsScreen> {
  final ApiClient _api = ApiClient();
  List<StreamView> _streams = <StreamView>[];
  List<Profile> _profiles = <Profile>[];
  String _query = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final List<StreamView> streams = await _api.streams();
      final List<Profile> profiles = await _api.profiles();
      if (!mounted) {
        return;
      }
      setState(() {
        _streams = streams;
        _profiles = profiles;
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

  Future<void> _action(Future<void> Function() call) async {
    try {
      await call();
      await _load();
    } on Object catch (error) {
      _showError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<StreamView> streams = _streams.where(_matchesQuery).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text('Streams', style: Theme.of(context).textTheme.titleLarge),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                NeoSearchField(onChanged: (String value) => setState(() => _query = value)),
                NeoButton(
                  label: 'Probe',
                  icon: Icons.radar_outlined,
                  onPressed: _openProbeDialog,
                ),
                NeoButton(
                  label: 'New stream',
                  icon: Icons.add,
                  primary: true,
                  onPressed: () => _openStreamDialog(),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),
        NeoPanel(
          child: _content(streams),
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 38,
        columns: const <DataColumn>[
          DataColumn(label: Text('Name')),
          DataColumn(label: Text('Input')),
          DataColumn(label: Text('Output')),
          DataColumn(label: Text('Profile')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Actions')),
        ],
        rows: streams.map(_row).toList(),
      ),
    );
  }

  DataRow _row(StreamView item) {
    final StreamState state = item.state;
    return DataRow(
      cells: <DataCell>[
        DataCell(Text(item.config.name.isEmpty ? item.config.id : item.config.name)),
        DataCell(SizedBox(width: 260, child: Text(item.config.inputUrl, overflow: TextOverflow.ellipsis))),
        DataCell(SizedBox(width: 260, child: Text(item.config.outputUrl, overflow: TextOverflow.ellipsis))),
        DataCell(Text(item.config.profileName)),
        DataCell(NeoBadge(label: state.status, tone: streamTone(state.status, state.hasError))),
        DataCell(
          Row(
            children: <Widget>[
              NeoButton(
                label: 'Start',
                icon: Icons.play_arrow,
                onPressed: state.isRunning ? null : () => _action(() => _api.startStream(item.config.id)),
              ),
              const SizedBox(width: 8),
              NeoButton(
                label: 'Stop',
                icon: Icons.stop,
                onPressed: state.isRunning ? () => _action(() => _api.stopStream(item.config.id)) : null,
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                tooltip: 'More actions',
                onSelected: (String value) => _handleRowAction(value, item),
                itemBuilder: (BuildContext context) => const <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(value: 'restart', child: Text('Restart')),
                  PopupMenuItem<String>(value: 'edit', child: Text('Edit')),
                  PopupMenuItem<String>(value: 'command', child: Text('FFmpeg command')),
                  PopupMenuItem<String>(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleRowAction(String action, StreamView item) async {
    switch (action) {
      case 'restart':
        await _action(() => _api.restartStream(item.config.id));
        return;
      case 'edit':
        await _openStreamDialog(item: item);
        return;
      case 'command':
        await _openCommandDialog(item.config.id);
        return;
      case 'delete':
        await _confirmDelete(item);
        return;
    }
  }

  Future<void> _openStreamDialog({StreamView? item}) async {
    final Map<String, Object?>? body = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (BuildContext context) => _StreamDialog(
        profiles: _profiles,
        item: item,
      ),
    );
    if (body == null) {
      return;
    }
    try {
      if (item == null) {
        await _api.saveStream(body);
      } else {
        await _api.updateStream(item.config.id, body);
      }
      await _load();
    } on Object catch (error) {
      _showError(error);
    }
  }

  Future<void> _openCommandDialog(String id) async {
    late final CommandPreview preview;
    try {
      preview = await _api.command(id);
    } on Object catch (error) {
      _showError(error);
      return;
    }
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('FFmpeg command'),
        content: SizedBox(
          width: 760,
          child: SelectableText('${preview.path} ${preview.args.join(' ')}'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(StreamView item) async {
    final String label = item.config.name.isEmpty ? item.config.id : item.config.name;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Delete stream'),
        content: Text('Delete $label?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      try {
        await _api.deleteStream(item.config.id);
        await _load();
      } on Object catch (error) {
        _showError(error);
      }
    }
  }

  Future<void> _openProbeDialog() async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => _ProbeDialog(api: _api),
    );
  }

  bool _matchesQuery(StreamView item) {
    final String value = _query.trim().toLowerCase();
    if (value.isEmpty) {
      return true;
    }
    return item.config.name.toLowerCase().contains(value) ||
        item.config.id.toLowerCase().contains(value) ||
        item.config.profileName.toLowerCase().contains(value);
  }

  void _showError(Object error) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(apiErrorMessage(error))),
    );
  }
}

class _StreamDialog extends StatefulWidget {
  const _StreamDialog({
    required this.profiles,
    this.item,
    super.key,
  });

  final List<Profile> profiles;
  final StreamView? item;

  @override
  State<_StreamDialog> createState() => _StreamDialogState();
}

class _StreamDialogState extends State<_StreamDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _id = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  bool _enabled = true;
  String? _profile;

  @override
  void initState() {
    super.initState();
    final StreamView? item = widget.item;
    _id.text = item?.config.id ?? '';
    _name.text = item?.config.name ?? '';
    _input.text = item?.config.inputUrl ?? '';
    _output.text = item?.config.outputUrl ?? '';
    _enabled = item?.config.enabled ?? true;
    _profile = item?.config.profileName ?? (widget.profiles.isEmpty ? null : widget.profiles.first.name);
  }

  @override
  void dispose() {
    _id.dispose();
    _name.dispose();
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.item == null ? 'New stream' : 'Edit stream'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _Field(controller: _id, label: 'ID', enabled: widget.item == null),
              _Field(controller: _name, label: 'Name'),
              _Field(controller: _input, label: 'Input URL'),
              _Field(controller: _output, label: 'Output URL'),
              DropdownButtonFormField<String>(
                value: _profile,
                decoration: const InputDecoration(labelText: 'Profile'),
                items: widget.profiles
                    .map(
                      (Profile profile) => DropdownMenuItem<String>(
                        value: profile.name,
                        child: Text(profile.name),
                      ),
                    )
                    .toList(),
                onChanged: (String? value) => setState(() => _profile = value),
              ),
              CheckboxListTile(
                value: _enabled,
                contentPadding: EdgeInsets.zero,
                title: const Text('Enabled'),
                onChanged: (bool? value) => setState(() => _enabled = value ?? false),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: Text(widget.item == null ? 'Create' : 'Save'),
        ),
      ],
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false) || _profile == null) {
      return;
    }
    Navigator.of(context).pop(<String, Object?>{
      'id': _id.text.trim(),
      'name': _name.text.trim(),
      'input_url': _input.text.trim(),
      'output_url': _output.text.trim(),
      'profile_name': _profile,
      'enabled': _enabled,
    });
  }
}

class _ProbeDialog extends StatefulWidget {
  const _ProbeDialog({
    required this.api,
    super.key,
  });

  final ApiClient api;

  @override
  State<_ProbeDialog> createState() => _ProbeDialogState();
}

class _ProbeDialogState extends State<_ProbeDialog> {
  final TextEditingController _input = TextEditingController();
  ProbeResult? _result;
  bool _loading = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ProbeResult? result = _result;
    return AlertDialog(
      title: const Text('Probe stream'),
      content: SizedBox(
        width: 760,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _input,
              decoration: const InputDecoration(labelText: 'Input URL'),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const LinearProgressIndicator()
            else if (result != null)
              _ProbeResultView(result: result),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _probe,
          child: const Text('Probe'),
        ),
      ],
    );
  }

  Future<void> _probe() async {
    setState(() => _loading = true);
    try {
      final ProbeResult result = await widget.api.probe(_input.text.trim());
      if (!mounted) {
        return;
      }
      setState(() {
        _result = result;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(error))),
      );
    }
  }
}

class _ProbeResultView extends StatelessWidget {
  const _ProbeResultView({
    required this.result,
    super.key,
  });

  final ProbeResult result;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Format: ${result.formatName} · Bitrate: ${result.bitRate.isEmpty ? '-' : result.bitRate}'),
        const SizedBox(height: 8),
        DataTable(
          columns: const <DataColumn>[
            DataColumn(label: Text('Index')),
            DataColumn(label: Text('Type')),
            DataColumn(label: Text('Codec')),
            DataColumn(label: Text('Size')),
            DataColumn(label: Text('FPS')),
          ],
          rows: result.streams
              .map(
                (ProbeStream item) => DataRow(
                  cells: <DataCell>[
                    DataCell(Text('${item.index}')),
                    DataCell(Text(item.codecType)),
                    DataCell(Text(item.codecName)),
                    DataCell(Text(item.width == 0 ? '-' : '${item.width}x${item.height}')),
                    DataCell(Text(item.avgFrameRate.isEmpty ? '-' : item.avgFrameRate)),
                  ],
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.enabled = true,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        decoration: InputDecoration(labelText: label),
        validator: (String? value) {
          if (value == null || value.trim().isEmpty) {
            return 'Required';
          }
          return null;
        },
      ),
    );
  }
}
