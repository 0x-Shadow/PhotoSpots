import 'package:flutter_test/flutter_test.dart';
import 'package:photospot/state/auth_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('signing out clears the cached profile identity', () async {
    final auth = AuthState();
    await auth.load();
    await auth.updateProfile(
      name: 'Private Name',
      bio: 'Private bio',
      city: 'Athens',
    );

    await auth.signOut();

    expect(auth.isGuest, isTrue);
    expect(auth.displayName, 'Explorer');
    expect(auth.bio, isEmpty);
    expect(auth.city, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(AuthState.displayNameKey), isNull);
    expect(prefs.getString(AuthState.cityKey), isNull);
  });
}
