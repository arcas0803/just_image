import 'dart:isolate';
import 'dart:typed_data';

import 'batch_queue.dart';
import 'exceptions.dart';
import 'image_format.dart';
import 'image_pipeline.dart';
import 'image_result.dart';
import 'native_bridge.dart';

/// High-level image processing engine.
///
/// This is the main entry point for the just_image package. It wraps
/// the native bridge, pipeline creation, and batch processing into a
/// single, convenient API.
///
/// ```dart
/// final engine = JustImageEngine();
///
/// // Quick one-shot processing:
/// final result = await engine.process(
///   imageBytes,
///   width: 800,
///   height: 600,
///   format: ImageFormat.webp,
/// );
///
/// // Or use the full pipeline:
/// final result2 = await engine
///     .load(imageBytes)
///     .resize(1920, 1080)
///     .sharpen(1.5)
///     .toFormat(ImageFormat.avif)
///     .execute();
///
/// engine.dispose();
/// ```
class JustImageEngine {
  late final NativeBridge _bridge;
  BatchQueue? _batchQueue;

  JustImageEngine() {
    _bridge = NativeBridge();
  }

  /// Version string of the underlying Rust native library.
  String get nativeVersion => _bridge.nativeVersion;

  /// Creates a new processing pipeline from raw image bytes.
  ///
  /// ```dart
  /// final pipeline = engine.load(imageBytes);
  /// final result = await pipeline.resize(800, 600).execute();
  /// ```
  ImagePipeline load(Uint8List bytes) => ImagePipeline(bytes);

  /// Returns the batch processing queue, creating one if needed.
  ///
  /// ```dart
  /// final future = engine.batch.enqueue(pipeline);
  /// ```
  BatchQueue get batch {
    _batchQueue ??= BatchQueue();
    return _batchQueue!;
  }

  /// Creates a new batch queue with custom concurrency.
  ///
  /// Replaces any previously created queue.
  ///
  /// ```dart
  /// final queue = engine.createBatch(concurrency: 8);
  /// final results = await Future.wait([
  ///   queue.enqueue(pipeline1),
  ///   queue.enqueue(pipeline2),
  /// ]);
  /// ```
  BatchQueue createBatch({int concurrency = 4}) {
    _batchQueue?.dispose();
    _batchQueue = BatchQueue(concurrency: concurrency);
    return _batchQueue!;
  }

  /// Quick one-shot processing: load, transform, and return in a
  /// single async call.
  ///
  /// ```dart
  /// final result = await engine.process(
  ///   imageBytes,
  ///   width: 800,
  ///   height: 600,
  ///   format: ImageFormat.webp,
  ///   quality: 85,
  /// );
  /// ```
  Future<ImageResult> process(
    Uint8List bytes, {
    int? width,
    int? height,
    ImageFormat format = ImageFormat.jpeg,
    int quality = 90,
  }) {
    var pipeline = load(bytes).toFormat(format).quality(quality);
    if (width != null && height != null) {
      pipeline = pipeline.resize(width, height);
    }
    return pipeline.execute();
  }

  /// Releases resources held by the engine.
  void dispose() {
    _batchQueue?.dispose();
  }

  /// List of available artistic filter names.
  ///
  /// ```dart
  /// print(engine.availableFilters);
  /// // [vintage, sepia, cool, warm, marine, dramatic, lomo, retro,
  /// //  noir, bloom, polaroid, golden_hour, arctic, cinematic, fade]
  /// ```
  List<String> get availableFilters => _bridge.availableFilters;

  /// Encodes an image into a BlurHash string.
  ///
  /// [componentsX] and [componentsY] control the hash complexity
  /// (typically 4×3). Runs in a background [Isolate].
  ///
  /// ```dart
  /// final hash = await engine.blurHashEncode(imageBytes);
  /// print(hash); // e.g. "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
  /// ```
  Future<String> blurHashEncode(
    Uint8List bytes, {
    int componentsX = 4,
    int componentsY = 3,
  }) async {
    final cx = componentsX;
    final cy = componentsY;
    final input = bytes;

    final response = await Isolate.run(() {
      final bridge = NativeBridge();
      return bridge.blurHashEncode(input, componentsX: cx, componentsY: cy);
    });

    if (response.error != null) {
      throw PipelineExecutionException(response.error!);
    }

    return String.fromCharCodes(response.data);
  }

  /// Decodes a BlurHash string into PNG image bytes.
  ///
  /// [width] and [height] set the output dimensions. Use small sizes
  /// (e.g. 32×32) for lightweight placeholders. Runs in a background
  /// [Isolate].
  ///
  /// ```dart
  /// final placeholder = await engine.blurHashDecode(
  ///   'LEHV6nWB2yk8pyo0adR*.7kCMdnj',
  ///   width: 32,
  ///   height: 32,
  /// );
  /// // placeholder.data contains PNG bytes
  /// ```
  Future<ImageResult> blurHashDecode(
    String hash, {
    int width = 32,
    int height = 32,
  }) async {
    final h = hash;
    final w = width;
    final hh = height;

    final response = await Isolate.run(() {
      final bridge = NativeBridge();
      return bridge.blurHashDecode(h, w, hh);
    });

    if (response.error != null) {
      throw PipelineExecutionException(response.error!);
    }

    return ImageResult(
      data: response.data,
      width: response.width,
      height: response.height,
      format: 'png',
    );
  }
}
