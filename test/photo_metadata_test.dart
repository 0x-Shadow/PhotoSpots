import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photospot/services/photo_metadata.dart';

/// Builds the smallest valid little-endian JPEG with an EXIF GPS block.
Uint8List _jpegWithGps({
  double latDeg = 38,
  double latMin = 43,
  double latSec = 12,
  double lngDeg = 9,
  double lngMin = 8,
  double lngSec = 22,
  String latRef = 'N',
  String lngRef = 'W',
}) {
  final tiff = <int>[];
  void u16(int value) {
    tiff.addAll([value & 0xFF, (value >> 8) & 0xFF]);
  }

  void u32(int value) {
    tiff.addAll([
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
    ]);
  }

  // Hundredths keep the test's fractional minutes/seconds exact.
  void rational(double whole) {
    u32((whole * 100).round());
    u32(100);
  }

  // TIFF header: "II", 42, IFD0 at offset 8.
  tiff.addAll([0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00]);

  // IFD0 with a single GPS-IFD pointer entry.
  u16(1);
  u16(0x8825);
  u16(4); // LONG
  u32(1);
  u32(26); // GPS IFD starts after IFD0's 18 bytes
  u32(0); // no next IFD

  // GPS IFD: 4 entries, then the rational data.
  u16(4);
  u16(0x0001); // GPSLatitudeRef
  u16(2); // ASCII
  u32(2);
  tiff.addAll([latRef.codeUnitAt(0), 0x00, 0x00, 0x00]);

  u16(0x0002); // GPSLatitude
  u16(5); // RATIONAL
  u32(3);
  u32(80);

  u16(0x0003); // GPSLongitudeRef
  u16(2);
  u32(2);
  tiff.addAll([lngRef.codeUnitAt(0), 0x00, 0x00, 0x00]);

  u16(0x0004); // GPSLongitude
  u16(5);
  u32(3);
  u32(104);

  u32(0); // no next IFD

  rational(latDeg);
  rational(latMin);
  rational(latSec);

  rational(lngDeg);
  rational(lngMin);
  rational(lngSec);

  final exif = <int>[0x45, 0x78, 0x69, 0x66, 0x00, 0x00, ...tiff];
  final app1Length = exif.length + 2;

  return Uint8List.fromList([
    0xFF, 0xD8,
    0xFF, 0xE1,
    (app1Length >> 8) & 0xFF, app1Length & 0xFF,
    ...exif,
    0xFF, 0xD9,
  ]);
}

/// The raw `Exif\0\0` + TIFF block from the generated JPEG.
Uint8List _exifBlock() {
  final bytes = _jpegWithGps();
  const signature = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00];
  for (var i = 0; i + signature.length <= bytes.length; i++) {
    var match = true;
    for (var j = 0; j < signature.length; j++) {
      if (bytes[i + j] != signature[j]) {
        match = false;
        break;
      }
    }
    if (match) {
      return Uint8List.fromList(bytes.sublist(i, bytes.length - 2));
    }
  }
  throw StateError('no Exif block in the fixture');
}

/// Wraps the TIFF block in a minimal PNG with an `eXIf` chunk.
Uint8List _pngWithGps() {
  final tiff = _exifBlock().sublist(6);
  final chunk = <int>[];
  final length = tiff.length;
  chunk.addAll([
    (length >> 24) & 0xFF,
    (length >> 16) & 0xFF,
    (length >> 8) & 0xFF,
    length & 0xFF,
    0x65, 0x58, 0x49, 0x66, // eXIf
    ...tiff,
    0, 0, 0, 0, // CRC
  ]);
  return Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    ...chunk,
  ]);
}

void main() {
  test('reads decimal degrees from a JPEG EXIF GPS block', () {
    final location = PhotoMetadata.readGps(_jpegWithGps());

    expect(location, isNotNull);
    expect(location!.latitude, closeTo(38.72, 0.001));
    expect(location.longitude, closeTo(-9.1394, 0.001));
  });

  test('honours the S and E hemisphere refs', () {
    final location = PhotoMetadata.readGps(
      _jpegWithGps(latRef: 'S', lngRef: 'E'),
    );

    expect(location, isNotNull);
    expect(location!.latitude, lessThan(0));
    expect(location.longitude, greaterThan(0));
  });

  test('reads GPS from a HEIC-style file with the Exif payload inline', () {
    final exif = _exifBlock();
    final bytes = Uint8List.fromList([
      // A box header and some item data, as a HEIC stores it.
      0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70,
      0x68, 0x65, 0x69, 0x63, 0x00, 0x00, 0x00, 0x00,
      ...exif,
    ]);

    final location = PhotoMetadata.readGps(bytes);

    expect(location, isNotNull);
    expect(location!.latitude, closeTo(38.72, 0.001));
    expect(location.longitude, closeTo(-9.1394, 0.001));
  });

  test('reads GPS from a PNG eXIf chunk', () {
    final location = PhotoMetadata.readGps(_pngWithGps());

    expect(location, isNotNull);
    expect(location!.latitude, closeTo(38.72, 0.001));
    expect(location.longitude, closeTo(-9.1394, 0.001));
  });

  test('returns null without EXIF, for other formats, and for junk', () {
    expect(
      PhotoMetadata.readGps(
        Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]),
      ),
      isNull,
    );
    expect(
      PhotoMetadata.readGps(
        Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0]),
      ),
      isNull,
    );
    expect(
      PhotoMetadata.readGps(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE1, 0x00])),
      isNull,
    );
  });
}