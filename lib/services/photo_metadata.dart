import 'dart:typed_data';

/// GPS coordinates embedded in a photo by the camera.
class PhotoLocation {
  const PhotoLocation({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;

  @override
  String toString() =>
      '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';

  @override
  bool operator ==(Object other) =>
      other is PhotoLocation &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);
}

/// Reads the GPS block a camera writes into a JPEG's EXIF segment.
///
/// Pure Dart and dependency-free: it walks the JPEG marker stream to the APP1
/// segment, parses the TIFF header and IFD0, follows the GPS IFD pointer, and
/// converts the three DMS rationals into decimal degrees. Anything unexpected
/// (PNG, stripped metadata, corrupt offsets) simply returns null — detecting a
/// location is a bonus, never a requirement.
class PhotoMetadata {
  PhotoMetadata._();

  static PhotoLocation? readGps(Uint8List bytes) {
    if (bytes.length < 4) return null;
    if (bytes[0] != 0xFF || bytes[1] != 0xD8) return null;

    var offset = 2;
    while (offset + 4 <= bytes.length) {
      if (bytes[offset] != 0xFF) {
        offset++;
        continue;
      }
      final marker = bytes[offset + 1];
      // Standalone markers carry no length payload.
      if (marker == 0xD8 ||
          marker == 0x01 ||
          (marker >= 0xD0 && marker <= 0xD7) ||
          marker == 0xFF) {
        offset += 2;
        continue;
      }
      // Start of scan / end of image: no APP1 ahead.
      if (marker == 0xDA || marker == 0xD9) return null;

      final length = _u16(bytes, offset + 2, Endian.big);
      if (length < 2) return null;
      final segmentStart = offset + 4;
      final segmentEnd = offset + 2 + length;
      if (segmentEnd > bytes.length) return null;

      if (marker == 0xE1 &&
          segmentStart + 6 <= segmentEnd &&
          bytes[segmentStart] == 0x45 && // E
          bytes[segmentStart + 1] == 0x78 && // x
          bytes[segmentStart + 2] == 0x69 && // i
          bytes[segmentStart + 3] == 0x66 && // f
          bytes[segmentStart + 4] == 0x00) {
        return _readTiff(
          Uint8List.sublistView(bytes, segmentStart + 6, segmentEnd),
        );
      }
      offset = segmentEnd;
    }
    return null;
  }

  static PhotoLocation? _readTiff(Uint8List tiff) {
    if (tiff.length < 8) return null;
    final little = tiff[0] == 0x49 && tiff[1] == 0x49; // "II"
    final big = tiff[0] == 0x4D && tiff[1] == 0x4D; // "MM"
    if (!little && !big) return null;
    final endian = little ? Endian.little : Endian.big;
    if (_u16(tiff, 2, endian) != 0x2A) return null;

    final ifd0 = _u32(tiff, 4, endian);
    final gpsIfd = _findTag(tiff, ifd0, endian, 0x8825);
    if (gpsIfd == null || gpsIfd >= tiff.length) return null;

    final latitude = _readCoordinate(tiff, gpsIfd, endian, 0x0002);
    final longitude = _readCoordinate(tiff, gpsIfd, endian, 0x0004);
    if (latitude == null || longitude == null) return null;

    final latRef = _readAscii(tiff, gpsIfd, endian, 0x0001);
    final lngRef = _readAscii(tiff, gpsIfd, endian, 0x0003);

    final lat = latRef == 'S' ? -latitude : latitude;
    final lng = lngRef == 'W' ? -longitude : longitude;
    if (lat.abs() > 90 || lng.abs() > 180) return null;
    if (lat == 0 && lng == 0) return null;
    return PhotoLocation(latitude: lat, longitude: lng);
  }

  /// Returns the value stored in [tag] of the IFD starting at [ifdOffset],
  /// interpreted as an unsigned 32-bit offset.
  static int? _findTag(
    Uint8List tiff,
    int ifdOffset,
    Endian endian,
    int tag,
  ) {
    if (ifdOffset + 2 > tiff.length) return null;
    final count = _u16(tiff, ifdOffset, endian);
    if (count == 0 || count > 512) return null;
    for (var i = 0; i < count; i++) {
      final entry = ifdOffset + 2 + i * 12;
      if (entry + 12 > tiff.length) return null;
      if (_u16(tiff, entry, endian) != tag) continue;
      final type = _u16(tiff, entry + 2, endian);
      final value = _u32(tiff, entry + 8, endian);
      if (type == 3) return value & 0xFFFF; // SHORT is inline
      return value;
    }
    return null;
  }

  /// Reads a GPS coordinate: three RATIONALs (degrees, minutes, seconds).
  static double? _readCoordinate(
    Uint8List tiff,
    int ifdOffset,
    Endian endian,
    int tag,
  ) {
    if (ifdOffset + 2 > tiff.length) return null;
    final count = _u16(tiff, ifdOffset, endian);
    for (var i = 0; i < count; i++) {
      final entry = ifdOffset + 2 + i * 12;
      if (entry + 12 > tiff.length) return null;
      if (_u16(tiff, entry, endian) != tag) continue;
      if (_u16(tiff, entry + 2, endian) != 5) return null;
      final values = _u32(tiff, entry + 4, endian);
      if (values < 3) return null;
      final start = _u32(tiff, entry + 8, endian);
      final degrees = _rational(tiff, endian, start);
      final minutes = _rational(tiff, endian, start + 8);
      final seconds = _rational(tiff, endian, start + 16);
      if (degrees == null || minutes == null || seconds == null) return null;
      return degrees + minutes / 60 + seconds / 3600;
    }
    return null;
  }

  static String? _readAscii(
    Uint8List tiff,
    int ifdOffset,
    Endian endian,
    int tag,
  ) {
    if (ifdOffset + 2 > tiff.length) return null;
    final count = _u16(tiff, ifdOffset, endian);
    for (var i = 0; i < count; i++) {
      final entry = ifdOffset + 2 + i * 12;
      if (entry + 12 > tiff.length) return null;
      if (_u16(tiff, entry, endian) != tag) continue;
      if (_u16(tiff, entry + 2, endian) != 2) return null;
      final length = _u32(tiff, entry + 4, endian);
      if (length == 0 || length > 8) return null;
      final start = length <= 4 ? entry + 8 : _u32(tiff, entry + 8, endian);
      if (start + length > tiff.length) return null;
      final value = String.fromCharCodes(tiff.sublist(start, start + length))
          .replaceAll('\u0000', '')
          .trim()
          .toUpperCase();
      return value.isEmpty ? null : value;
    }
    return null;
  }

  static double? _rational(Uint8List tiff, Endian endian, int offset) {
    if (offset + 8 > tiff.length) return null;
    final numerator = _u32(tiff, offset, endian);
    final denominator = _u32(tiff, offset + 4, endian);
    if (denominator == 0) return null;
    return numerator / denominator;
  }

  static int _u16(Uint8List bytes, int offset, Endian endian) {
    if (offset + 2 > bytes.length) return 0;
    return ByteData.sublistView(bytes).getUint16(offset, endian);
  }

  static int _u32(Uint8List bytes, int offset, Endian endian) {
    if (offset + 4 > bytes.length) return 0;
    return ByteData.sublistView(bytes).getUint32(offset, endian);
  }
}
