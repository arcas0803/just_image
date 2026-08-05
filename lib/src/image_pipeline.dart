import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

import 'artistic_filter.dart';
import 'exceptions.dart';
import 'image_result.dart';
import 'image_source.dart';
import 'native_bridge.dart';
import 'output_config.dart';

/// Immutable, chainable image processing pipeline.
///
/// Build a sequence of operations and execute them in one pass through
/// the Rust native engine. Every method returns a new [ImagePipeline]
/// instance, so pipelines can be reused and composed.
///
/// ```dart
/// final result = await File('photo.jpg')
///     .justImage
///     .resize(1920, 1080)
///     .sharpen(1.5)
///     .encode(OutputFormat.webp, quality: 85)
///     .run();
/// ```
final class ImagePipeline {
  final ImageSource _source;
  final List<Map<String, dynamic>> _operations;
  final ImageSource? _watermarkSource;
  final OutputConfig _output;
  final bool _autoOrient;
  final bool _preserveMetadata;
  final bool _preserveIcc;

  const ImagePipeline._({
    required ImageSource source,
    List<Map<String, dynamic>>? operations,
    ImageSource? watermarkSource,
    OutputConfig? output,
    bool? autoOrient,
    bool? preserveMetadata,
    bool? preserveIcc,
  }) : _source = source,
       _operations = operations ?? const [],
       _watermarkSource = watermarkSource,
       _output = output ?? const JpegOutput(),
       _autoOrient = autoOrient ?? true,
       _preserveMetadata = preserveMetadata ?? true,
       _preserveIcc = preserveIcc ?? true;

  /// Creates a pipeline from raw image bytes.
  ImagePipeline.bytes(Uint8List bytes) : this._(source: BytesSource(bytes));

  /// Creates a pipeline from a dart:io [File].
  ImagePipeline.file(File file) : this._(source: FileSource(file));

  /// Creates a pipeline from a cross_file [XFile].
  ImagePipeline.xfile(XFile xfile) : this._(source: XFileSource(xfile));

  /// Creates a pipeline from any [ImageSource].
  const ImagePipeline.fromSource(ImageSource source)
    : _source = source,
      _operations = const [],
      _watermarkSource = null,
      _output = const JpegOutput(),
      _autoOrient = true,
      _preserveMetadata = true,
      _preserveIcc = true;

  // ────────────────────────────────
  // Configuration
  // ────────────────────────────────

  /// Sets the output format and quality.
  ///
  /// Accepts either an [OutputFormat] enum or an [OutputConfig] instance:
  /// ```dart
  /// pipeline.encode(OutputFormat.webp, quality: 85);
  /// pipeline.encode(const WebpOutput(quality: 85));
  /// ```
  ImagePipeline encode(Object output, {int? quality}) {
    final config = switch (output) {
      OutputConfig o => o,
      OutputFormat f => OutputConfig.from(f, quality),
      _ => throw ArgumentError(
        'encode() expects OutputFormat or OutputConfig, got ${output.runtimeType}',
      ),
    };
    _requireRange('quality', config.quality, 1, 100);
    return _copyWith(output: config);
  }

  /// Enables or disables automatic EXIF orientation.
  ImagePipeline autoOrient(bool enabled) => _copyWith(autoOrient: enabled);

  /// Enables or disables EXIF metadata preservation in the output.
  ImagePipeline preserveMetadata(bool enabled) =>
      _copyWith(preserveMetadata: enabled);

  /// Enables or disables ICC colour profile preservation.
  ImagePipeline preserveIcc(bool enabled) => _copyWith(preserveIcc: enabled);

  // ────────────────────────────────
  // Transforms
  // ────────────────────────────────

  /// Resizes the image using Lanczos3 interpolation.
  ImagePipeline resize(int width, int height) {
    _requirePositive('width', width);
    _requirePositive('height', height);
    return _addOperation({'type': 'resize', 'width': width, 'height': height});
  }

  /// Rectangular crop starting at ([x], [y]) with size [width]×[height].
  ImagePipeline crop(int x, int y, int width, int height) {
    _requireNonNegative('x', x);
    _requireNonNegative('y', y);
    _requirePositive('width', width);
    _requirePositive('height', height);
    return _addOperation({
      'type': 'crop',
      'x': x,
      'y': y,
      'width': width,
      'height': height,
    });
  }

  /// Free-angle rotation in degrees.
  ImagePipeline rotate(double degrees) {
    _requireFinite('degrees', degrees);
    return _addOperation({'type': 'rotate', 'degrees': degrees});
  }

  /// Flips the image horizontally.
  ImagePipeline flipHorizontal() => _addOperation({'type': 'flip_horizontal'});

  /// Flips the image vertically.
  ImagePipeline flipVertical() => _addOperation({'type': 'flip_vertical'});

  // ────────────────────────────────
  // Effects
  // ────────────────────────────────

  /// Gaussian blur with the given [sigma] radius.
  ImagePipeline blur(double sigma) {
    _requireFinite('sigma', sigma);
    if (sigma < 0) {
      throw RangeError.range(sigma, 0, null, 'sigma');
    }
    return _addOperation({'type': 'blur', 'sigma': sigma});
  }

  /// Sharpens the image using an unsharp mask.
  ImagePipeline sharpen(double amount, [double threshold = 0.0]) {
    _requireFinite('amount', amount);
    _requireFinite('threshold', threshold);
    if (amount < 0) throw RangeError.range(amount, 0, null, 'amount');
    if (threshold < 0) {
      throw RangeError.range(threshold, 0, null, 'threshold');
    }
    return _addOperation({
      'type': 'sharpen',
      'amount': amount,
      'threshold': threshold,
    });
  }

  /// Sobel edge detection.
  ImagePipeline sobel() => _addOperation({'type': 'sobel'});

