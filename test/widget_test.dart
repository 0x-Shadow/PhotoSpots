import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photospot/data/spot_repository.dart';
import 'package:photospot/screens/root_shell.dart';
import 'package:photospot/state/app_state.dart';
import 'package:photospot/state/settings_state.dart';
import 'package:photospot/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PhotoSpot boots with the root shell', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => AppState(MockSpotRepository())..load(),
          ),
          ChangeNotifierProvider(create: (_) => SettingsState()..load()),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const RootShell()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Explore the\nbest places.'), findsOneWidget);
  });
}
