import 'dart:typed_data';

/// Supported image formats for [ImageResult].
enum ImageFormat {
  jpeg,
  png,
  webp,
  tiff,
  bmp;

  /// Parses a format string (e.g. `'jpeg'`) into an [ImageFormat].
  static ImageFormat fromString(String name) => switch (name) {
    'jpeg' => ImageFormat.jpeg,
    'png' => ImageFormat.png,
    'webp' => ImageFormat.webp,
    'tiff' => ImageFormat.tiff,
    'bmp' => ImageFormat.bmp,
    _ => throw ArgumentError('Unknown image format: $name'),
  };
}

/// Immutable result of an image processing operation.
///
/// ```dart
/// final result = await pipeline.run();
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

  /// Output format used.
  final ImageFormat format;

  const ImageResult({
    required this.data,
    required this.width,
    required this.height,
    required this.format,
  });

  /// Size of the resulting image data in bytes.
  int get sizeInBytes => data.length;
}
