import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Shrinks a picked photo before it is uploaded.
///
/// Location detection reads the raw EXIF block from the original file first, so
/// re-encoding here never costs the auto-placed pin. Every failure path returns
/// the original bytes: publishing is more important than saving bytes.
Future<Uint8List> compressForUpload(Uint8List bytes) async {
  // The web build has no dependable native encoder; the browser image stays as
  // the user picked it rather than risking a corrupt upload.
  if (kIsWeb || bytes.length < 400 * 1024) return bytes;

  try {
    final compressed = await FlutterImageCompress.compressWithList(
      bytes,
      minWidth: 1600,
      minHeight: 1600,
      quality: 82,
      format: CompressFormat.jpeg,
    );
    return compressed.length < bytes.length ? compressed : bytes;
  } catch (_) {
    return bytes;
  }
}
