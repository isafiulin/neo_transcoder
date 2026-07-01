import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_routes.dart';
import '../../app/session_cubit.dart';
import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/state/load_status.dart';
import '../../core/widgets/neo_button.dart';
import '../../core/widgets/neo_panel.dart';
import '../../core/widgets/neo_state.dart';
import 'settings_cubit.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<bool> _action(Future<void> Function(SettingsCubit cubit) call) async {
    final SettingsCubit cubit = context.read<SettingsCubit>();
    try {
      await call(cubit);
      return true;
    } on Object catch (error) {
      _showError(error);
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (BuildContext context, SettingsState state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Settings', style: Theme.of(context).textTheme.titleLarge),
            if (AuthStore.mustChangePassword) ...<Widget>[
              const SizedBox(height: 12),
              NeoPanel(
                title: 'Password change required',
                child: Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text('The default admin password must be changed before using the system.'),
                    ),
                    NeoButton(
                      label: 'Change password',
                      icon: Icons.lock_reset,
                      primary: true,
                      onPressed: _openOwnPasswordDialog,
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            NeoPanel(
              title: 'Runtime',
              child: Wrap(
                spacing: 18,
                runSpacing: 12,
                children: const <Widget>[
                  _SettingValue(label: 'Config', value: '/etc/neotranscoder/config.json'),
                  _SettingValue(label: 'State', value: '/var/lib/neotranscoder/state.json'),
                  _SettingValue(label: 'Logs', value: 'journald + in-memory recent logs'),
                  _SettingValue(label: 'Service', value: 'neotranscoder.service'),
                ],
              ),
            ),
            const SizedBox(height: 18),
            NeoPanel(
              title: 'Users',
              trailing: NeoButton(
                label: 'New user',
                icon: Icons.person_add_alt,
                primary: true,
                onPressed: _openCreateUserDialog,
              ),
              child: _usersContent(state),
            ),
          ],
        );
      },
    );
  }

  Widget _usersContent(SettingsState state) {
    if (state.status == LoadStatus.loading || state.status == LoadStatus.initial) {
      return const NeoLoadingState(label: 'Loading users');
    }
    if (state.status == LoadStatus.failure) {
      return NeoErrorState(message: state.error, onRetry: context.read<SettingsCubit>().load);
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 38,
        columns: const <DataColumn>[
          DataColumn(label: Text('Username')),
          DataColumn(label: Text('Password state')),
          DataColumn(label: Text('Created')),
          DataColumn(label: Text('Actions')),
        ],
        rows: state.users.map(_userRow).toList(),
      ),
    );
  }

  DataRow _userRow(UserAccount user) {
    return DataRow(
      cells: <DataCell>[
        DataCell(Text(user.username)),
        DataCell(Text(user.mustChangePassword ? 'Must change' : 'Active')),
        DataCell(Text(user.createdAt)),
        DataCell(
          Row(
            children: <Widget>[
              NeoButton(
                label: 'Password',
                icon: Icons.lock_reset,
                onPressed: () => _openUserPasswordDialog(user),
              ),
              const SizedBox(width: 8),
              NeoButton(
                label: 'Delete',
                icon: Icons.delete_outline,
                onPressed: user.username == 'admin' ? null : () => _confirmDelete(user),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openOwnPasswordDialog() async {
    final _PasswordChange? value = await showDialog<_PasswordChange>(
      context: context,
      builder: (BuildContext context) => const _OwnPasswordDialog(),
    );
    if (value == null || !mounted) {
      return;
    }
    final bool changed = await _action((SettingsCubit cubit) => cubit.changePassword(value.currentPassword, value.newPassword));
    if (!mounted) {
      return;
    }
    if (changed) {
      context.read<SessionCubit>().logout();
      context.go(AppRoutes.login);
    }
  }

  Future<void> _openCreateUserDialog() async {
    final _UserPassword? value = await showDialog<_UserPassword>(
      context: context,
      builder: (BuildContext context) => const _UserPasswordDialog(title: 'New user'),
    );
    if (value == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    await _action((SettingsCubit cubit) => cubit.createUser(value.username, value.password));
  }

  Future<void> _openUserPasswordDialog(UserAccount user) async {
    final _UserPassword? value = await showDialog<_UserPassword>(
      context: context,
      builder: (BuildContext context) => _UserPasswordDialog(
        title: 'Change password',
        username: user.username,
      ),
    );
    if (value == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    await _action((SettingsCubit cubit) => cubit.changeUserPassword(value.username, value.password));
  }

  Future<void> _confirmDelete(UserAccount user) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Delete user'),
        content: Text('Delete ${user.username}?'),
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
      await _action((SettingsCubit cubit) => cubit.deleteUser(user.username));
    }
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

class _OwnPasswordDialog extends StatefulWidget {
  const _OwnPasswordDialog({super.key});

  @override
  State<_OwnPasswordDialog> createState() => _OwnPasswordDialogState();
}

class _OwnPasswordDialogState extends State<_OwnPasswordDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _current = TextEditingController();
  final TextEditingController _next = TextEditingController();

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change password'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _PasswordField(controller: _current, label: 'Current password'),
              _PasswordField(controller: _next, label: 'New password'),
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
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    Navigator.of(context).pop(_PasswordChange(_current.text, _next.text));
  }
}

class _UserPasswordDialog extends StatefulWidget {
  const _UserPasswordDialog({
    required this.title,
    this.username = '',
    super.key,
  });

  final String title;
  final String username;

  @override
  State<_UserPasswordDialog> createState() => _UserPasswordDialogState();
}

class _UserPasswordDialogState extends State<_UserPasswordDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();

  @override
  void initState() {
    super.initState();
    _username.text = widget.username;
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextFormField(
                controller: _username,
                enabled: widget.username.isEmpty,
                decoration: const InputDecoration(labelText: 'Username'),
                validator: _required,
              ),
              _PasswordField(controller: _password, label: 'Password'),
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
          child: const Text('Save'),
        ),
      ],
    );
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Required';
    }
    return null;
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    Navigator.of(context).pop(_UserPassword(_username.text.trim(), _password.text));
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    super.key,
  });

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        obscureText: true,
        decoration: InputDecoration(labelText: label),
        validator: (String? value) {
          if (value == null || value.length < 6) {
            return 'Minimum 6 characters';
          }
          return null;
        },
      ),
    );
  }
}

class _SettingValue extends StatelessWidget {
  const _SettingValue({
    required this.label,
    required this.value,
    super.key,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          SelectableText(value),
        ],
      ),
    );
  }
}

class _PasswordChange {
  const _PasswordChange(this.currentPassword, this.newPassword);

  final String currentPassword;
  final String newPassword;
}

class _UserPassword {
  const _UserPassword(this.username, this.password);

  final String username;
  final String password;
}
