import 'package:flutter_test/flutter_test.dart';
import 'package:photospot/services/update_service.dart';

void main() {
  group('cleanVersion', () {
    test('strips a leading v', () {
      expect(UpdateService.cleanVersion('v1.4.0'), '1.4.0');
    });

    test('drops pre-release and build suffixes', () {
      expect(UpdateService.cleanVersion('v1.4.0-beta.2'), '1.4.0');
      expect(UpdateService.cleanVersion('1.4.0+42'), '1.4.0');
    });
  });

  group('isNewer', () {
    test('detects a patch bump', () {
      expect(UpdateService.isNewer('1.0.3', '1.0.2'), isTrue);
    });

    test('detects major and minor bumps', () {
      expect(UpdateService.isNewer('2.0.0', '1.9.9'), isTrue);
      expect(UpdateService.isNewer('1.10.0', '1.9.0'), isTrue);
    });

    test('treats missing parts as zero', () {
      expect(UpdateService.isNewer('1.2', '1.2.0'), isFalse);
      expect(UpdateService.isNewer('1.2.1', '1.2'), isTrue);
    });

    test('never downgrades', () {
      expect(UpdateService.isNewer('1.0.1', '1.0.2'), isFalse);
      expect(UpdateService.isNewer('1.0.2', '1.0.2'), isFalse);
    });
  });
}
