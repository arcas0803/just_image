// Example: Using just_image_flutter in a Flutter app.
//
// This file demonstrates how to use the just_image API in Flutter.
// The Rust native library is compiled and bundled automatically via
// Native Assets — no platform-specific configuration required.

import 'dart:io';
import 'dart:typed_data';

import 'package:just_image_flutter/just_image_flutter.dart';

/// Process an image file using the just_image pipeline.
Future<void> processImage(String inputPath, String outputPath) async {
  final bytes = File(inputPath).readAsBytesSync();

  final result = await ImagePipeline(bytes)
      .resize(1920, 1080)
      .sharpen(1.5)
      .brightness(0.1)
      .toFormat(ImageFormat.webp)
      .quality(85)
      .execute();

  File(outputPath).writeAsBytesSync(result.data);
}

/// Convert between image formats.
Future<Uint8List> convertFormat(
  Uint8List input,
  ImageFormat targetFormat,
) async {
  final result = await ImagePipeline(
    input,
  ).toFormat(targetFormat).quality(90).execute();
  return result.data;
}

/// Batch-process multiple images with priority queue.
Future<List<ImageResult>> batchThumbnails(List<Uint8List> images) async {
  final engine = JustImageEngine();
  final batch = engine.createBatch(concurrency: 4);

  final futures = images.map((bytes) {
    final pipeline = ImagePipeline(
      bytes,
    ).resize(200, 200).toFormat(ImageFormat.jpeg).quality(80);
    return batch.enqueue(pipeline, priority: TaskPriority.normal);
  });

  final results = await Future.wait(futures);
  batch.dispose();
  return results;
}
