import 'dart:math' as math;

/// Solar light windows for a geographic coordinate and local calendar date.
class SolarLightTimes {
  const SolarLightTimes({
    required this.sunrise,
    required this.sunset,
    required this.morningGoldenEnd,
    required this.eveningGoldenStart,
    required this.eveningBlueEnd,
    this.isPolarDay = false,
    this.isPolarNight = false,
  });

  final DateTime? sunrise;
  final DateTime? sunset;
  final DateTime? morningGoldenEnd;
  final DateTime? eveningGoldenStart;
  final DateTime? eveningBlueEnd;
  final bool isPolarDay;
  final bool isPolarNight;
}

/// Pure-Dart NOAA-approximation solar calculator for photographers.
/// Zero network dependencies and fully deterministic for any given [date].
class SolarCalculator {
  SolarCalculator._();

  static SolarLightTimes forLocation({
    required double latitude,
    required double longitude,
    required DateTime date,
  }) {
    final localMidnight = DateTime(date.year, date.month, date.day);
    final tzOffsetHours = date.timeZoneOffset.inMinutes / 60.0;
    final dayOfYear =
        localMidnight.difference(DateTime(date.year, 1, 1)).inDays + 1;

    // Fractional year in radians (NOAA general solar equation).
    final gamma = (2 * math.pi / 365.0) * (dayOfYear - 1);

    final eqTime = 229.18 *
        (0.000075 +
            0.001868 * math.cos(gamma) -
            0.032077 * math.sin(gamma) -
            0.014615 * math.cos(2 * gamma) -
            0.040849 * math.sin(2 * gamma));

    final decl = 0.006918 -
        0.399912 * math.cos(gamma) +
        0.070257 * math.sin(gamma) -
        0.006758 * math.cos(2 * gamma) +
        0.000907 * math.sin(2 * gamma) -
        0.002697 * math.cos(3 * gamma) +
        0.00148 * math.sin(3 * gamma);

    final latRad = latitude * math.pi / 180.0;

    DateTime? eventTime(double zenithDeg, {required bool isRise}) {
      final zenithRad = zenithDeg * math.pi / 180.0;
      final cosHa = (math.cos(zenithRad) /
              (math.cos(latRad) * math.cos(decl))) -
          math.tan(latRad) * math.tan(decl);
      if (cosHa > 1.0 || cosHa < -1.0) return null;
      final haDeg = math.acos(cosHa) * 180.0 / math.pi;
      final signedHa = isRise ? haDeg : -haDeg;
      final minutesUtc = 720.0 - 4.0 * (longitude + signedHa) - eqTime;
      final minutesLocal = minutesUtc + tzOffsetHours * 60.0;
      return localMidnight.add(Duration(minutes: minutesLocal.round()));
    }

    // Standard sunrise/sunset zenith = 90.833°, golden hour top (~+6° elevation
    // => zenith 84°), civil twilight / blue hour end (~-6° => zenith 96°).
    final sunrise = eventTime(90.833, isRise: true);
    final sunset = eventTime(90.833, isRise: false);
    final morningGoldenEnd = eventTime(84.0, isRise: true);
    final eveningGoldenStart = eventTime(84.0, isRise: false);
    final eveningBlueEnd = eventTime(96.0, isRise: false);

    final cosSunrise = (math.cos(90.833 * math.pi / 180.0) /
            (math.cos(latRad) * math.cos(decl))) -
        math.tan(latRad) * math.tan(decl);

    return SolarLightTimes(
      sunrise: sunrise,
      sunset: sunset,
      morningGoldenEnd: morningGoldenEnd,
      eveningGoldenStart: eveningGoldenStart,
      eveningBlueEnd: eveningBlueEnd,
      isPolarDay: cosSunrise < -1.0,
      isPolarNight: cosSunrise > 1.0,
    );
  }

  static String formatTime(DateTime? dt) {
    if (dt == null) return '—';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
