import 'dart:math' as math;
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

/// Reads the GPS block a camera writes into a photo's EXIF metadata.
///
/// Pure Dart and dependency-free. It understands the containers phones actually
/// produce:
///
/// * JPEG — walks the marker stream to APP1/Exif.
/// * HEIC/HEIF (iPhone and many Androids) — finds the Exif payload inside the
///   `meta` box data.
/// * PNG — reads the `eXIf` chunk.
/// * WebP — reads the `EXIF` chunk.
/// * Anything else (or an unexpected layout) — falls back to scanning the
///   buffer for an `Exif\0\0` header.
///
/// Anything unreadable simply returns null: detecting a location is a bonus,
/// never a requirement.
class PhotoMetadata {
  PhotoMetadata._();

  /// The bytes scanned when looking for an Exif header. EXIF blocks live in
  /// the first few megabytes even in large HEIC files, so the cap keeps a
  /// multi-megabyte fallback scan off the jank path.
  static const int _scanLimit = 8 << 20;

  static PhotoLocation? readGps(Uint8List bytes) {
    if (bytes.length < 4) return null;

    // JPEG: read APP1 properly first so a file with several segments is fast.
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
      final segment = _readJpegExif(bytes);
      if (segment != null) return segment;
    }

    if (_isPng(bytes)) {
      final tiff = _readPngExif(bytes);
      if (tiff != null) {
        final location = _readTiff(tiff);
        if (location != null) return location;
      }
    }

    if (_isWebp(bytes)) {
      final tiff = _readWebpExif(bytes);
      if (tiff != null) {
        final location = _readTiff(tiff);
        if (location != null) return location;
      }
    }

    // HEIC/HEIF, and any JPEG/PNG whose segment layout surprised us: the Exif
    // payload always carries its own header, so search for it wherever it is.
    final scanned = _scanForExif(bytes);
    if (scanned != null) return scanned;

    // Some containers carry a bare TIFF block with no `Exif\0\0` header (or
    // an item offset we cannot follow). Only worth scanning when the file is
    // not one of the formats already handled above, so a JPEG with no GPS
    // cannot be misread from random image bytes.
    final handled = (bytes.length > 1 && bytes[0] == 0xFF && bytes[1] == 0xD8) ||
        _isPng(bytes) ||
        _isWebp(bytes);
    if (!handled) {
      final tiff = _scanForTiffHeader(bytes);
      if (tiff != null) return tiff;
    }

