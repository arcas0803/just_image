import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

import 'exceptions.dart';
import 'image_pipeline.dart';
import 'image_result.dart';
import 'image_source.dart';
import 'native_bridge.dart';
import 'output_config.dart';

export 'image_result.dart' show ImageFormat;

/// High-level static API for the just_image package.
///
/// Use this class for one-shot operations, BlurHash, image info, and batch
/// processing. For fluent pipelines, prefer the `.justImage` extension on
/// [File], [XFile] or [Uint8List].
///
/// ```dart
/// final hash = await JustImage.blurHashEncode(
///   FileSource(File('photo.jpg')),
/// );
/// final info = await JustImage.info(XFileSource(xfile));
/// final results = await JustImage.processBatch([
///   file1.justImage.resize(100, 100).encode(const JpegOutput()),
///   file2.justImage.resize(100, 100).encode(const JpegOutput()),
/// ], concurrency: 4);
/// ```
final class JustImage {
  const JustImage._();

  /// Quick one-shot processing: load, resize and encode.
  static Future<ImageResult> process(
    ImageSource source, {
    int? width,
    int? height,
    OutputConfig output = const JpegOutput(),
  }) async {
    if ((width == null) != (height == null)) {
      throw ArgumentError('width and height must be provided together');
    }
    var pipeline = ImagePipeline.fromSource(source).encode(output);
    if (width != null && height != null) {
      pipeline = pipeline.resize(width, height);
    }
    return pipeline.run();
  }

  /// Encodes an image into a BlurHash string.
  static Future<String> blurHashEncode(
    ImageSource source, {
    int componentsX = 4,
    int componentsY = 3,
  }) async {
    if (componentsX < 1 || componentsX > 9) {
      throw RangeError.range(componentsX, 1, 9, 'componentsX');
    }
    if (componentsY < 1 || componentsY > 9) {
      throw RangeError.range(componentsY, 1, 9, 'componentsY');
    }
    final bytes = await source.readBytes();
    if (bytes.isEmpty) throw const EmptyInputException();
    final response = await Isolate.run(() {
      final bridge = NativeBridge();
      return bridge.blurHashEncode(
        bytes,
        componentsX: componentsX,
        componentsY: componentsY,
      );
    });

    if (response.error != null) {
      throw PipelineExecutionException(response.error!);
    }
    return utf8.decode(response.data);
  }

  /// Decodes a BlurHash string into a PNG image.
  static Future<ImageResult> blurHashDecode(
    String hash, {
    int width = 32,
    int height = 32,
  }) async {
    if (width <= 0) throw RangeError.range(width, 1, null, 'width');
    if (height <= 0) throw RangeError.range(height, 1, null, 'height');
    final response = await Isolate.run(() {
      final bridge = NativeBridge();
      return bridge.blurHashDecode(hash, width, height);
    });

    if (response.error != null) {
      throw PipelineExecutionException(response.error!);
    }
    return ImageResult(
      data: response.data,
      width: response.width,
      height: response.height,
      format: ImageFormat.png,
    );
  }

  /// Reads basic metadata (width, height) from an image source.
  static Future<ImageInfo> info(ImageSource source) async {
    final bytes = await source.readBytes();
    if (bytes.isEmpty) throw const EmptyInputException();
    final response = await Isolate.run(() {
      final bridge = NativeBridge();
      return bridge.imageInfo(bytes);
    });

    if (response.error != null) {
      throw ImageDecodeException(response.error!);
    }

    final json = response.data.isEmpty
        ? <String, dynamic>{}
        : (jsonDecode(utf8.decode(response.data)) as Map<String, dynamic>);

    return ImageInfo(
      width: (json['width'] as int?) ?? response.width,
      height: (json['height'] as int?) ?? response.height,
    );
  }

  /// Processes a list of pipelines in parallel, preserving order.
  ///
  /// If a pipeline fails, the error is captured in the [BatchResult.errors]
  /// list instead of aborting the entire batch. The corresponding result
  /// entry will be `null`.
  static Future<BatchResult> processBatch(
    List<ImagePipeline> pipelines, {
    int concurrency = 4,
  }) async {
    if (concurrency <= 0) {
      throw RangeError.range(concurrency, 1, null, 'concurrency');
    }
    final results = List<ImageResult?>.filled(pipelines.length, null);
    final errors = List<JustImageException?>.filled(pipelines.length, null);
    final futures = <Future<void>>[];
    final semaphore = _Semaphore(concurrency);

    for (var i = 0; i < pipelines.length; i++) {
      await semaphore.acquire();
      final index = i;
      futures.add(
        pipelines[index]
            .run()
            .then((result) {
              results[index] = result;
            })
            .catchError((e) {
              errors[index] = e is JustImageException
                  ? e
                  : PipelineExecutionException(e.toString());
            })
            .whenComplete(semaphore.release),
      );
    }

    await Future.wait(futures);
    return BatchResult(results: results, errors: errors);
  }
}

/// Result of a batch processing operation.
///
/// Contains both successful results and errors, allowing partial success
/// handling. The [errors] list is parallel to [results] — if `results[i]`
/// is `null`, then `errors[i]` contains the exception.
final class BatchResult {
  /// Successful results (null for failed items).
  final List<ImageResult?> results;

  /// Errors for failed items (null for successful items).
  final List<JustImageException?> errors;

  const BatchResult({required this.results, required this.errors});

  /// Number of successfully processed pipelines.
  int get successCount => results.where((r) => r != null).length;

  /// Number of failed pipelines.
  int get failureCount => errors.where((e) => e != null).length;

  /// Whether all pipelines succeeded.
  bool get allSucceeded => failureCount == 0;

  /// Returns only the successful results.
  List<ImageResult> get successful => results.whereType<ImageResult>().toList();
}

/// Basic image metadata returned by [JustImage.info].
final class ImageInfo {
  final int width;
  final int height;

  const ImageInfo({required this.width, required this.height});
}

class _Semaphore {
  final int max;
  int _count = 0;
  final _waiters = <Completer<void>>[];

  _Semaphore(this.max);

  Future<void> acquire() async {
    if (_count < max) {
      _count++;
      return;
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      final completer = _waiters.removeAt(0);
      completer.complete();
    } else if (_count > 0) {
      _count--;
    }
  }
}
