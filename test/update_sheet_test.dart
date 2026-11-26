import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photospot/services/update_service.dart';
import 'package:photospot/widgets/update_sheet.dart';

void main() {
  final release = ReleaseInfo(
    tag: 'v2.0.0',
    version: '2.0.0',
    notes: 'Polish and fixes.',
    pageUrl: Uri.parse('https://example.com/releases'),
  );

  Future<void> pumpSheet(
    WidgetTester tester, {
    required UpdatePhase phase,
    int received = 0,
    int? total,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UpdateSheet(
            release: release,
            initialPhase: phase,
            initialReceived: received,
            initialTotal: total,
          ),
        ),
      ),
    );
  }

  testWidgets('the permission phase explains what to do next', (tester) async {
    await pumpSheet(tester, phase: UpdatePhase.needsPermission);

    expect(
      find.text(
        'Allow PhotoSpot to install updates, then tap Update again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Install update'), findsOneWidget);
  });

  testWidgets('downloading shows progress in megabytes', (tester) async {
    await pumpSheet(
      tester,
      phase: UpdatePhase.downloading,
      received: 2 * 1024 * 1024,
      total: 4 * 1024 * 1024,
    );

    expect(find.text('2.0 of 4.0 MB'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });
}
