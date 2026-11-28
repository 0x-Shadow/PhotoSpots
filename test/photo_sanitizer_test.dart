import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photospot/services/photo_compression.dart';
import 'package:photospot/utils/validators.dart';

String _latin1(Uint8List bytes) => String.fromCharCodes(bytes);

Uint8List _jpegWithExif() => Uint8List.fromList([
      // SOI.
      0xFF, 0xD8,
      // APP0 JFIF: marker, length 16, 14 bytes of JFIF data.
      0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05,
      0x06, 0x07, 0x08, 0x09,
      // APP1 EXIF: marker, length 14, 12 bytes of metadata.
      0xFF, 0xE1, 0x00, 0x0E, 0x45, 0x78, 0x69, 0x66, 0x00, 0x00, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF,
      // EOI.
      0xFF, 0xD9,
    ]);

Uint8List _pngChunk(String type, List<int> data) {
  final len = data.length;
  return Uint8List.fromList([
    (len >> 24) & 0xFF,
    (len >> 16) & 0xFF,
    (len >> 8) & 0xFF,
    len & 0xFF,
    ...type.codeUnits,
    ...data,
    0x00,
    0x00,
    0x00,
    0x00,
  ]);
}

Uint8List _pngWithExif() {
  return Uint8List.fromList([
    ...[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
    ..._pngChunk('IHDR', [0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x06, 0x00, 0x00]),
    ..._pngChunk('eXIf', [0x00, 0x00, 0x00, 0x00]),
    ..._pngChunk('IDAT', [0x00]),
    ..._pngChunk('IEND', []),
  ]);
}

Uint8List _webpWithExifFlags(int flags) {
  final vp8xData = [flags, 0, 0, 0, 0, 0, 0, 0, 0, 0]; // flags + reserved + wh = 10 bytes
  return Uint8List.fromList([
    // RIFF....WEBP
    0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x2D, 0x00, 0x57, 0x45, 0x42, 0x50,
    ..._webpChunk('VP8X', vp8xData, sizeOverride: 10),
    ..._webpChunk('EXIF', [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
  ]);
}

Uint8List _webpChunk(String type, List<int> data, {int? sizeOverride}) {
  final size = sizeOverride ?? data.length;
  final b = BytesBuilder();
  void be32(int v) {
    b.add([(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]);
  }

  be32(size);
  b.add(type.codeUnits);
  b.add(data);
  b.add([0x00, 0x00, 0x00, 0x00]);
  return b.toBytes();
}

Uint8List _heicBox(String type, List<int> payload) {
  final size = 8 + payload.length;
  final out = BytesBuilder();
  void be32(int v) {
    out.add([(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]);
  }

  be32(size);
  out.add(type.codeUnits);
  out.add(payload);
  return out.toBytes();
}

Uint8List _heicWithExif() {
  return Uint8List.fromList([
    ..._heicBox('ftyp', [0x68, 0x65, 0x69, 0x63]),
    ..._heicBox('Exif', const []),
    ..._heicBox('mif1', [0x00, 0x00, 0x00, 0x00]),
  ]);
}

void main() {
  group('imageFormat detection', () {
    test('classifies jpeg / png / webp / heic from magic bytes', () {
      expect(
        Validators.imageFormat(Uint8List.fromList([
          0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
        ])),
        ImageFormat.jpeg,
      );
      expect(
        Validators.imageFormat(Uint8List.fromList([
          0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
        ])),
        ImageFormat.png,
      );
      expect(
        Validators.imageFormat(Uint8List.fromList([
          0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50,
        ])),
        ImageFormat.webp,
      );
      expect(
        Validators.imageFormat(Uint8List.fromList([
          0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63, 0x00, 0x00,
        ])),
        ImageFormat.heic,
      );
      expect(
        Validators.imageFormat(Uint8List.fromList([1, 2, 3, 4, 5])),
        ImageFormat.unknown,
      );
    });

    test('hasAllowedImageMagicBytes accepts every supported container', () {
      expect(
        Validators.hasAllowedImageMagicBytes(Uint8List.fromList([
          0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
        ])),
        isTrue,
      );
      expect(
        Validators.hasAllowedImageMagicBytes(Uint8List.fromList([1, 2, 3, 4])),
        isFalse,
      );
    });
  });

  group('content type and extension mapping', () {
    test('maps each format to its storage mime type and extension', () {
      final png = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x00,
      ]);
      final webp = Uint8List.fromList([
        0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50,
      ]);
      final heic = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63, 0x00, 0x00,
      ]);
      final jpeg = Uint8List.fromList([
        0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
      ]);

      expect(Validators.imageContentType(png), 'image/png');
      expect(Validators.imageExtension(png), 'png');
      expect(Validators.imageContentType(webp), 'image/webp');
      expect(Validators.imageExtension(webp), 'webp');
      expect(Validators.imageContentType(heic), 'image/heic');
      expect(Validators.imageExtension(heic), 'heic');
      expect(Validators.imageContentType(jpeg), 'image/jpeg');
      expect(Validators.imageExtension(jpeg), 'jpg');
    });
  });

  group('stripJpegExif', () {
    test('drops APP1 EXIF segments but keeps the rest of the stream', () {
      final stripped = stripJpegExif(_jpegWithExif());

      expect(stripped[0], 0xFF);
      expect(stripped[1], 0xD8);
      expect(_latin1(stripped.sublist(6, 10)), 'JFIF');
      expect(_latin1(stripped.sublist(stripped.length - 2, stripped.length)),
          String.fromCharCodes([0xFF, 0xD9]));
      expect(_latin1(stripped).contains('Exif'), isFalse);
      expect(_latin1(stripped).contains('JFIF'), isTrue);
    });

    test('leaves non-JPEG bytes untouched', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      expect(stripJpegExif(bytes), same(bytes));
    });
  });

  group('stripPngMetadata', () {
    test('drops eXIf metadata chunks but keeps critical chunks', () {
      final stripped = stripPngMetadata(_pngWithExif());

      expect(_latin1(stripped.sublist(12, 16)), 'IHDR');
      expect(_latin1(stripped).contains('IEND'), isTrue);
      expect(_latin1(stripped).contains('eXIf'), isFalse);
      expect(_latin1(stripped).contains('IHDR'), isTrue);
    });

    test('returns malformed input untouched', () {
      final bytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0B]);
      expect(stripPngMetadata(bytes), same(bytes));
    });
  });

  group('stripWebpMetadata', () {
    test('removes the EXIF chunk and clears its VP8X flag', () {
      final input = _webpWithExifFlags(0x0C);
      final stripped = stripWebpMetadata(input);

      expect(_latin1(stripped.sublist(0, 4)), 'RIFF');
      expect(_latin1(stripped.sublist(8, 12)), 'WEBP');
      expect(_latin1(stripped.sublist(16, 20)), 'VP8X');
      expect(stripped[20], 0x00);
      expect(_latin1(stripped).contains('EXIF'), isFalse);
      expect(_latin1(stripped).contains('WEBP'), isTrue);
      expect(_latin1(stripped).contains('VP8X'), isTrue);
    });
  });

  group('stripHeicMetadata', () {
    test('drops top-level Exif boxes but keeps the rest', () {
      final stripped = stripHeicMetadata(_heicWithExif());

      expect(_latin1(stripped.sublist(4, 8)), 'ftyp');
      expect(_latin1(stripped).contains('Exif'), isFalse);
      expect(_latin1(stripped).contains('mif1'), isTrue);
    });
  });

  group('compressForUpload', () {
    test('small JPEGs are returned already stripped without re-encoding', () async {
      final stripped = await compressForUpload(_jpegWithExif());

      expect(stripped[0], 0xFF);
      expect(stripped[1], 0xD8);
      expect(_latin1(stripped).contains('Exif'), isFalse);
      expect(_latin1(stripped).contains('JFIF'), isTrue);
      expect(stripped.last, 0xD9);
    });

    test('unknown bytes pass through unchanged (upload path rejects them)', () async {
      final bytes = Uint8List.fromList([9, 9, 9, 9]);
      final result = await compressForUpload(bytes);
      expect(result, same(bytes));
    });
  });
}
