import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'exceptions.dart';
import 'image_format.dart';
import 'image_result.dart';
import 'native_bridge.dart';

/// Fluent, chainable image processing pipeline.
///
/// Build a sequence of operations and execute them in one pass through
/// the Rust native engine. Every method returns `this`, so you can
/// chain calls naturally.
///
/// ```dart
/// final result = await ImagePipeline(bytes)
///     .resize(1920, 1080)
///     .sharpen(1.5)
///     .toFormat(ImageFormat.avif)
///     .execute();
/// ```
class ImagePipeline {
  final Uint8List _inputBytes;
  final List<Map<String, dynamic>> _operations = [];
  Uint8List? _watermarkBytes;
  String _outputFormat = 'jpeg';
  int _quality = 90;
  bool _autoOrient = true;
  bool _preserveMetadata = true;
  bool _preserveIcc = true;

  /// Creates a pipeline from raw image bytes.
  ImagePipeline(this._inputBytes);

  // ────────────────────────────────
  // Configuration
  // ────────────────────────────────

  /// Sets the output format.
  ///
  /// ```dart
  /// pipeline.toFormat(ImageFormat.webp);
  /// ```
  ImagePipeline toFormat(ImageFormat format) {
    _outputFormat = format.value;
    return this;
  }

  /// Compression quality (1–100).
  ///
  /// ```dart
  /// pipeline.quality(85);
  /// ```
  ImagePipeline quality(int q) {
    _quality = q.clamp(1, 100);
    return this;
  }

  /// Enables or disables automatic EXIF orientation.
  ///
  /// When enabled (the default), the image is rotated according to its
  /// EXIF orientation tag before any other operations.
  ///
  /// ```dart
  /// pipeline.autoOrient(false); // keep raw orientation
  /// ```
  ImagePipeline autoOrient(bool enabled) {
    _autoOrient = enabled;
    return this;
  }

  /// Enables or disables EXIF metadata preservation in the output.
  ///
  /// ```dart
  /// pipeline.preserveMetadata(false); // strip all EXIF data
  /// ```
  ImagePipeline preserveMetadata(bool enabled) {
    _preserveMetadata = enabled;
    return this;
  }

  /// Enables or disables ICC colour profile preservation.
  ///
  /// ```dart
  /// pipeline.preserveIcc(true);
  /// ```
  ImagePipeline preserveIcc(bool enabled) {
    _preserveIcc = enabled;
    return this;
  }

  // ────────────────────────────────
  // Transforms
  // ────────────────────────────────

  /// Resizes the image using Lanczos3 interpolation.
  ///
  /// ```dart
  /// pipeline.resize(800, 600);
  /// ```
  ImagePipeline resize(int width, int height) {
    _operations.add({'type': 'resize', 'width': width, 'height': height});
    return this;
  }

  /// Rectangular crop.
  ///
  /// Crops to the region starting at ([x], [y]) with size
  /// [width]×[height] pixels.
  ///
  /// ```dart
  /// pipeline.crop(100, 50, 640, 480);
  /// ```
  ImagePipeline crop(int x, int y, int width, int height) {
    _operations.add({
      'type': 'crop',
      'x': x,
      'y': y,
      'width': width,
      'height': height,
    });
    return this;
  }

  /// Free-angle rotation in degrees.
  ///
  /// The canvas is expanded to fit the rotated image; empty corners
  /// are filled with transparency (if the format supports it).
  ///
  /// ```dart
  /// pipeline.rotate(45);
  /// ```
  ImagePipeline rotate(double degrees) {
    _operations.add({'type': 'rotate', 'degrees': degrees});
    return this;
  }

  /// Flips the image horizontally or vertically.
  ///
  /// ```dart
  /// pipeline.flip(FlipDirection.horizontal);
  /// ```
  ImagePipeline flip(FlipDirection direction) {
    _operations.add({
      'type': direction == FlipDirection.horizontal
          ? 'flip_horizontal'
          : 'flip_vertical',
    });
    return this;
  }

  // ────────────────────────────────
  // Effects
  // ────────────────────────────────

  /// Gaussian blur with the given [sigma] radius.
  ///
  /// ```dart
  /// pipeline.blur(3.0);
  /// ```
  ImagePipeline blur(double sigma) {
    _operations.add({'type': 'blur', 'sigma': sigma});
    return this;
  }

  /// Sharpens the image using an unsharp mask.
  ///
  /// [amount] controls intensity (typically 0.5–3.0), and [threshold]
  /// sets the minimum brightness difference to sharpen (0.0 = sharpen
  /// everything).
  ///
  /// ```dart
  /// pipeline.sharpen(1.5);          // default threshold
  /// pipeline.sharpen(2.0, 0.5);     // with threshold
  /// ```
  ImagePipeline sharpen(double amount, [double threshold = 0.0]) {
    _operations.add({
      'type': 'sharpen',
      'amount': amount,
      'threshold': threshold,
    });
    return this;
  }

  /// Sobel edge detection.
  ///
  /// Converts the image to a greyscale edge map.
  ///
  /// ```dart
  /// pipeline.sobel();
  /// ```
  ImagePipeline sobel() {
    _operations.add({'type': 'sobel'});
    return this;
  }

  /// Brightness adjustment in the range [−1.0, 1.0].
  ///
  /// Positive values brighten, negative values darken.
  ///
  /// ```dart
  /// pipeline.brightness(0.15);   // slightly brighter
  /// pipeline.brightness(-0.2);   // darker
  /// ```
  ImagePipeline brightness(double value) {
    _operations.add({'type': 'brightness', 'value': value});
    return this;
  }

