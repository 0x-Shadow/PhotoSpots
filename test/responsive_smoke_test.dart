import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photospot/screens/root_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/test_harness.dart';

Widget _app() => testApp(home: const RootShell());

Future<void> _pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(_app());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('all tabs lay out on a small phone screen', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpApp(tester);
    expect(tester.takeException(), isNull);

    for (final tab in ['Map', 'Saved', 'Profile', 'Home']) {
      await tester.tap(find.text(tab).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull, reason: '$tab tab overflowed');
    }
  });

  testWidgets('wide layout uses the navigation rail', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpApp(tester);

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Saved').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  });
}
