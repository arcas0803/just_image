/// Immutable configuration for the encoded output image.
///
/// ```dart
/// const output = WebpOutput(quality: 85);
/// ```
sealed class OutputConfig {
  const OutputConfig();

  /// Canonical format name sent to Rust (jpeg, png, webp, avif, tiff, bmp).
  String get format;

  /// Compression quality in the range [1, 100].
  int get quality;
}

/// JPEG output configuration.
final class JpegOutput extends OutputConfig {
  const JpegOutput({this.quality = 90});

  @override
  String get format => 'jpeg';

  @override
  final int quality;
}

/// PNG output configuration.
///
/// [quality] controls oxipng optimization level when < 100.
final class PngOutput extends OutputConfig {
  const PngOutput({this.quality = 100});

  @override
  String get format => 'png';

  @override
  final int quality;
}

/// WebP output configuration.
final class WebpOutput extends OutputConfig {
  const WebpOutput({this.quality = 90});

  @override
  String get format => 'webp';

  @override
  final int quality;
}

/// AVIF output configuration.
final class AvifOutput extends OutputConfig {
  const AvifOutput({this.quality = 80});

  @override
  String get format => 'avif';

  @override
  final int quality;
}

/// TIFF output configuration.
final class TiffOutput extends OutputConfig {
  const TiffOutput({this.quality = 100});

  @override
  String get format => 'tiff';

  @override
  final int quality;
}

/// BMP output configuration.
final class BmpOutput extends OutputConfig {
  const BmpOutput({this.quality = 100});

  @override
  String get format => 'bmp';

  @override
  final int quality;
}
