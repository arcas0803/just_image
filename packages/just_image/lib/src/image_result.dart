import 'dart:typed_data';

/// Immutable result of an image processing operation.
///
/// ```dart
/// final result = await pipeline.execute();
/// print('${result.width}x${result.height}, ${result.sizeInBytes} bytes');
/// File('output.jpg').writeAsBytesSync(result.data);
/// ```
final class ImageResult {
  /// Encoded bytes of the resulting image.
  final Uint8List data;

  /// Width of the resulting image in pixels.
  final int width;

  /// Height of the resulting image in pixels.
  final int height;

  /// Output format used (e.g. `"jpeg"`, `"png"`, `"webp"`).
  final String format;

  const ImageResult({
    required this.data,
    required this.width,
    required this.height,
    required this.format,
  });

  /// Size of the resulting image data in bytes.
  int get sizeInBytes => data.length;
}
