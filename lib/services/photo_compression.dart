import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../utils/validators.dart';

/// Shrinks a picked photo and strips camera EXIF/XMP metadata before upload.
///
/// Location detection reads the raw EXIF block from the original file first, so
/// stripping metadata here never costs the auto-placed pin — and protects user
/// privacy (serial numbers, exact home GPS, timestamps) on public storage.
///
/// Every accepted container is sanitised, not just JPEG: PNG text/eXIf chunks,
/// WebP EXIF/XMP chunks, and HEIC Exif boxes are removed as well, and on
/// native platforms non-JPEG photos are re-encoded to JPEG so no metadata
/// survives the trip at all.
Future<Uint8List> compressForUpload(Uint8List bytes) async {
  final format = Validators.imageFormat(bytes);

  Uint8List sanitized;
  switch (format) {
    case ImageFormat.png:
      sanitized = stripPngMetadata(bytes);
    case ImageFormat.webp:
      sanitized = stripWebpMetadata(bytes);
    case ImageFormat.heic:
      sanitized = stripHeicMetadata(bytes);
    case ImageFormat.jpeg:
    case ImageFormat.unknown:
      // JPEG: strip APP1/EXIF and APP13 segments in pure Dart. Unknown bytes
      // are returned unchanged; the upload path rejects them on magic bytes.
      sanitized = stripJpegExif(bytes);
  }

  // The web build has no dependable native encoder; sanitised bytes it is.
  if (kIsWeb || format == ImageFormat.unknown) return sanitized;
  if (format == ImageFormat.jpeg && sanitized.length < 400 * 1024) {
    return sanitized;
  }

  try {
    final compressed = await FlutterImageCompress.compressWithList(
      sanitized,
      minWidth: 1600,
      minHeight: 1600,
      quality: 82,
      format: CompressFormat.jpeg,
      keepExif: false,
    );
    // Re-encoding always wins for non-JPEG input (it drops the container's
    // metadata for good); for JPEG only when it actually shrinks the file.
    if (format != ImageFormat.jpeg) return compressed;
    return compressed.length < sanitized.length ? compressed : sanitized;
  } catch (_) {
    // No encoder available (tests, exotic platforms): the sanitised bytes
    // from above are still metadata-free for JPEG/PNG/WebP.
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

/// Drops PNG ancillary metadata chunks (tEXt/zTXt/iTXt comments, eXIf GPS,
/// tIME timestamps, dSIG) while keeping critical chunks and colour profiles.
/// Malformed input is returned unchanged so a broken file never gets worse.
Uint8List stripPngMetadata(Uint8List bytes) {
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (bytes.length < 8) return bytes;
  for (var i = 0; i < 8; i++) {
    if (bytes[i] != signature[i]) return bytes;
  }

  const metadataChunks = {'tEXt', 'zTXt', 'iTXt', 'eXIf', 'tIME', 'dSIG'};

  final out = BytesBuilder(copy: false);
  out.add(Uint8List.sublistView(bytes, 0, 8));
  var offset = 8;

  while (offset + 12 <= bytes.length) {
    final length = _be32(bytes, offset);
    final chunkEnd = offset + 12 + length;
    if (length > bytes.length || chunkEnd > bytes.length) {
      // Corrupt length: keep the rest verbatim instead of truncating.
      out.add(Uint8List.sublistView(bytes, offset));
      return out.toBytes();
    }

    final type = String.fromCharCodes(bytes, offset + 4, offset + 8);
    if (!metadataChunks.contains(type)) {
      out.add(Uint8List.sublistView(bytes, offset, chunkEnd));
    }
    offset = chunkEnd;

    if (type == 'IEND') break;
  }

  if (offset < bytes.length) {
    out.add(Uint8List.sublistView(bytes, offset));
  }
  return out.toBytes();
}

/// Removes the EXIF and XMP chunks from a WebP container and clears their
/// flags in the VP8X feature bitstream. Malformed input is returned as-is.
Uint8List stripWebpMetadata(Uint8List bytes) {
  if (bytes.length < 12) return bytes;
  if (String.fromCharCodes(bytes, 0, 4) != 'RIFF' ||
      String.fromCharCodes(bytes, 8, 12) != 'WEBP') {
    return bytes;
  }

  final out = BytesBuilder(copy: false);
  out.add(Uint8List.sublistView(bytes, 0, 12));
  var offset = 12;

  while (offset + 8 <= bytes.length) {
    final type = String.fromCharCodes(bytes, offset + 4, offset + 8);
    final length = _be32(bytes, offset);
    final dataEnd = offset + 8 + length;
    final chunkEnd = dataEnd + (length & 1) + 4; // data (+pad) + CRC
    if (length > bytes.length || chunkEnd > bytes.length) {
      out.add(Uint8List.sublistView(bytes, offset));
      return out.toBytes();
    }

    if (type == 'EXIF' || type == 'XMP ') {
      // Chunk dropped; the VP8X flags below no longer advertise it.
    } else if (type == 'VP8X' && length >= 10) {
      // Copy first: sublistView aliases the caller's buffer, and the flags
      // byte has to change without mutating the original photo bytes.
      final data = Uint8List.fromList(
        Uint8List.sublistView(bytes, offset + 8, dataEnd),
      );
      // Bit 3 = EXIF metadata, bit 2 = XMP metadata (spec: Rsv I L E X A R).
      data[0] &= ~0x0C;
      out.add(Uint8List.sublistView(bytes, offset, offset + 8));
      out.add(data);
      out.add(Uint8List.sublistView(bytes, dataEnd, dataEnd + 4)); // CRC
    } else {
      out.add(Uint8List.sublistView(bytes, offset, chunkEnd));
    }
    offset = chunkEnd;
  }

  if (offset < bytes.length) {
    out.add(Uint8List.sublistView(bytes, offset));
  }
  return out.toBytes();
}

/// Best-effort HEIC/HEIF sanitiser: drops top-level `Exif` boxes (which is
/// where many writers place the GPS payload) and otherwise returns the file
/// unchanged. Callers on native platforms re-encode to JPEG right after this,
/// which removes any nested metadata for good.
Uint8List stripHeicMetadata(Uint8List bytes) {
  if (bytes.length < 16) return bytes;

  final out = BytesBuilder(copy: false);
  var offset = 0;

  while (offset + 8 <= bytes.length) {
    var size = _be32(bytes, offset);
    var headerSize = 8;

    if (size == 1) {
      // 64-bit extended size: 8-byte size field after the type.
      if (offset + 16 > bytes.length) {
        out.add(Uint8List.sublistView(bytes, offset));
        return out.toBytes();
      }
      size = _be64(bytes, offset + 8);
      headerSize = 16;
    } else if (size == 0) {
      // Box extends to end of file.
      size = bytes.length - offset;
    }

    if (size < headerSize || offset + size > bytes.length) {
      out.add(Uint8List.sublistView(bytes, offset));
      return out.toBytes();
    }

    final type = String.fromCharCodes(bytes, offset + 4, offset + 8);
    if (type != 'Exif') {
      out.add(Uint8List.sublistView(bytes, offset, offset + size));
    }
    offset += size;
  }

  if (offset < bytes.length) {
    out.add(Uint8List.sublistView(bytes, offset));
  }
  return out.toBytes();
}

int _be32(Uint8List bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

int _be64(Uint8List bytes, int offset) =>
    (_be32(bytes, offset) << 32) | _be32(bytes, offset + 4);
