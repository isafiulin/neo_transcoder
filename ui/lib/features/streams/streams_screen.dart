import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:neotranscoder_ui/core/api/api_client.dart';
import 'package:neotranscoder_ui/core/api/models.dart';
import 'package:neotranscoder_ui/core/design_system/status.dart';
import 'package:neotranscoder_ui/core/state/load_status.dart';
import 'package:neotranscoder_ui/core/widgets/neo_badge.dart';
import 'package:neotranscoder_ui/core/widgets/neo_button.dart';
import 'package:neotranscoder_ui/core/widgets/neo_panel.dart';
import 'package:neotranscoder_ui/core/widgets/neo_search_field.dart';
import 'package:neotranscoder_ui/core/widgets/neo_state.dart';
import 'streams_cubit.dart';

class StreamsScreen extends StatefulWidget {
  const StreamsScreen({super.key});

  @override
  State<StreamsScreen> createState() => _StreamsScreenState();
}

class _StreamsScreenState extends State<StreamsScreen> {
  Future<void> _action(Future<void> Function() call) async {
    try {
      await call();
    } on Object catch (error) {
      _showError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<StreamsCubit, StreamsState>(
      builder: (BuildContext context, StreamsState state) {
        final List<StreamView> streams = state.filtered;
        return Column(
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
                    NeoSearchField(
                        onChanged: context.read<StreamsCubit>().setQuery),
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
              child: _content(state, streams),
            ),
          ],
        );
      },
    );
  }

  Widget _content(StreamsState state, List<StreamView> streams) {
    final String? error = state.error.isEmpty ? null : state.error;
    if (state.status == LoadStatus.loading ||
        state.status == LoadStatus.initial) {
      return const NeoLoadingState(label: 'Loading streams');
    }
    if (error != null) {
      return NeoErrorState(
          message: error, onRetry: context.read<StreamsCubit>().load);
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
        DataCell(
            Text(item.config.name.isEmpty ? item.config.id : item.config.name)),
        DataCell(SizedBox(
            width: 260,
            child:
                Text(item.config.inputUrl, overflow: TextOverflow.ellipsis))),
        DataCell(SizedBox(
            width: 260,
            child:
                Text(item.config.outputUrl, overflow: TextOverflow.ellipsis))),
        DataCell(Text(item.config.profileName)),
        DataCell(NeoBadge(
            label: state.status,
            tone: streamTone(state.status, state.hasError))),
        DataCell(
          Row(
            children: <Widget>[
              NeoButton(
                label: 'Start',
                icon: Icons.play_arrow,
                onPressed: state.isRunning
                    ? null
                    : () => _action(() =>
                        context.read<StreamsCubit>().start(item.config.id)),
              ),
              const SizedBox(width: 8),
              NeoButton(
                label: 'Stop',
                icon: Icons.stop,
                onPressed: state.isRunning
                    ? () => _action(
                        () => context.read<StreamsCubit>().stop(item.config.id))
                    : null,
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                tooltip: 'More actions',
                onSelected: (String value) => _handleRowAction(value, item),
                itemBuilder: (BuildContext context) =>
                    const <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                      value: 'restart', child: Text('Restart')),
                  PopupMenuItem<String>(value: 'edit', child: Text('Edit')),
                  PopupMenuItem<String>(
                      value: 'command', child: Text('FFmpeg command')),
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
        await _action(
            () => context.read<StreamsCubit>().restart(item.config.id));
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
    final StreamsCubit cubit = context.read<StreamsCubit>();
    final Map<String, Object?>? body = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (BuildContext context) => _StreamDialog(
        cubit: cubit,
        profiles: cubit.state.profiles,
        item: item,
      ),
    );
    if (body == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    try {
      if (item == null) {
        await cubit.saveStream(body);
      } else {
        await cubit.saveStream(body, id: item.config.id);
      }
    } on Object catch (error) {
      _showError(error);
    }
  }

  Future<void> _openCommandDialog(String id) async {
    final CommandPreview preview;
    try {
      preview = await context.read<StreamsCubit>().command(id);
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
          child: SelectableText(
              '${_shellQuote(preview.path)} ${preview.args.map(_shellQuote).join(' ')}'),
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
    final StreamsCubit cubit = context.read<StreamsCubit>();
    final String label =
        item.config.name.isEmpty ? item.config.id : item.config.name;
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
    if (!mounted) {
      return;
    }
    if (confirmed ?? false) {
      try {
        await cubit.deleteStream(item.config.id);
      } on Object catch (error) {
        _showError(error);
      }
    }
  }

  Future<void> _openProbeDialog() async {
    final StreamsCubit cubit = context.read<StreamsCubit>();
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => _ProbeDialog(cubit: cubit),
    );
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
    required this.cubit,
    required this.profiles,
    this.item,
  });

  final StreamsCubit cubit;
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
  final TextEditingController _audioMaps = TextEditingController();
  final TextEditingController _logoPath = TextEditingController();
  final TextEditingController _logoX = TextEditingController(text: '0');
  final TextEditingController _logoY = TextEditingController(text: '0');
  final TextEditingController _options = TextEditingController();
  final TextEditingController _logRetention = TextEditingController(text: '60');
  String _logLevel = '';
  bool _keepStats = false;
  bool _enabled = true;
  bool _disableAudio = false;
  bool _logoEnabled = false;
  bool _probingAudio = false;
  String _audioProbeError = '';
  List<ProbeStream> _audioTracks = <ProbeStream>[];
  String _sourceType = 'multicast';
  String? _profile;

  @override
  void initState() {
    super.initState();
    final StreamView? item = widget.item;
    _id.text = item?.config.id ?? '';
    _name.text = item?.config.name ?? '';
    _input.text = item?.config.inputUrl ?? '';
    _output.text = item?.config.outputUrl ?? '';
    _sourceType = item?.config.sourceType ?? 'multicast';
    _audioMaps.text = item?.config.audioMaps.join('\n') ?? '';
    _disableAudio = item?.config.disableAudio ?? false;
    _logoEnabled = item?.config.logo.enabled ?? false;
    _logoPath.text = item?.config.logo.path ?? '';
    _logoX.text = '${item?.config.logo.x ?? 0}';
    _logoY.text = '${item?.config.logo.y ?? 0}';
    _options.text =
        _encodeKeyValues(item?.config.options ?? <String, String>{});
    _logRetention.text = '${item?.config.logRetentionSeconds ?? 60}';
    _logLevel = item?.config.logLevel ?? '';
    _keepStats = item?.config.keepStats ?? false;
    _enabled = item?.config.enabled ?? true;
    _profile = item?.config.profileName ??
        (widget.profiles.isEmpty ? null : widget.profiles.first.name);
  }

  @override
  void dispose() {
    _id.dispose();
    _name.dispose();
    _input.dispose();
    _output.dispose();
    _audioMaps.dispose();
    _logoPath.dispose();
    _logoX.dispose();
    _logoY.dispose();
    _options.dispose();
    _logRetention.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.item == null ? 'New stream' : 'Edit stream'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _Field(
                    controller: _id, label: 'ID', enabled: widget.item == null),
                _Field(controller: _name, label: 'Name'),
                SegmentedButton<String>(
                  segments: const <ButtonSegment<String>>[
                    ButtonSegment<String>(
                      value: 'multicast',
                      icon: Icon(Icons.settings_input_antenna),
                      label: Text('Multicast'),
                    ),
                    ButtonSegment<String>(
                      value: 'file',
                      icon: Icon(Icons.video_file_outlined),
                      label: Text('File'),
                    ),
                  ],
                  selected: <String>{_sourceType},
                  onSelectionChanged: (Set<String> value) =>
                      setState(() => _sourceType = value.first),
                ),
                const SizedBox(height: 12),
                _Field(
                    controller: _input,
                    label: _sourceType == 'file'
                        ? 'Input file path'
                        : 'Input multicast URL'),
                _Field(controller: _output, label: 'Output URL'),
                _Field(
                    controller: _logRetention, label: 'Log retention seconds'),
                DropdownButtonFormField<String>(
                  initialValue: _logLevel,
                  decoration: const InputDecoration(
                    labelText: 'Log level',
                    helperText:
                        'Default follows the system setting (warning). Set to '
                        'info temporarily to see full ffmpeg detail for this '
                        'stream while debugging - takes effect on next '
                        'start/restart.',
                  ),
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem<String>(value: '', child: Text('Default')),
                    DropdownMenuItem<String>(
                        value: 'info', child: Text('Info (detailed)')),
                    DropdownMenuItem<String>(
                        value: 'warning', child: Text('Warning')),
                    DropdownMenuItem<String>(
                        value: 'error', child: Text('Error only')),
                  ],
                  onChanged: (String? value) =>
                      setState(() => _logLevel = value ?? ''),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _profile,
                  decoration: const InputDecoration(labelText: 'Profile'),
                  items: widget.profiles
                      .map(
                        (Profile profile) => DropdownMenuItem<String>(
                          value: profile.name,
                          child: Text(profile.name),
                        ),
                      )
                      .toList(),
                  onChanged: (String? value) =>
                      setState(() => _profile = value),
                ),
                CheckboxListTile(
                  value: _enabled,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enabled'),
                  onChanged: (bool? value) =>
                      setState(() => _enabled = value ?? false),
                ),
                CheckboxListTile(
                  value: _keepStats,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Keep FFmpeg console stats (-stats)'),
                  subtitle: const Text(
                      'Off by default (-nostats). Turning this on lets ffmpeg '
                      'print its own periodic stats line to stderr as well as '
                      '-progress pipe:1. Safe to leave on - the stats line '
                      'itself is not stored in the stream log.'),
                  onChanged: (bool? value) =>
                      setState(() => _keepStats = value ?? false),
                ),
                CheckboxListTile(
                  value: _disableAudio,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Remove audio'),
                  onChanged: (bool? value) =>
                      setState(() => _disableAudio = value ?? false),
                ),
                if (!_disableAudio)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      TextFormField(
                        controller: _audioMaps,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Audio maps',
                          helperText:
                              'Probe input and select audio tracks, or enter maps manually.',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: NeoButton(
                          label: 'Probe audio tracks',
                          icon: Icons.manage_search,
                          onPressed: _probingAudio ? null : _probeAudioTracks,
                        ),
                      ),
                      if (_probingAudio) ...<Widget>[
                        const SizedBox(height: 8),
                        const LinearProgressIndicator(),
                      ],
                      if (_audioProbeError.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 8),
                        Text(
                          _audioProbeError,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error),
                        ),
                      ],
                      if (_audioTracks.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 8),
                        for (int index = 0;
                            index < _audioTracks.length;
                            index++)
                          _AudioTrackTile(
                            stream: _audioTracks[index],
                            map: _audioMapFor(index),
                            selected: _selectedAudioMaps()
                                .contains(_audioMapFor(index)),
                            onChanged: (bool selected) =>
                                _setAudioMap(_audioMapFor(index), selected),
                          ),
                      ],
                      const SizedBox(height: 12),
                    ],
                  ),
                CheckboxListTile(
                  value: _logoEnabled,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Add logo overlay'),
                  onChanged: (bool? value) =>
                      setState(() => _logoEnabled = value ?? false),
                ),
                if (_logoEnabled) ...<Widget>[
                  _Field(controller: _logoPath, label: 'Logo file path'),
                  Row(
                    children: <Widget>[
                      Expanded(
                          child: _Field(controller: _logoX, label: 'Logo X')),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _Field(controller: _logoY, label: 'Logo Y')),
                    ],
                  ),
                ],
                TextFormField(
                  controller: _options,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Profile options',
                    helperText:
                        'One key=value per line. Values override template defaults.',
                  ),
                ),
              ],
            ),
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
    final int retention = int.tryParse(_logRetention.text.trim()) ?? 60;
    Navigator.of(context).pop(<String, Object?>{
      'id': _id.text.trim(),
      'name': _name.text.trim(),
      'input_url': _input.text.trim(),
      'output_url': _output.text.trim(),
      'source_type': _sourceType,
      'profile_name': _profile,
      'audio_maps': _disableAudio ? <String>[] : _lines(_audioMaps.text),
      'disable_audio': _disableAudio,
      'logo': <String, Object?>{
        'enabled': _logoEnabled,
        'path': _logoPath.text.trim(),
        'x': int.tryParse(_logoX.text.trim()) ?? 0,
        'y': int.tryParse(_logoY.text.trim()) ?? 0,
      },
      'options': _parseKeyValues(_options.text),
      'log_retention_seconds': retention,
      'log_level': _logLevel,
      'keep_stats': _keepStats,
      'enabled': _enabled,
    });
  }

  Future<void> _probeAudioTracks() async {
    final String input = _input.text.trim();
    if (input.isEmpty) {
      setState(() => _audioProbeError = 'Input is required before probe.');
      return;
    }
    setState(() {
      _probingAudio = true;
      _audioProbeError = '';
    });
    try {
      final ProbeResult result = await widget.cubit.probe(input);
      if (!mounted) {
        return;
      }
      final List<ProbeStream> audioTracks = result.streams
          .where((ProbeStream item) => item.codecType == 'audio')
          .toList();
      setState(() {
        _audioTracks = audioTracks;
        _probingAudio = false;
        _audioProbeError = audioTracks.isEmpty ? 'No audio tracks found.' : '';
        if (_audioMaps.text.trim().isEmpty && audioTracks.isNotEmpty) {
          _audioMaps.text =
              List<String>.generate(audioTracks.length, _audioMapFor)
                  .join('\n');
        }
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _probingAudio = false;
        _audioProbeError = apiErrorMessage(error);
      });
    }
  }

  Set<String> _selectedAudioMaps() => _lines(_audioMaps.text).toSet();

  String _audioMapFor(int audioIndex) => '0:a:$audioIndex';

  void _setAudioMap(String map, bool selected) {
    final Set<String> maps = _selectedAudioMaps();
    if (selected) {
      maps.add(map);
    } else {
      maps.remove(map);
    }
    final List<String> ordered = <String>[];
    for (int index = 0; index < _audioTracks.length; index++) {
      final String trackMap = _audioMapFor(index);
      if (maps.remove(trackMap)) {
        ordered.add(trackMap);
      }
    }
    final List<String> remainingMaps = maps.toList()..sort();
    ordered.addAll(remainingMaps);
    setState(() => _audioMaps.text = ordered.join('\n'));
  }
}