  /// Contrast adjustment in the range [−1.0, 1.0].
  ///
  /// ```dart
  /// pipeline.contrast(0.3);  // more contrast
  /// ```
  ImagePipeline contrast(double value) {
    _operations.add({'type': 'contrast', 'value': value});
    return this;
  }

  /// HSL colour adjustment.
  ///
  /// [hue] is a rotation in degrees (0–360), [saturation] and
  /// [lightness] are offsets in the range [−1.0, 1.0].
  ///
  /// ```dart
  /// pipeline.hsl(hue: 15, saturation: 0.1, lightness: 0.05);
  /// ```
  ImagePipeline hsl({
    double hue = 0,
    double saturation = 0,
    double lightness = 0,
  }) {
    _operations.add({
      'type': 'hsl',
      'hue': hue,
      'saturation': saturation,
      'lightness': lightness,
    });
    return this;
  }

  /// Overlays a watermark image.
  ///
  /// [overlayBytes] are the raw bytes of the watermark image.
  /// [x] and [y] set the position, [opacity] controls blending
  /// (0.0 = transparent, 1.0 = fully opaque).
  ///
  /// ```dart
  /// final watermark = File('logo.png').readAsBytesSync();
  /// pipeline.watermark(watermark, x: 10, y: 10, opacity: 0.6);
  /// ```
  ImagePipeline watermark(
    Uint8List overlayBytes, {
    int x = 0,
    int y = 0,
    double opacity = 1.0,
  }) {
    _watermarkBytes = overlayBytes;
    _operations.add({'type': 'watermark', 'x': x, 'y': y, 'opacity': opacity});
    return this;
  }

  /// Applies a named artistic filter.
  ///
  /// Available filters: `vintage`, `sepia`, `cool`, `warm`, `marine`,
  /// `dramatic`, `lomo`, `retro`, `noir`, `bloom`, `polaroid`,
  /// `golden_hour`, `arctic`, `cinematic`, `fade`.
  ///
  /// ```dart
  /// pipeline.filter('cinematic');
  /// ```
  ImagePipeline filter(String name) {
    _operations.add({'type': 'filter', 'name': name});
    return this;
  }

  /// Generates a thumbnail that fits inside the given bounding box
  /// while preserving the aspect ratio.
  ///
  /// ```dart
  /// pipeline.thumbnail(200, 200);
  /// ```
  ImagePipeline thumbnail(int maxWidth, int maxHeight) {
    _operations.add({
      'type': 'thumbnail',
      'max_width': maxWidth,
      'max_height': maxHeight,
    });
    return this;
  }

  // ────────────────────────────────
  // Execution
  // ────────────────────────────────

  /// Builds the JSON configuration for the pipeline.
  String _buildConfigJson() {
    final config = {
      'output_format': _outputFormat,
      'quality': _quality,
      'auto_orient': _autoOrient,
      'preserve_metadata': _preserveMetadata,
      'preserve_icc': _preserveIcc,
      'operations': _operations,
    };
    return jsonEncode(config);
  }

  /// Executes the pipeline synchronously (blocks the current thread).
  ///
  /// **Only use in isolates or CLI scripts.** For Flutter / UI code,
  /// use [execute] instead.
  ///
  /// ```dart
  /// // Inside a Dart CLI script:
  /// final result = ImagePipeline(bytes)
  ///     .resize(800, 600)
  ///     .toFormat(ImageFormat.jpeg)
  ///     .executeSync();
  /// ```
  ImageResult executeSync() {
    if (_inputBytes.isEmpty) {
      throw const EmptyInputException();
    }

    final bridge = NativeBridge();
    final request = PipelineRequest(
      inputBytes: _inputBytes,
      configJson: _buildConfigJson(),
      watermarkBytes: _watermarkBytes,
    );

    final response = bridge.processPipeline(request);

    if (response.error != null) {
      throw _classifyNativeError(response.error!);
    }

    return ImageResult(
      data: response.data,
      width: response.width,
      height: response.height,
      format: _outputFormat,
    );
  }

  /// Executes the pipeline in a background [Isolate].
  ///
  /// This is the **recommended** way to run the pipeline. The heavy
  /// Rust processing runs off the main thread, keeping the UI
  /// responsive.
  ///
  /// ```dart
  /// final result = await ImagePipeline(bytes)
  ///     .resize(1920, 1080)
  ///     .sharpen(1.5)
  ///     .toFormat(ImageFormat.webp)
  ///     .quality(85)
  ///     .execute();
  ///
  /// File('output.webp').writeAsBytesSync(result.data);
  /// ```
  Future<ImageResult> execute() async {
    final configJson = _buildConfigJson();
    final watermark = _watermarkBytes;
    final input = _inputBytes;
    final format = _outputFormat;

    final response = await Isolate.run(() {
      final bridge = NativeBridge();
      final request = PipelineRequest(
        inputBytes: input,
        configJson: configJson,
        watermarkBytes: watermark,
      );
      return bridge.processPipeline(request);
    });

    if (response.error != null) {
      throw _classifyNativeError(response.error!);
    }

    return ImageResult(
      data: response.data,
      width: response.width,
      height: response.height,
      format: format,
    );
  }
}

/// Maps a native error message to the appropriate exception class.
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
