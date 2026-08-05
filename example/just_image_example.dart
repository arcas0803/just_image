// ignore_for_file: unused_local_variable
/// Complete just_image example: image processing with the native Rust engine.
///
/// Before running, generate the test images:
///   dart run example/create_test_images.dart
///
/// Then run the example:
///   dart run example/just_image_example.dart
///
/// NOTE: Requires the native library to be compiled:
///   cd src/native && cargo build --release
library;

import 'dart:io';

import 'package:just_image/just_image.dart';

Future<void> main() async {
  final imgDir = 'example/images';
  final outDir = 'example/output';
  Directory(outDir).createSync(recursive: true);

  // Check that test images exist
  final gradientFile = File('$imgDir/gradient.bmp');
  if (!gradientFile.existsSync()) {
    print('⚠ Test images not found.');
    print('  Run first: dart run example/create_test_images.dart');
    return;
  }

  print('═══════════════════════════════════════');
  print('  just_image — Processing Example');
  print('═══════════════════════════════════════\n');

  // ─────────────────────────────────────
  // 1. Basic fluent pipeline: resize + sharpen + format conversion
  // ─────────────────────────────────────
  print('1. Basic pipeline: resize + sharpen → JPEG');

  final result = await gradientFile.justImage
      .resize(100, 75)
      .sharpen(1.5)
      .encode(OutputFormat.jpeg, quality: 85)
      .run();

  File('$outDir/01_resized.jpg').writeAsBytesSync(result.data);
  print(
    '   → ${result.width}x${result.height}, '
    '${result.sizeInBytes} bytes\n',
  );

  // ─────────────────────────────────────
  // 2. High-level static API: quick processing
  // ─────────────────────────────────────
  print('2. JustImage.process: landscape → WebP thumbnail');
  final landscapeFile = File('$imgDir/landscape.bmp');
  final thumb = await JustImage.process(
    FileSource(landscapeFile),
    width: 160,
    height: 120,
    output: const WebpOutput(quality: 80),
  );

  File('$outDir/02_thumb.webp').writeAsBytesSync(thumb.data);
  print('   → ${thumb.width}x${thumb.height}, ${thumb.sizeInBytes} bytes\n');

  // ─────────────────────────────────────
  // 3. Full pipeline with multiple effects
  // ─────────────────────────────────────
  print(
    '3. Pro pipeline: crop + resize + HSL + brightness + contrast + sharpen',
  );
  final checkerFile = File('$imgDir/checkerboard.bmp');
  final watermarkFile = File('$imgDir/watermark.bmp');

  final pro = await checkerFile.justImage
      .autoOrient(true)
      .preserveMetadata(true)
      .crop(10, 10, 140, 140)
      .resize(200, 200)
      .hsl(hue: 15, saturation: 0.1, lightness: 0.05)
      .brightness(0.05)
      .contrast(0.15)
      .sharpen(1.2, 0.5)
      .watermark(FileSource(watermarkFile), x: 60, y: 80, opacity: 0.5)
      .encode(const PngOutput())
      .run();

  File('$outDir/03_pro.png').writeAsBytesSync(pro.data);
  print('   → ${pro.width}x${pro.height}, ${pro.sizeInBytes} bytes\n');

  // ─────────────────────────────────────
  // 4. Individual effects
  // ─────────────────────────────────────
  final circlesFile = File('$imgDir/circles.bmp');

  // 4a. Gaussian Blur
  print('4a. Effect: Gaussian Blur (σ=3.0)');
  final blurred = await circlesFile.justImage
      .blur(3.0)
      .encode(const PngOutput())
      .run();
  File('$outDir/04a_blur.png').writeAsBytesSync(blurred.data);
  print('   → ${blurred.width}x${blurred.height}\n');

  // 4b. Edge detection (Sobel)
  print('4b. Effect: Sobel Edge Detection');
  final edges = await circlesFile.justImage
      .sobel()
      .encode(const PngOutput())
      .run();
  File('$outDir/04b_edges.png').writeAsBytesSync(edges.data);
  print('   → ${edges.width}x${edges.height}\n');

  // 4c. Free-angle rotation (45°)
  print('4c. Transform: 45° Rotation');
  final rotated = await gradientFile.justImage
      .rotate(45)
      .encode(const PngOutput())
      .run();
  File('$outDir/04c_rotated.png').writeAsBytesSync(rotated.data);
  print('   → ${rotated.width}x${rotated.height}\n');

  // 4d. Horizontal flip
  print('4d. Transform: Horizontal Flip');
  final flipped = await gradientFile.justImage
      .flipHorizontal()
      .encode(const BmpOutput())
      .run();
  File('$outDir/04d_flipped.bmp').writeAsBytesSync(flipped.data);
  print('   → ${flipped.width}x${flipped.height}\n');

  // 4e. Brightness adjustment
  print('4e. Effect: Brightness +30%');
  final bright = await landscapeFile.justImage
      .brightness(0.3)
      .encode(const PngOutput())
      .run();
  File('$outDir/04e_bright.png').writeAsBytesSync(bright.data);
  print('   → ${bright.width}x${bright.height}\n');

  // ─────────────────────────────────────
  // 5. Batch processing with JustImage.processBatch
  // ─────────────────────────────────────
  print('5. Batch processing: 3 images in parallel');

  final batch = await JustImage.processBatch([
    gradientFile.justImage
        .resize(80, 60)
        .sharpen(0.8)
        .encode(const WebpOutput(quality: 75)),
    landscapeFile.justImage
        .resize(80, 60)
        .sharpen(0.8)
        .encode(const WebpOutput(quality: 75)),
    circlesFile.justImage
        .resize(80, 60)
        .sharpen(0.8)
        .encode(const WebpOutput(quality: 75)),
  ], concurrency: 3);

  final batchResults = batch.successful;
  for (var i = 0; i < batchResults.length; i++) {
    File('$outDir/05_batch_$i.webp').writeAsBytesSync(batchResults[i].data);
  }
  print(
    '   → ${batch.successCount} images processed '
    '(${batch.failureCount} failed)\n',
  );

  // ─────────────────────────────────────
  // 6. Format conversion
  // ─────────────────────────────────────
  print('6. Format conversion: BMP → JPEG, PNG, WebP');
  for (final output in [
    const JpegOutput(),
    const PngOutput(),
    const WebpOutput(),
  ]) {
    final converted = await gradientFile.justImage.encode(output).run();
    final ext = output.format;
    File('$outDir/06_converted.$ext').writeAsBytesSync(converted.data);
    print('   → $ext: ${converted.sizeInBytes} bytes');
  }

  print('\n═══════════════════════════════════════');
  print('  ✅ All examples completed');
  print('  📂 Output saved to: $outDir/');
  print('═══════════════════════════════════════');
}
