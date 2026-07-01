import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../api/api_client.dart';

class AppShell extends StatelessWidget {
  const AppShell({
    required this.location,
    required this.child,
    super.key,
  });

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool wide = constraints.maxWidth >= 980;
        if (wide) {
          return Scaffold(
            body: Row(
              children: <Widget>[
                _SideNav(location: location),
                Expanded(child: _ContentFrame(child: child)),
              ],
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: const _BrandHeader(compact: true),
          ),
          drawer: Drawer(child: _SideNav(location: location)),
          body: _ContentFrame(child: child),
        );
      },
    );
  }
}

class _ContentFrame extends StatelessWidget {
  const _ContentFrame({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        if (MediaQuery.sizeOf(context).width >= 980)
          const _TopBar(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(NeoSpacing.xl),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1440),
                child: child,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: NeoColors.surface,
        border: Border(
          bottom: BorderSide(color: NeoColors.line),
        ),
      ),
      child: SizedBox(
        height: 64,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: NeoSpacing.xl),
          child: Row(
            children: <Widget>[
              const Spacer(),
              const Icon(Icons.cloud_done_outlined, color: NeoColors.success, size: 18),
              const SizedBox(width: NeoSpacing.sm),
              Text('API connected', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(width: NeoSpacing.lg),
              IconButton(
                tooltip: 'Logout',
                onPressed: () {
                  AuthStore.clear();
                  context.go('/login');
                },
                icon: const Icon(Icons.logout, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SideNav extends StatelessWidget {
  const _SideNav({
    required this.location,
    super.key,
  });

  final String location;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: NeoColors.surface,
      child: SizedBox(
        width: 248,
        child: _SideNavContent(location: location),
      ),
    );
  }
}

class _SideNavContent extends StatelessWidget {
  const _SideNavContent({
    required this.location,
    super.key,
  });

  final String location;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 22),
            child: _BrandHeader(),
          ),
          _NavItem(
            icon: Icons.dashboard_outlined,
            label: 'Dashboard',
            path: '/',
            selected: location == '/',
          ),
          _NavItem(
            icon: Icons.stream_outlined,
            label: 'Streams',
            path: '/streams',
            selected: location == '/streams',
          ),
          _NavItem(
            icon: Icons.tune_outlined,
            label: 'Profiles',
            path: '/profiles',
            selected: location == '/profiles',
          ),
          _NavItem(
            icon: Icons.article_outlined,
            label: 'Logs',
            path: '/logs',
            selected: location == '/logs',
          ),
          _NavItem(
            icon: Icons.settings_outlined,
            label: 'Settings',
            path: '/settings',
            selected: location == '/settings',
          ),
          _NavItem(
            icon: Icons.logout,
            label: 'Logout',
            path: '/login',
            selected: false,
            onTap: () {
              AuthStore.clear();
              context.go('/login');
            },
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(NeoSpacing.lg),
            child: Text(
              'NeoTranscoder',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({this.compact = false, super.key});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Image.asset(
          'assets/brand/neotelecom-logo.png',
          width: compact ? 132 : 176,
          fit: BoxFit.contain,
        ),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.path,
    required this.selected,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final String path;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = selected ? NeoColors.blueDark : NeoColors.muted;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: NeoSpacing.md, vertical: 3),
      child: Material(
        color: selected ? NeoColors.blue.withOpacity(0.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(NeoRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(NeoRadius.md),
          onTap: () {
            final VoidCallback? onTap = this.onTap;
            if (onTap == null) {
              context.go(path);
            } else {
              onTap();
            }
            if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
              Navigator.of(context).pop();
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: <Widget>[
                Icon(icon, color: color, size: 20),
                const SizedBox(width: NeoSpacing.md),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