  /// Brightness adjustment in the range [-1.0, 1.0].
  ImagePipeline brightness(double value) {
    _requireDoubleRange('value', value, -1, 1);
    return _addOperation({'type': 'brightness', 'value': value});
  }

  /// Contrast adjustment in the range [-1.0, 1.0].
  ImagePipeline contrast(double value) {
    _requireDoubleRange('value', value, -1, 1);
    return _addOperation({'type': 'contrast', 'value': value});
  }

  /// HSL colour adjustment.
  ImagePipeline hsl({
    double hue = 0,
    double saturation = 0,
    double lightness = 0,
  }) {
    _requireFinite('hue', hue);
    _requireDoubleRange('saturation', saturation, -1, 1);
    _requireDoubleRange('lightness', lightness, -1, 1);
    return _addOperation({
      'type': 'hsl',
      'hue': hue,
      'saturation': saturation,
      'lightness': lightness,
    });
  }

  /// Overlays a watermark image.
  ///
  /// [source] can be raw bytes, a [File] or an [XFile].
  ImagePipeline watermark(
    ImageSource source, {
    int x = 0,
    int y = 0,
    double opacity = 1.0,
  }) {
    _requireDoubleRange('opacity', opacity, 0, 1);
    return _copyWith(
      watermarkSource: source,
      operations: [
        ..._operations,
        {'type': 'watermark', 'x': x, 'y': y, 'opacity': opacity},
      ],
    );
  }

  /// Applies a named artistic filter.
  ImagePipeline filter(ArtisticFilterName filter) =>
      _addOperation({'type': 'filter', 'name': filter.jsonName});

  /// Generates a thumbnail that fits inside the given bounding box.
  ImagePipeline thumbnail(int maxWidth, int maxHeight) {
    _requirePositive('maxWidth', maxWidth);
    _requirePositive('maxHeight', maxHeight);
    return _addOperation({
      'type': 'thumbnail',
      'max_width': maxWidth,
      'max_height': maxHeight,
    });
  }

  // ────────────────────────────────
  // Execution
  // ────────────────────────────────

  /// Executes the pipeline in a background [Isolate].
  ///
  /// This is the recommended way to run the pipeline. It never blocks the
  /// event loop and is safe to use in Flutter / UI code.
  Future<ImageResult> run() async {
    final request = await _buildRequest();
    final response = await Isolate.run(() {
      final bridge = NativeBridge();
      return bridge.processPipeline(request);
    });
    return _toImageResult(response);
  }

  // ────────────────────────────────
  // Internal helpers
  // ────────────────────────────────

  ImagePipeline _addOperation(Map<String, dynamic> operation) =>
      _copyWith(operations: [..._operations, operation]);

  ImagePipeline _copyWith({
    ImageSource? source,
    List<Map<String, dynamic>>? operations,
    ImageSource? watermarkSource,
    OutputConfig? output,
    bool? autoOrient,
    bool? preserveMetadata,
    bool? preserveIcc,
  }) => ImagePipeline._(
    source: source ?? _source,
    operations: operations ?? _operations,
    watermarkSource: watermarkSource ?? _watermarkSource,
    output: output ?? _output,
    autoOrient: autoOrient ?? _autoOrient,
    preserveMetadata: preserveMetadata ?? _preserveMetadata,
    preserveIcc: preserveIcc ?? _preserveIcc,
  );

  String _buildConfigJson() {
    return jsonEncode({
      'output_format': _output.format,
      'quality': _output.quality,
      'auto_orient': _autoOrient,
      'preserve_metadata': _preserveMetadata,
      'preserve_icc': _preserveIcc,
      'operations': _operations,
    });
  }

  Future<PipelineRequest> _buildRequest() async {
    final bytes = await _source.readBytes();
    if (bytes.isEmpty) {
      throw const EmptyInputException();
    }

    Uint8List? watermarkBytes;
    final watermarkSource = _watermarkSource;
    if (watermarkSource != null) {
      watermarkBytes = await watermarkSource.readBytes();
      if (watermarkBytes.isEmpty) watermarkBytes = null;
    }

    return PipelineRequest(
      inputBytes: bytes,
      configJson: _buildConfigJson(),
      watermarkBytes: watermarkBytes,
    );
  }

  ImageResult _toImageResult(PipelineResponse response) {
    if (response.error != null) {
      throw _classifyNativeError(response.error!);
    }
    return ImageResult(
      data: response.data,
      width: response.width,
      height: response.height,
      format: ImageFormat.fromString(_output.format),
    );
  }
}

void _requirePositive(String name, int value) {
  if (value <= 0) throw RangeError.range(value, 1, null, name);
}

void _requireNonNegative(String name, int value) {
  if (value < 0) throw RangeError.range(value, 0, null, name);
}

void _requireRange(String name, int value, int min, int max) {
  if (value < min || value > max) {
    throw RangeError.range(value, min, max, name);
  }
}

void _requireFinite(String name, double value) {
  if (!value.isFinite) throw ArgumentError.value(value, name, 'must be finite');
}

void _requireDoubleRange(String name, double value, double min, double max) {
  _requireFinite(name, value);
  if (value < min || value > max) {
    throw RangeError.value(value, name, 'must be between $min and $max');
  }
}

JustImageException _classifyNativeError(String message) {
  final lower = message.toLowerCase();
  if (lower.contains('decode error') ||
      lower.contains('unsupported image format')) {
    return ImageDecodeException(message);
  }
  if (lower.contains('encode error') ||
      lower.contains('unsupported output format')) {
    return ImageEncodeException(message);
  }
  if (lower.contains('null or empty input')) {
    return const EmptyInputException();
  }
  return PipelineExecutionException(message);
}
