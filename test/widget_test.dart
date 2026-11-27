import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photospot/screens/root_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PhotoSpot boots with the root shell', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(testApp(home: const RootShell()));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Find a place\nworth going out for.'), findsOneWidget);
  });
}