    // Last resort: XMP. Editors and some galleries keep GPS in the XMP packet
    // after stripping the EXIF block, which is why the same file can show a
    // location in other photo apps but not here.
    return _scanForXmpGps(bytes);
  }

  /// Searches the buffer for a bare TIFF header (`II*\0` or `MM\0*`) and
  /// parses the GPS block that follows. Used for HEIC/HEIF/AVIF variants whose
  /// Exif item layout does not start with an `Exif\0\0` signature.
  static PhotoLocation? _scanForTiffHeader(Uint8List bytes) {
    final end = math.min(bytes.length, _scanLimit) - 4;
    for (var i = 0; i <= end; i++) {
      final first = bytes[i];
      if (first != 0x49 && first != 0x4D) continue; // 'I' or 'M'
      if (bytes[i + 1] != first) continue;
      final valid = first == 0x49
          ? bytes[i + 2] == 0x2A && bytes[i + 3] == 0x00
          : bytes[i + 2] == 0x00 && bytes[i + 3] == 0x2A;
      if (!valid) continue;
      final location = _readTiff(Uint8List.sublistView(bytes, i));
      if (location != null) return location;
    }
    return null;
  }

  /// Reads `GPSLatitude` / `GPSLongitude` from an XMP packet, e.g.
  /// `exif:GPSLatitude="38,43.12N"`. Returns null unless both axes parse.
  static PhotoLocation? _scanForXmpGps(Uint8List bytes) {
    // XMP lives near the start of the file even in large photos; a 1 MB window
    // keeps the fallback cheap.
    final end = math.min(bytes.length, 1 << 20);
    final text = String.fromCharCodes(bytes.sublist(0, end));
    final lat = _xmpCoordinate(text, 'GPSLatitude');
    final lng = _xmpCoordinate(text, 'GPSLongitude');
    if (lat == null || lng == null) return null;
    if (lat.abs() > 90 || lng.abs() > 180) return null;
    if (lat == 0 && lng == 0) return null;
    return PhotoLocation(latitude: lat, longitude: lng);
  }

  // Degrees use a dot decimal; the comma is the DMS separator, so it must not
  // be swallowed by the degrees group (`38,43.12N` is 38° 43.12′).
  static final _xmpPattern = RegExp(
    r'''^[^0-9+-]{0,6}(-?[0-9]{1,3}(?:\.[0-9]+)?)'''
    r'''(?:[,\s]+([0-9]{1,2}(?:\.[0-9]+)?))?'''
    r'''(?:[,\s]+([0-9]{1,2}(?:\.[0-9]+)?))?'''
    r'''\s*([NSEW])?''',
  );

  static double? _xmpCoordinate(String text, String tag) {
    var index = text.indexOf(tag);
    var attempts = 0;
    while (index != -1 && attempts < 6) {
      attempts++;
      final start = index + tag.length;
      // Skip `GPSLatitudeRef` and similar tags that merely start with the name.
      if (start < text.length) {
        final next = text.codeUnitAt(start);
        final isLetter = (next >= 0x41 && next <= 0x5A) ||
            (next >= 0x61 && next <= 0x7A);
        if (isLetter) {
          index = text.indexOf(tag, start);
          continue;
        }
      }
      final slice = text.substring(
        start,
        math.min(text.length, start + 90),
      );
      final match = _xmpPattern.firstMatch(slice);
      if (match != null) {
        double parse(String? value) =>
            double.tryParse((value ?? '0').replaceAll(',', '.')) ?? 0;
        final degrees = parse(match.group(1));
        final minutes = parse(match.group(2));
        final seconds = parse(match.group(3));
        final sign = degrees < 0 ? -1.0 : 1.0;
        var value = sign *
            (degrees.abs() + minutes / 60 + seconds / 3600);
        final ref = match.group(4);
        if (ref == 'S' || ref == 'W') value = -value.abs();
        if (value != 0) return value;
      }
      index = text.indexOf(tag, start);
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Containers
  // ---------------------------------------------------------------------------

  /// Walks JPEG markers until an APP1/Exif segment is found.
  static PhotoLocation? _readJpegExif(Uint8List bytes) {
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

      if (marker == 0xE1 && _hasExifHeader(bytes, segmentStart, segmentEnd)) {
        return _readTiff(
          Uint8List.sublistView(bytes, segmentStart + 6, segmentEnd),
        );
      }
      offset = segmentEnd;
    }
    return null;
  }

  static bool _isPng(Uint8List bytes) =>
      bytes.length > 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47;

  /// Reads the `eXIf` chunk of a PNG, whose payload is a bare TIFF block.
  static Uint8List? _readPngExif(Uint8List bytes) {
    var offset = 8;
    while (offset + 8 <= bytes.length) {
      final length = _u32(bytes, offset, Endian.big);
      if (length <= 0 || offset + 12 + length > bytes.length) return null;
      final type = bytes[offset + 4];
      // 'eXIf'
      if (type == 0x65 &&
          bytes[offset + 5] == 0x58 &&
          bytes[offset + 6] == 0x49 &&
          bytes[offset + 7] == 0x66) {
        return Uint8List.sublistView(bytes, offset + 8, offset + 8 + length);
      }
      offset += 12 + length; // length + type + data + CRC
    }
    return null;
  }

  static bool _isWebp(Uint8List bytes) =>
      bytes.length > 12 &&
      bytes[0] == 0x52 && // R
      bytes[1] == 0x49 && // I
      bytes[2] == 0x46 && // F
      bytes[3] == 0x46 && // F
      bytes[8] == 0x57 && // W
      bytes[9] == 0x45 && // E
      bytes[10] == 0x42 && // B
      bytes[11] == 0x50; // P

  /// Reads the `EXIF` chunk of a WebP, whose payload is a bare TIFF block.
  static Uint8List? _readWebpExif(Uint8List bytes) {
    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final type = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final length = _u32(bytes, offset + 4, Endian.little);
      if (length < 0 || offset + 8 + length > bytes.length) return null;
      if (type == 'EXIF') {
        var start = offset + 8;
        // Some writers keep the "Exif\0\0" header inside the chunk.
        if (start + 6 <= bytes.length && _hasExifHeader(bytes, start, start + 6)) {
          start += 6;
        }
        return Uint8List.sublistView(bytes, start, offset + 8 + length);
      }
      offset += 8 + length + (length.isOdd ? 1 : 0);
    }
    return null;
  }

  /// Searches the buffer for an `Exif\0\0` header and parses the TIFF block
  /// that follows. This is what makes HEIC/HEIF photos work.
  static PhotoLocation? _scanForExif(Uint8List bytes) {
    final end = math.min(bytes.length, _scanLimit);
    final last = end - 6;
    for (var i = 0; i <= last; i++) {
      if (bytes[i] != 0x45) continue; // 'E'
      if (!_hasExifHeader(bytes, i, end)) continue;
      final tiff = Uint8List.sublistView(bytes, i + 6, end);
      final location = _readTiff(tiff);
      if (location != null) return location;
    }
    return null;
  }

  static bool _hasExifHeader(Uint8List bytes, int start, int end) {
    if (start + 6 > end || start < 0) return false;
    return bytes[start] == 0x45 && // E
        bytes[start + 1] == 0x78 && // x
        bytes[start + 2] == 0x69 && // i
        bytes[start + 3] == 0x66 && // f
        bytes[start + 4] == 0x00 &&
        bytes[start + 5] == 0x00;
  }

  // ---------------------------------------------------------------------------
  // TIFF / EXIF
  // ---------------------------------------------------------------------------

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