class _AudioTrackTile extends StatelessWidget {
  const _AudioTrackTile({
    required this.stream,
    required this.map,
    required this.selected,
    required this.onChanged,
  });

  final ProbeStream stream;
  final String map;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final String bitrate = stream.bitRate.isEmpty ? '-' : stream.bitRate;
    final String language = stream.tags['language'] ?? '-';
    final String layout = stream.channelLayout.isEmpty
        ? (stream.channels == 0 ? '-' : '${stream.channels} ch')
        : stream.channelLayout;
    return CheckboxListTile(
      value: selected,
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
          '$map · ${stream.codecName.isEmpty ? 'unknown' : stream.codecName}'),
      subtitle: Text(
          'Stream index ${stream.index} · language $language · $layout · bitrate $bitrate'),
      onChanged: (bool? value) => onChanged(value ?? false),
    );
  }
}

List<String> _lines(String value) {
  return value
      .split('\n')
      .map((String item) => item.trim())
      .where((String item) => item.isNotEmpty)
      .toList();
}

Map<String, String> _parseKeyValues(String value) {
  final Map<String, String> out = <String, String>{};
  for (final String line in value.split('\n')) {
    final String trimmed = line.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final int index = trimmed.indexOf('=');
    if (index <= 0) {
      continue;
    }
    out[trimmed.substring(0, index).trim()] =
        trimmed.substring(index + 1).trim();
  }
  return out;
}

