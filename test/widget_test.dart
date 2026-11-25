import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:photospot/data/spot_repository.dart';
import 'package:photospot/screens/root_shell.dart';
import 'package:photospot/state/app_state.dart';
import 'package:photospot/theme/app_theme.dart';

void main() {
  testWidgets('PhotoSpot boots with root shell', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(MockSpotRepository())..load(),
        child: MaterialApp(theme: AppTheme.dark, home: const RootShell()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    // App boots without crashing
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
