import 'package:meta/meta.dart';

import 'internal/native_pipeline_executor.dart';

/// Supported output image formats.
///
/// Each format has a sensible default quality. Use [encode] with a custom
/// quality to override:
///
/// ```dart
/// pipeline.encode(OutputFormat.webp, quality: 85);
/// ```
sealed class OutputFormat extends OutputConfig {
  const OutputFormat._();

  /// JPEG format (lossy, default quality 90).
  static const jpeg = _JpegFormat();

  /// PNG format (lossless).
  static const png = _PngFormat();

  /// WebP format (lossy/lossless, default quality 90).
  static const webp = _WebpFormat();

  /// TIFF format (lossless).
  static const tiff = _TiffFormat();

  /// BMP format (lossless, uncompressed).
  static const bmp = _BmpFormat();

  /// AVIF format (lossy, default quality 80).
  static const avif = _AvifFormat();

  /// Every supported output format.
  static const values = [jpeg, png, webp, tiff, bmp, avif];

  /// Default quality for this format (1–100).
  int get defaultQuality;

  /// Canonical name sent to the native engine.
  String get name => format;

  @override
  int get quality => defaultQuality;

  /// Creates the matching typed configuration with a custom quality.
  OutputConfig withQuality(int quality);
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

  /// Canonical format name sent to Rust.
  String get format;

  /// Compression quality in the range [1, 100].
  int get quality;

  /// Format-specific encoder settings serialized for the native backend.
  @internal
  Map<String, Object?> get options => const {};

  /// Selects the smallest native feature group required by this output.
  @internal
  NativePipelineExecutor upgradeExecutor(NativePipelineExecutor current);

  /// Constructs an [OutputConfig] from an [OutputFormat] and optional quality.
  factory OutputConfig.from(OutputFormat format, [int? quality]) =>
      quality == null ? format : format.withQuality(quality);
}

final class _JpegFormat extends OutputFormat {
  const _JpegFormat() : super._();
  @override
  String get format => 'jpeg';
  @override
  int get defaultQuality => 90;
  @override
  OutputConfig withQuality(int quality) => JpegOutput(quality: quality);
  @override
  NativePipelineExecutor upgradeExecutor(NativePipelineExecutor current) =>
      current;
}

final class _PngFormat extends OutputFormat {
  const _PngFormat() : super._();
  @override
  String get format => 'png';
  @override
  int get defaultQuality => 100;
  @override
  OutputConfig withQuality(int quality) => PngOutput(quality: quality);
  @override
  NativePipelineExecutor upgradeExecutor(NativePipelineExecutor current) =>
      current;
}

final class _WebpFormat extends OutputFormat {
  const _WebpFormat() : super._();
  @override
  String get format => 'webp';
  @override
  int get defaultQuality => 90;
  @override
  OutputConfig withQuality(int quality) => WebpOutput(quality: quality);
  @override
  NativePipelineExecutor upgradeExecutor(NativePipelineExecutor current) =>
      requireStandard(current);
}

final class _TiffFormat extends OutputFormat {
  const _TiffFormat() : super._();
  @override
  String get format => 'tiff';
  @override
  int get defaultQuality => 100;
  @override
  OutputConfig withQuality(int quality) => TiffOutput(quality: quality);
  @override
  NativePipelineExecutor upgradeExecutor(NativePipelineExecutor current) =>
      requireStandard(current);
}

final class _BmpFormat extends OutputFormat {
  const _BmpFormat() : super._();
  @override
  String get format => 'bmp';
  @override
  int get defaultQuality => 100;
  @override
  OutputConfig withQuality(int quality) => BmpOutput(quality: quality);
  @override
  NativePipelineExecutor upgradeExecutor(NativePipelineExecutor current) =>
      current;
}

final class _AvifFormat extends OutputFormat {
  const _AvifFormat() : super._();
  @override
  String get format => 'avif';
  @override
  int get defaultQuality => 80;
  @override
  OutputConfig withQuality(int quality) => AvifOutput(quality: quality);
  @override
  NativePipelineExecutor upgradeExecutor(NativePipelineExecutor current) =>
      requireExtended(current);
}

/// JPEG output configuration.
final class JpegOutput extends OutputConfig {
  const JpegOutput({this.quality = 90});

  @override
  String get format => 'jpeg';

  @override
  final int quality;

  @override
  NativePipelineExecutor upgradeExecutor(NativePipelineExecutor current) =>
      current;
}

/// PNG compression strategy.
enum PngCompression { fast, balanced, best }

/// PNG scanline filter strategy.
enum PngFilter { adaptive, none, sub, up, average, paeth }

/// PNG output configuration.
///
/// [quality] controls oxipng optimization level when < 100.
final class PngOutput extends OutputConfig {
  const PngOutput({
    this.quality = 100,
    this.compression = PngCompression.balanced,
    this.filter = PngFilter.adaptive,
    this.optimizationLevel = 0,
  });

  @override
  String get format => 'png';

  @override
  final int quality;

  /// Deflate compression effort.
  final PngCompression compression;

  /// Scanline filter selection strategy.
  final PngFilter filter;

  /// oxipng preset from 0 (disabled) to 6 (smallest/slower).
  final int optimizationLevel;

  @override
  Map<String, Object?> get options => {
    'png_compression': compression.name,
    'png_filter': filter.name,
    'png_optimization': optimizationLevel,
  };

  @override
  NativePipelineExecutor upgradeExecutor(NativePipelineExecutor current) =>
      current;
}

/// WebP output configuration.
final class WebpOutput extends OutputConfig {
  const WebpOutput({this.quality = 90}) : lossless = false;

  const WebpOutput.lossless() : quality = 100, lossless = true;

  @override
  String get format => 'webp';

  @override
  final int quality;

  /// Whether the lossless WebP encoder is used.
  final bool lossless;

  @override
  Map<String, Object?> get options => {'webp_lossless': lossless};

  @override
  NativePipelineExecutor upgradeExecutor(NativePipelineExecutor current) =>
      requireStandard(current);
}

/// TIFF output configuration.
final class TiffOutput extends OutputConfig {
  const TiffOutput({this.quality = 100});

  @override
  String get format => 'tiff';

  @override
  final int quality;

  @override
  NativePipelineExecutor upgradeExecutor(NativePipelineExecutor current) =>
      requireStandard(current);
}

/// BMP output configuration.
final class BmpOutput extends OutputConfig {
  const BmpOutput({this.quality = 100});

  @override
  String get format => 'bmp';

  @override
  final int quality;

  @override
  NativePipelineExecutor upgradeExecutor(NativePipelineExecutor current) =>
      current;
}

/// AVIF output configuration.
final class AvifOutput extends OutputConfig {
  const AvifOutput({this.quality = 80, this.speed = 6, this.threads});

  @override
  String get format => 'avif';

  @override
  final int quality;

  /// Encoder speed from 1 (slowest/smallest) to 10 (fastest).
  final int speed;

  /// Optional encoder thread count. `null` uses the native default.
  final int? threads;

  @override
  Map<String, Object?> get options => {
    'avif_speed': speed,
    if (threads != null) 'avif_threads': threads,
  };

  @override
  NativePipelineExecutor upgradeExecutor(NativePipelineExecutor current) =>
      requireExtended(current);
}
