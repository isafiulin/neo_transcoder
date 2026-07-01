import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/widgets/neo_button.dart';
import '../../core/widgets/neo_panel.dart';
import '../../core/widgets/neo_search_field.dart';
import '../../core/widgets/neo_state.dart';

class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({super.key});

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  final ApiClient _api = ApiClient();
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
      final List<Profile> profiles = await _api.profiles();
      if (!mounted) {
        return;
      }
      setState(() {
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

  @override
  Widget build(BuildContext context) {
    final List<Profile> profiles = _profiles.where(_matchesQuery).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text('Profiles', style: Theme.of(context).textTheme.titleLarge),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                NeoSearchField(
                  onChanged: (String value) => setState(() => _query = value),
                  hintText: 'Filter profiles',
                ),
                NeoButton(
                  label: 'New profile',
                  icon: Icons.add,
                  onPressed: () => _openProfileDialog(),
                  primary: true,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),
        NeoPanel(
          child: _content(profiles),
        ),
      ],
    );
  }

  Widget _content(List<Profile> profiles) {
    final String? error = _error;
    if (_loading) {
      return const NeoLoadingState(label: 'Loading profiles');
    }
    if (error != null) {
      return NeoErrorState(message: error, onRetry: _load);
    }
    if (profiles.isEmpty) {
      return const NeoEmptyState(
        title: 'No profiles',
        message: 'Create a profile or adjust the filter.',
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 38,
        columns: const <DataColumn>[
          DataColumn(label: Text('Name')),
          DataColumn(label: Text('Video')),
          DataColumn(label: Text('Bitrate')),
          DataColumn(label: Text('Audio')),
          DataColumn(label: Text('Output')),
          DataColumn(label: Text('Actions')),
        ],
        rows: profiles.map(_row).toList(),
      ),
    );
  }

  DataRow _row(Profile profile) {
    return DataRow(
      cells: <DataCell>[
        DataCell(Text(profile.name)),
        DataCell(Text(profile.videoCodec)),
        DataCell(Text(profile.videoBitrate.isEmpty ? '-' : profile.videoBitrate)),
        DataCell(Text(profile.audioCodec)),
        DataCell(Text(profile.outputFormat)),
        DataCell(
          PopupMenuButton<String>(
            tooltip: 'Profile actions',
            onSelected: (String value) => _handleAction(value, profile),
            itemBuilder: (BuildContext context) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(value: 'edit', child: Text('Edit')),
              PopupMenuItem<String>(value: 'delete', child: Text('Delete')),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleAction(String action, Profile profile) async {
    switch (action) {
      case 'edit':
        await _openProfileDialog(profile: profile);
        return;
      case 'delete':
        await _confirmDelete(profile);
        return;
    }
  }

  Future<void> _openProfileDialog({Profile? profile}) async {
    final Map<String, Object?>? body = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (BuildContext context) => _ProfileDialog(profile: profile),
    );
    if (body == null) {
      return;
    }
    try {
      if (profile == null) {
        await _api.saveProfile(body);
      } else {
        await _api.updateProfile(profile.name, body);
      }
      await _load();
    } on Object catch (error) {
      _showError(error);
    }
  }

  Future<void> _confirmDelete(Profile profile) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Delete profile'),
        content: Text('Delete ${profile.name}? Streams using this profile must be changed first.'),
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
        await _api.deleteProfile(profile.name);
        await _load();
      } on Object catch (error) {
        _showError(error);
      }
    }
  }

  bool _matchesQuery(Profile profile) {
    final String value = _query.trim().toLowerCase();
    if (value.isEmpty) {
      return true;
    }
    return profile.name.toLowerCase().contains(value) ||
        profile.videoCodec.toLowerCase().contains(value) ||
        profile.audioCodec.toLowerCase().contains(value);
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

class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog({
    this.profile,
    super.key,
  });

  final Profile? profile;

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _videoCodec = TextEditingController(text: 'libx264');
  final TextEditingController _preset = TextEditingController(text: 'veryfast');
  final TextEditingController _tune = TextEditingController(text: 'zerolatency');
  final TextEditingController _videoBitrate = TextEditingController(text: '4000k');
  final TextEditingController _maxrate = TextEditingController(text: '4000k');
  final TextEditingController _bufsize = TextEditingController(text: '8000k');
  final TextEditingController _audioCodec = TextEditingController(text: 'aac');
  final TextEditingController _audioBitrate = TextEditingController(text: '128k');
  final TextEditingController _format = TextEditingController(text: 'mpegts');

  @override
  void initState() {
    super.initState();
    final Profile? profile = widget.profile;
    if (profile == null) {
      return;
    }
    _name.text = profile.name;
    _videoCodec.text = profile.videoCodec;
    _preset.text = profile.videoPreset;
    _tune.text = profile.videoTune;
    _videoBitrate.text = profile.videoBitrate;
    _maxrate.text = profile.videoMaxrate;
    _bufsize.text = profile.videoBufsize;
    _audioCodec.text = profile.audioCodec;
    _audioBitrate.text = profile.audioBitrate;
    _format.text = profile.outputFormat;
  }

  @override
  void dispose() {
    _name.dispose();
    _videoCodec.dispose();
    _preset.dispose();
    _tune.dispose();
    _videoBitrate.dispose();
    _maxrate.dispose();
    _bufsize.dispose();
    _audioCodec.dispose();
    _audioBitrate.dispose();
    _format.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.profile == null ? 'New profile' : 'Edit profile'),
      content: SizedBox(
        width: 680,
        child: Form(
          key: _formKey,
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              _Field(controller: _name, label: 'Name', enabled: widget.profile == null),
              _Field(controller: _videoCodec, label: 'Video codec'),
              _Field(controller: _preset, label: 'Preset'),
              _Field(controller: _tune, label: 'Tune'),
              _Field(controller: _videoBitrate, label: 'Video bitrate'),
              _Field(controller: _maxrate, label: 'Maxrate'),
              _Field(controller: _bufsize, label: 'Bufsize'),
              _Field(controller: _audioCodec, label: 'Audio codec'),
              _Field(controller: _audioBitrate, label: 'Audio bitrate'),
              _Field(controller: _format, label: 'Output format'),
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
          child: Text(widget.profile == null ? 'Create' : 'Save'),
        ),
      ],
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    Navigator.of(context).pop(<String, Object?>{
      'name': _name.text.trim(),
      'video': <String, Object?>{
        'codec': _videoCodec.text.trim(),
        'preset': _preset.text.trim(),
        'tune': _tune.text.trim(),
        'bitrate': _videoBitrate.text.trim(),
        'maxrate': _maxrate.text.trim(),
        'bufsize': _bufsize.text.trim(),
      },
      'audio': <String, Object?>{
        'codec': _audioCodec.text.trim(),
        'bitrate': _audioBitrate.text.trim(),
      },
      'output': <String, Object?>{
        'format': _format.text.trim(),
      },
    });
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
    return SizedBox(
      width: 210,
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
