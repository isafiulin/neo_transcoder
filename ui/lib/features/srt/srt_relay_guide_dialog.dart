import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:neotranscoder_ui/app/theme.dart';
import 'package:neotranscoder_ui/core/widgets/neo_button.dart';

class SrtRelayGuideButton extends StatelessWidget {
  const SrtRelayGuideButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const Key('srt-relay-guide-button'),
      tooltip: 'Relay setup guide',
      onPressed: () => showDialog<void>(
        context: context,
        builder: (BuildContext context) => const SrtRelayGuideDialog(),
      ),
      icon: const Icon(Icons.info_outline),
    );
  }
}

class SrtRelayGuideDialog extends StatelessWidget {
  const SrtRelayGuideDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final Size screen = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(NeoSpacing.lg),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 760,
          maxHeight: screen.height * .88,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NeoSpacing.xl,
                NeoSpacing.lg,
                NeoSpacing.md,
                NeoSpacing.lg,
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.info_outline, color: NeoColors.blue),
                  const SizedBox(width: NeoSpacing.md),
                  Expanded(
                    child: Text(
                      'SRT relay setup',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close guide',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            const Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(NeoSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      'A relay forwards UDP multicast MPEG-TS unchanged. '
                      'Publish mode calls a partner listener; Accept mode '
                      'listens for authenticated partner callers.',
                    ),
                    SizedBox(height: NeoSpacing.xl),
                    _GuideSection(
                      icon: Icons.input_outlined,
                      title: '1. Select the multicast source',
                      body:
                          'Enter the multicast group and UDP port. Select the '
                          'Linux interface that receives the group when the '
                          'server has multiple network interfaces.',
                      examples: <_GuideExample>[
                        _GuideExample(
                          label: 'Multicast input',
                          value: 'udp://239.10.10.1:1234',
                        ),
                        _GuideExample(
                          label: 'Network interface',
                          value: 'eno1',
                        ),
                        _GuideExample(
                          label: 'Check multicast membership',
                          value: 'ip maddr show dev eno1',
                        ),
                      ],
                    ),
                    SizedBox(height: NeoSpacing.xl),
                    _GuideSection(
                      icon: Icons.cell_tower_outlined,
                      title: '2. Choose the SRT direction',
                      body:
                          'For normal partner delivery choose Publish and enter '
                          'the partner public IP and UDP port. Choose Accept only '
                          'when partners must initiate connections to this server.',
                      examples: <_GuideExample>[
                        _GuideExample(
                          label: 'Publish to partner (NeoTranscoder is Caller)',
                          value:
                              'Destination 203.0.113.50  •  UDP 9000  •  Stream ID channel-1',
                        ),
                        _GuideExample(
                          label: 'Accept partners (NeoTranscoder is Listener)',
                          value: 'Bind 0.0.0.0  •  UDP 9000  •  Latency 800 ms',
                        ),
                        _GuideExample(
                          label: 'firewalld',
                          value:
                              'firewall-cmd --permanent --add-port=9000/udp && firewall-cmd --reload',
                        ),
                      ],
                    ),
                    SizedBox(height: NeoSpacing.xl),
                    _GuideSection(
                      icon: Icons.key_outlined,
                      title: '3. Create an access client',
                      body: 'Save the relay, open Access clients, assign this '
                          'relay, and add the caller public IP or CIDR. Use '
                          'AES-256 when the receiver supports a passphrase. IP '
                          'ACL only is available for legacy receivers.',
                      examples: <_GuideExample>[
                        _GuideExample(
                          label: 'Single caller IP',
                          value: '203.0.113.10/32',
                        ),
                        _GuideExample(
                          label: 'Partner network',
                          value: '198.51.100.0/24',
                        ),
                        _GuideExample(
                          label: 'Security modes',
                          value: 'AES-256 + IP ACL  |  IP ACL only (no key)',
                        ),
                      ],
                    ),
                    SizedBox(height: NeoSpacing.xl),
                    _GuideSection(
                      icon: Icons.play_circle_outline,
                      title: '4. Connect the receiver',
                      body: 'Strict mode requires the client ID as Stream ID. '
                          'Compatibility mode accepts legacy SRT 1.0+ receivers '
                          'and can assign connections without Stream ID to one '
                          'explicit default client. IP ACL and the selected '
                          'client encryption policy still apply.',
                      examples: <_GuideExample>[
                        _GuideExample(
                          label: 'Receiver URL',
                          value:
                              'srt://public.example.net:9000?mode=caller&transtype=live&streamid=partner-a&passphrase=<one-time-key>&pbkeylen=32',
                        ),
                        _GuideExample(
                          label: 'FFplay example',
                          value:
                              'ffplay "srt://public.example.net:9000?mode=caller&streamid=partner-a&passphrase=<one-time-key>&pbkeylen=32"',
                        ),
                        _GuideExample(
                          label: 'Receiver without encryption',
                          value:
                              'srt://public.example.net:9000?mode=caller&transtype=live&streamid=partner-legacy',
                        ),
                        _GuideExample(
                          label: 'Compatibility mode with AES-256',
                          value:
                              'srt://public.example.net:9000?passphrase=<one-time-key>',
                        ),
                        _GuideExample(
                          label: 'Compatibility mode without encryption',
                          value: 'srt://public.example.net:9000',
                        ),
                      ],
                    ),
                    SizedBox(height: NeoSpacing.xl),
                    _SecurityNote(),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(NeoSpacing.lg),
              child: Align(
                alignment: Alignment.centerRight,
                child: NeoButton(
                  label: 'Done',
                  icon: Icons.check,
                  primary: true,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideSection extends StatelessWidget {
  const _GuideSection({
    required this.icon,
    required this.title,
    required this.body,
    required this.examples,
  });

  final IconData icon;
  final String title;
  final String body;
  final List<_GuideExample> examples;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, color: NeoColors.blue, size: 20),
            const SizedBox(width: NeoSpacing.md),
            Expanded(
              child:
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
            ),
          ],
        ),
        const SizedBox(height: NeoSpacing.sm),
        Text(body),
        const SizedBox(height: NeoSpacing.md),
        for (final _GuideExample example in examples) ...<Widget>[
          _CopyExample(example: example),
          if (example != examples.last) const SizedBox(height: NeoSpacing.sm),
        ],
      ],
    );
  }
}

