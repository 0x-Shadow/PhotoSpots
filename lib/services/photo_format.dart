import 'dart:typed_data';

/// Container formats the app accepts for upload.
enum ImageContainer { jpeg, png, webp, heic, unknown }

/// Detects photo container format and whether a photo is a spherical 360°
/// (equirectangular) capture — the format DJI Mini 4K, Insta360 and DJI 360
/// cameras write. Detection is dependency-free and never throws so a bad file
/// simply isn't treated as 360.
class PhotoFormat {
  PhotoFormat._();

  /// The container format of [bytes], or [ImageContainer.unknown] when it
  /// can't be determined from the magic header.
  static ImageContainer formatOf(Uint8List bytes) {
    if (bytes.length < 12) return ImageContainer.unknown;
    // JPEG: FF D8 FF
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return ImageContainer.jpeg;
    }
    // PNG: 89 50 4E 47 ...
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return ImageContainer.png;
    }
    // WebP: "RIFF"...."WEBP"
    if (bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return ImageContainer.webp;
    }
    // HEIC/HEIF: ...."ftyp"
    if (bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70) {
      return ImageContainer.heic;
    }
    return ImageContainer.unknown;
  }

  /// Whether [bytes] look like a spherical 360° equirectangular photo.
  ///
  /// Equirectangular 360 captures have a 2:1 width:height ratio (DJI Mini 4K,
  /// Insta360, DJI 360 all write this). We read the JPEG SOF0/SOF2 header to
  /// get dimensions without decoding the full image, then accept ratios near
  /// 2:1. Files that aren't JPEG or whose dimensions can't be read are not
  /// treated as 360.
  static bool is360Equirectangular(Uint8List bytes) {
    if (formatOf(bytes) != ImageContainer.jpeg) return false;
    final dims = _jpegDimensions(bytes);
    if (dims == null) return false;
    final width = dims.width;
    final height = dims.height;
    if (width <= 0 || height <= 0) return false;
    final ratio = width / height;
    // Equirectangular 360 is 2:1; allow tolerance for camera variances.
    return ratio >= 1.85 && ratio <= 2.15;
  }

  /// Reads JPEG dimensions from the SOF0/SOF2 frame header without decoding
  /// the image. Returns null when the layout is unexpected.
  static Size? _jpegDimensions(Uint8List bytes) {
    var offset = 2;
    while (offset + 8 <= bytes.length) {
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
      // Start of scan / end of image: no more frame headers.
      if (marker == 0xDA || marker == 0xD9) break;
      final length = (_u16Big(bytes, offset + 2));
      final segmentEnd = offset + 2 + length;
      if (length < 2 || segmentEnd > bytes.length) break;

      // SOF0 (baseline) / SOF2 (progressive) frame header.
      if (marker == 0xC0 || marker == 0xC2) {
        if (segmentEnd - offset < 7) break;
        final precision = bytes[offset + 4];
        if (precision == 0 || precision > 16) break;
        final height = _u16Big(bytes, offset + 5);
        final width = _u16Big(bytes, offset + 7);
        return Size(width.toDouble(), height.toDouble());
      }
      offset = segmentEnd;
    }
    return null;
  }

  static int _u16Big(Uint8List bytes, int offset) =>
      (bytes[offset] << 8) | bytes[offset + 1];
}

/// Lightweight dimension carrier so photo_format stays dependency-free.
class Size {
  final double width;
  final double height;
  const Size(this.width, this.height);
}
