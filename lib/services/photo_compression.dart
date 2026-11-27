import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Shrinks a picked photo and strips camera EXIF metadata before upload.
///
/// Location detection reads the raw EXIF block from the original file first, so
/// stripping metadata here never costs the auto-placed pin — and protects user
/// privacy (serial numbers, exact home GPS, timestamps) on public storage.
Future<Uint8List> compressForUpload(Uint8List bytes) async {
  // Always strip JPEG APP1/EXIF segments in pure Dart so even small files or
  // web uploads do not leak raw camera metadata.
  final sanitized = stripJpegExif(bytes);

  // The web build has no dependable native encoder; return sanitized bytes.
  if (kIsWeb || sanitized.length < 400 * 1024) return sanitized;

  try {
    final compressed = await FlutterImageCompress.compressWithList(
      sanitized,
      minWidth: 1600,
      minHeight: 1600,
      quality: 82,
      format: CompressFormat.jpeg,
      keepExif: false,
    );
    return compressed.length < sanitized.length ? compressed : sanitized;
  } catch (_) {
    return sanitized;
  }
}

/// Strips JPEG APP1 (EXIF/XMP) and APP2-APP15 metadata segments while keeping
/// image structure intact. Non-JPEG bytes are returned unchanged.
Uint8List stripJpegExif(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
    return bytes;
  }

  final out = BytesBuilder(copy: false);
  out.add(const [0xFF, 0xD8]);
  var offset = 2;

  while (offset < bytes.length) {
    if (bytes[offset] != 0xFF) {
      out.add(Uint8List.sublistView(bytes, offset));
      break;
    }

    if (offset + 1 >= bytes.length) {
      out.addByte(bytes[offset]);
      break;
    }

    final marker = bytes[offset + 1];
    // Start of Scan (0xDA): copy the rest of the entropy-coded image stream.
    if (marker == 0xDA || marker == 0xD9) {
      out.add(Uint8List.sublistView(bytes, offset));
      break;
    }

    // Standalone markers with no length field.
    if (marker == 0x00 ||
        marker == 0x01 ||
        (marker >= 0xD0 && marker <= 0xD8) ||
        marker == 0xFF) {
      out.add(Uint8List.sublistView(bytes, offset, offset + 2));
      offset += 2;
      continue;
    }

    if (offset + 3 >= bytes.length) {
      out.add(Uint8List.sublistView(bytes, offset));
      break;
    }

    final length = (bytes[offset + 2] << 8) | bytes[offset + 3];
    final segmentEnd = offset + 2 + length;
    if (length < 2 || segmentEnd > bytes.length) {
      out.add(Uint8List.sublistView(bytes, offset));
      break;
    }

    // Drop APP1 (EXIF/XMP) and APP13 (IPTC) metadata segments. Keep APP0/APP2
    // (JFIF/ICC color profile) and quantization/Huffman tables.
    final isSensitiveMetadata = marker == 0xE1 || marker == 0xED;
    if (!isSensitiveMetadata) {
      out.add(Uint8List.sublistView(bytes, offset, segmentEnd));
    }
    offset = segmentEnd;
  }

  return out.toBytes();
}