class _GuideExample {
  const _GuideExample({required this.label, required this.value});

  final String label;
  final String value;
}

class _CopyExample extends StatefulWidget {
  const _CopyExample({required this.example});

  final _GuideExample example;

  @override
  State<_CopyExample> createState() => _CopyExampleState();
}

class _CopyExampleState extends State<_CopyExample> {
  Timer? _timer;
  bool _copied = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: NeoColors.page,
        border: Border.all(color: NeoColors.line),
        borderRadius: BorderRadius.circular(NeoRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          NeoSpacing.md,
          NeoSpacing.sm,
          NeoSpacing.sm,
          NeoSpacing.sm,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    widget.example.label,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: NeoSpacing.xs),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SelectableText(
                      widget.example.value,
                      style: const TextStyle(
                        color: NeoColors.navy,
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: NeoSpacing.sm),
            IconButton(
              tooltip: _copied ? 'Copied' : 'Copy example',
              onPressed: _copy,
              icon: Icon(
                _copied ? Icons.check : Icons.copy_outlined,
                color: _copied ? NeoColors.success : NeoColors.muted,
                size: 19,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.example.value));
    if (!mounted) {
      return;
    }
    _timer?.cancel();
    setState(() => _copied = true);
    _timer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }
}

class _SecurityNote extends StatelessWidget {
  const _SecurityNote();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: NeoColors.warning.withValues(alpha: .08),
        border: Border.all(color: NeoColors.warning.withValues(alpha: .35)),
        borderRadius: BorderRadius.circular(NeoRadius.sm),
      ),
      child: const Padding(
        padding: EdgeInsets.all(NeoSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.security_outlined, color: NeoColors.warning, size: 20),
            SizedBox(width: NeoSpacing.md),
            Expanded(
              child: Text(
                'Use the source IP visible to this server after NAT. Avoid '
                'broad CIDRs; /0 is rejected for unencrypted clients. Stream ID '
                'is not a secret, and callers behind one NAT share the same IP '
                'trust. SRT encryption protects media transport; expose '
                'the management UI only through trusted access and TLS.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
