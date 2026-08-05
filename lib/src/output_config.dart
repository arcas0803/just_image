/// Supported output image formats.
///
/// Each format has a sensible default quality. Use [encode] with a custom
/// quality to override:
///
/// ```dart
/// pipeline.encode(OutputFormat.webp, quality: 85);
/// ```
enum OutputFormat {
  /// JPEG format (lossy, default quality 90).
  jpeg(90),

  /// PNG format (lossless, quality controls oxipng optimization level).
  png(100),

  /// WebP format (lossy/lossless, default quality 90).
  webp(90),

  /// AVIF format (high efficiency, default quality 80).
  avif(80),

  /// TIFF format (lossless).
  tiff(100),

  /// BMP format (lossless, uncompressed).
  bmp(100);

  /// Default quality for this format (1–100).
  final int defaultQuality;

  const OutputFormat(this.defaultQuality);

  /// Canonical string name sent to Rust.
  String get name => switch (this) {
    OutputFormat.jpeg => 'jpeg',
    OutputFormat.png => 'png',
    OutputFormat.webp => 'webp',
    OutputFormat.avif => 'avif',
    OutputFormat.tiff => 'tiff',
    OutputFormat.bmp => 'bmp',
  };
}

/// Immutable configuration for the encoded output image.
///
/// Prefer using [OutputFormat] directly with [ImagePipeline.encode]:
/// ```dart
/// pipeline.encode(OutputFormat.webp, quality: 85);
/// ```
///
/// For backward compatibility, the sealed [OutputConfig] hierarchy is still
/// available:
/// ```dart
/// pipeline.encode(const WebpOutput(quality: 85));
/// ```
sealed class OutputConfig {
  const OutputConfig();

  /// Canonical format name sent to Rust (jpeg, png, webp, avif, tiff, bmp).
  String get format;

  /// Compression quality in the range [1, 100].
  int get quality;

  /// Constructs an [OutputConfig] from an [OutputFormat] and optional quality.
  factory OutputConfig.from(OutputFormat format, [int? quality]) {
    final q = quality ?? format.defaultQuality;
    return switch (format) {
      OutputFormat.jpeg => JpegOutput(quality: q),
      OutputFormat.png => PngOutput(quality: q),
      OutputFormat.webp => WebpOutput(quality: q),
      OutputFormat.avif => AvifOutput(quality: q),
      OutputFormat.tiff => TiffOutput(quality: q),
      OutputFormat.bmp => BmpOutput(quality: q),
    };
  }
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