String _encodeKeyValues(Map<String, String> values) {
  final List<String> keys = values.keys.toList()..sort();
  return keys.map((String key) => '$key=${values[key]}').join('\n');
}

class _ProbeDialog extends StatefulWidget {
  const _ProbeDialog({
    required this.cubit,
  });

  final StreamsCubit cubit;

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
      final ProbeResult result = await widget.cubit.probe(_input.text.trim());
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
  });

  final ProbeResult result;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
            'Format: ${result.formatName} · Bitrate: ${result.bitRate.isEmpty ? '-' : result.bitRate}'),
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
                    DataCell(Text(item.width == 0
                        ? '-'
                        : '${item.width}x${item.height}')),
                    DataCell(Text(
                        item.avgFrameRate.isEmpty ? '-' : item.avgFrameRate)),
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

final RegExp _shellSafePattern = RegExp(r'^[A-Za-z0-9_./:=+@-]+$');

/// Quotes an arg for display only (the real process is started via
/// exec.Command with a []string, never a shell string - see jobs.go). URLs
/// with "?"/"&" or anything else outside a conservative safe set get
/// double-quoted so a copy-pasted command line doesn't misparse "&" as
/// backgrounding or otherwise get mangled by the shell.
String _shellQuote(String arg) {
  if (arg.isNotEmpty && _shellSafePattern.hasMatch(arg)) {
    return arg;
  }
  final String escaped = arg.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  return '"$escaped"';
}
