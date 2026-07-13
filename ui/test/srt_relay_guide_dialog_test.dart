import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neotranscoder_ui/app/theme.dart';
import 'package:neotranscoder_ui/features/srt/srt_relay_guide_dialog.dart';

void main() {
  testWidgets('relay info button opens responsive guide with examples',
      (WidgetTester tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: NeoTheme.light(),
        home: const Scaffold(body: SrtRelayGuideButton()),
      ),
    );

    await tester.tap(find.byKey(const Key('srt-relay-guide-button')));
    await tester.pumpAndSettle();

    expect(find.text('SRT relay setup'), findsOneWidget);
    expect(find.text('1. Select the multicast source'), findsOneWidget);
    expect(find.text('udp://239.10.10.1:1234'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final Finder copyButton = find.byTooltip('Copy example').first;
    await tester.ensureVisible(copyButton);
    await tester.pumpAndSettle();
    await tester.tap(copyButton);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byTooltip('Copied'), findsOneWidget);

    await tester.tap(find.byTooltip('Close guide'));
    await tester.pumpAndSettle();
    expect(find.text('SRT relay setup'), findsNothing);
  });
}
