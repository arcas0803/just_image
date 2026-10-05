import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

import 'artistic_filter.dart';
import 'exceptions.dart';
import 'image_result.dart';
import 'image_source.dart';
import 'internal/native_pipeline_executor.dart';
import 'native_bridge.dart';
import 'output_config.dart';

/// Metadata handling policy for encoded images.
enum MetadataPolicy {
  /// Remove EXIF/XMP metadata from the output.
  none,

  /// Preserve useful photographic metadata while removing sensitive fields.
  safe,

  /// Preserve all supported metadata, including GPS information.
  preserveAll,
}

/// Canvas behavior for rotations that are not multiples of 90 degrees.
enum RotationCanvas { clip, expand }

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
  final MetadataPolicy _metadataPolicy;
  final bool _preserveIcc;
  final String _inputFormat;
  final int? _svgWidth;
  final int? _svgHeight;
  final NativePipelineExecutor _executor;

  const ImagePipeline._({
    required this._source,
    List<Map<String, dynamic>>? operations,
    this._watermarkSource,
    OutputConfig? output,
    bool? autoOrient,
    MetadataPolicy? metadataPolicy,
    bool? preserveIcc,
    String? inputFormat,
    this._svgWidth,
    this._svgHeight,
    NativePipelineExecutor? executor,
  }) : _operations = operations ?? const [],
       _output = output ?? const JpegOutput(),
       _autoOrient = autoOrient ?? false,
       _metadataPolicy = metadataPolicy ?? MetadataPolicy.none,
       _preserveIcc = preserveIcc ?? false,
       _inputFormat = inputFormat ?? 'auto',
       _executor = executor ?? const CorePipelineExecutor();

  /// Creates a pipeline from raw image bytes.
  ImagePipeline.bytes(Uint8List bytes) : this._(source: BytesSource(bytes));

  /// Creates a pipeline from a dart:io [File].
  ImagePipeline.file(File file) : this._(source: FileSource(file));

  /// Creates a pipeline from a cross_file [XFile].
  ImagePipeline.xfile(XFile xfile) : this._(source: XFileSource(xfile));

  /// Creates a pipeline from explicitly typed AVIF input.
  ImagePipeline.avif(ImageSource source)
    : this._(
        source: source,
        inputFormat: 'avif',
        executor: const ExtendedPipelineExecutor(),
      );

  /// Creates a pipeline from SVG input rasterized at its intrinsic size or
  /// the optional requested dimensions.
  factory ImagePipeline.svg(ImageSource source, {int? width, int? height}) {
    if (width != null) _requirePositive('width', width);
    if (height != null) _requirePositive('height', height);
    return ImagePipeline._(
      source: source,
      inputFormat: 'svg',
      svgWidth: width,
      svgHeight: height,
      executor: const ExtendedPipelineExecutor(),
    );
  }

  /// Creates a pipeline from any [ImageSource].
  const ImagePipeline.fromSource(ImageSource source)
    : _source = source,
      _operations = const [],
      _watermarkSource = null,
      _output = const JpegOutput(),
      _autoOrient = false,
      _metadataPolicy = MetadataPolicy.none,
      _preserveIcc = false,
      _inputFormat = 'auto',
      _svgWidth = null,
      _svgHeight = null,
      _executor = const CorePipelineExecutor();

  // ────────────────────────────────
  // Configuration
  // ────────────────────────────────

  /// Sets the output format and quality.
  ///
  /// Accepts either an [OutputFormat] value or an [OutputConfig] instance:
  /// ```dart
  /// pipeline.encode(OutputFormat.webp, quality: 85);
  /// pipeline.encode(const WebpOutput(quality: 85));
  /// ```
  ImagePipeline encode(OutputConfig output, {int? quality}) {
    final config = output is OutputFormat && quality != null
        ? output.withQuality(quality)
        : output;
    _requireRange('quality', config.quality, 1, 100);
    if (config is PngOutput) {
      _requireRange('optimizationLevel', config.optimizationLevel, 0, 6);
    }
    if (config is AvifOutput) {
      _requireRange('speed', config.speed, 1, 10);
      if (config.threads != null) {
        _requirePositive('threads', config.threads!);
      }
    }
    return _copyWith(
      output: config,
      executor: config.upgradeExecutor(_executor),
    );
  }

  /// Enables or disables automatic EXIF orientation.
  ImagePipeline autoOrient(bool enabled) => _copyWith(
    autoOrient: enabled,
    executor: enabled ? requireStandard(_executor) : _executor,
  );

  /// Enables or disables EXIF metadata preservation in the output.
  ImagePipeline preserveMetadata(bool enabled) => metadataPolicy(
    enabled ? MetadataPolicy.preserveAll : MetadataPolicy.none,
  );

  /// Selects how EXIF/XMP metadata is handled in the output.
  ImagePipeline metadataPolicy(MetadataPolicy policy) => _copyWith(
    metadataPolicy: policy,
    executor: policy == MetadataPolicy.none
        ? _executor
        : requireStandard(_executor),
  );

  /// Enables or disables ICC colour profile preservation.
  ImagePipeline preserveIcc(bool enabled) => _copyWith(
    preserveIcc: enabled,
    executor: enabled ? requireStandard(_executor) : _executor,
  );

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
  ImagePipeline rotate(
    double degrees, {
    RotationCanvas canvas = RotationCanvas.expand,
    int background = 0x00000000,
  }) {
    _requireFinite('degrees', degrees);
    _requireRange('background', background, 0, 0xffffffff);
    return _addOperation({
      'type': 'rotate',
      'degrees': degrees,
      'canvas': canvas.name,
      'background': background,
    });
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
      executor: requireStandard(_executor),
      operations: [
        ..._operations,
        {'type': 'watermark', 'x': x, 'y': y, 'opacity': opacity},
      ],
    );
  }

  /// Applies a named artistic filter.
  ImagePipeline filter(ArtisticFilterName filter) => _copyWith(
    operations: [
      ..._operations,
      {'type': 'filter', 'name': filter.jsonName},
    ],
    executor: requireStandard(_executor),
  );

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
    final executor = _executor;
    final response = await Isolate.run(() {
      final bridge = NativeBridge();
      return executor.process(bridge, request);
    });
    return _toImageResult(response);
  }

  /// Executes the tree-shakeable core pipeline.
  ///
  /// The core ABI supports JPEG, PNG and BMP together with transforms,
  /// thumbnails and built-in effects. It deliberately disables EXIF/ICC
  /// preservation and rejects WebP, TIFF, watermarks and artistic filters so
  /// those native feature groups can disappear from a release bundle.
  @Deprecated('Tree shaking is automatic; use run().')
  Future<ImageResult> runCore() async {
    _validateCorePipeline();
    return run();
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
    MetadataPolicy? metadataPolicy,
    bool? preserveIcc,
    NativePipelineExecutor? executor,
  }) => ImagePipeline._(
    source: source ?? _source,
    operations: operations ?? _operations,
    watermarkSource: watermarkSource ?? _watermarkSource,
    output: output ?? _output,
    autoOrient: autoOrient ?? _autoOrient,
    metadataPolicy: metadataPolicy ?? _metadataPolicy,
    preserveIcc: preserveIcc ?? _preserveIcc,
    inputFormat: _inputFormat,
    svgWidth: _svgWidth,
    svgHeight: _svgHeight,
    executor: executor ?? _executor,
  );

  String _buildConfigJson() {
    return jsonEncode({
      'output_format': _output.format,
      'quality': _output.quality,
      ..._output.options,
      'input_format': _inputFormat,
      if (_svgWidth != null) 'svg_width': _svgWidth,
      if (_svgHeight != null) 'svg_height': _svgHeight,
      'auto_orient': _autoOrient,
      'metadata_policy': _metadataPolicy.name,
      'preserve_metadata': _metadataPolicy != MetadataPolicy.none,
      'preserve_icc': _preserveIcc,
      'operations': _operations,
    });
  }

  void _validateCorePipeline() {
    if (_executor is! CorePipelineExecutor) {
      throw UnsupportedError(
        'This pipeline requires optional native features; use run(), which '
        'selects them automatically.',
      );
    }
  }

  Future<PipelineRequest> _buildRequest({String? configJson}) async {
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
      inputData: TransferableTypedData.fromList([bytes]),
      configJson: configJson ?? _buildConfigJson(),
      watermarkData: watermarkBytes == null
          ? null
          : TransferableTypedData.fromList([watermarkBytes]),
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
