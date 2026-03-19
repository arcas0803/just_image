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
///   cd native && cargo build --release
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
  final gradientBytes = gradientFile.readAsBytesSync();

  final result = await ImagePipeline(gradientBytes)
      .resize(100, 75)
      .sharpen(1.5)
      .toFormat(ImageFormat.jpeg)
      .quality(85)
      .execute();

  File('$outDir/01_resized.jpg').writeAsBytesSync(result.data);
  print(
    '   → ${result.width}x${result.height}, '
    '${result.sizeInBytes} bytes\n',
  );

  // ─────────────────────────────────────
  // 2. High-level engine: quick processing
  // ─────────────────────────────────────
  print('2. Engine quick process: landscape → WebP thumbnail');
  final engine = JustImageEngine();
  print('   Native version: ${engine.nativeVersion}');

  final landscapeBytes = File('$imgDir/landscape.bmp').readAsBytesSync();
  final thumb = await engine.process(
    landscapeBytes,
    width: 160,
    height: 120,
    format: ImageFormat.webp,
    quality: 80,
  );

  File('$outDir/02_thumb.webp').writeAsBytesSync(thumb.data);
  print('   → ${thumb.width}x${thumb.height}, ${thumb.sizeInBytes} bytes\n');

  // ─────────────────────────────────────
  // 3. Full pipeline with multiple effects
  // ─────────────────────────────────────
  print(
    '3. Pro pipeline: crop + resize + HSL + brightness + contrast + sharpen',
  );
  final checkerBytes = File('$imgDir/checkerboard.bmp').readAsBytesSync();
  final watermarkBytes = File('$imgDir/watermark.bmp').readAsBytesSync();

  final pro = await engine
      .load(checkerBytes)
      .autoOrient(true)
      .preserveMetadata(true)
      .crop(10, 10, 140, 140)
      .resize(200, 200)
      .hsl(hue: 15, saturation: 0.1, lightness: 0.05)
      .brightness(0.05)
      .contrast(0.15)
      .sharpen(1.2, 0.5)
      .watermark(watermarkBytes, x: 60, y: 80, opacity: 0.5)
      .toFormat(ImageFormat.png)
      .execute();

  File('$outDir/03_pro.png').writeAsBytesSync(pro.data);
  print('   → ${pro.width}x${pro.height}, ${pro.sizeInBytes} bytes\n');

  // ─────────────────────────────────────
  // 4. Individual effects
  // ─────────────────────────────────────
  final circlesBytes = File('$imgDir/circles.bmp').readAsBytesSync();

  // 4a. Gaussian Blur
  print('4a. Effect: Gaussian Blur (σ=3.0)');
  final blurred = await ImagePipeline(
    circlesBytes,
  ).blur(3.0).toFormat(ImageFormat.png).execute();
  File('$outDir/04a_blur.png').writeAsBytesSync(blurred.data);
  print('   → ${blurred.width}x${blurred.height}\n');

  // 4b. Edge detection (Sobel)
  print('4b. Effect: Sobel Edge Detection');
  final edges = await ImagePipeline(
    circlesBytes,
  ).sobel().toFormat(ImageFormat.png).execute();
  File('$outDir/04b_edges.png').writeAsBytesSync(edges.data);
  print('   → ${edges.width}x${edges.height}\n');

  // 4c. Free-angle rotation (45°)
  print('4c. Transform: 45° Rotation');
  final rotated = await ImagePipeline(
    gradientBytes,
  ).rotate(45).toFormat(ImageFormat.png).execute();
  File('$outDir/04c_rotated.png').writeAsBytesSync(rotated.data);
  print('   → ${rotated.width}x${rotated.height}\n');

  // 4d. Horizontal flip
  print('4d. Transform: Horizontal Flip');
  final flipped = await ImagePipeline(
    gradientBytes,
  ).flip(FlipDirection.horizontal).toFormat(ImageFormat.bmp).execute();
  File('$outDir/04d_flipped.bmp').writeAsBytesSync(flipped.data);
  print('   → ${flipped.width}x${flipped.height}\n');

  // 4e. Brightness adjustment
  print('4e. Effect: Brightness +30%');
  final bright = await ImagePipeline(
    landscapeBytes,
  ).brightness(0.3).toFormat(ImageFormat.png).execute();
  File('$outDir/04e_bright.png').writeAsBytesSync(bright.data);
  print('   → ${bright.width}x${bright.height}\n');

  // ─────────────────────────────────────
  // 5. Batch processing with priorities
  // ─────────────────────────────────────
  print('5. Batch processing: 3 images in parallel');
  final batch = engine.createBatch(concurrency: 3);

  final inputImages = [gradientBytes, landscapeBytes, circlesBytes];

  final futures = inputImages.map(
    (bytes) => batch.enqueue(
      ImagePipeline(
        bytes,
      ).resize(80, 60).sharpen(0.8).toFormat(ImageFormat.webp).quality(75),
      priority: TaskPriority.normal,
    ),
  );

  final batchResults = await Future.wait(futures);
  for (var i = 0; i < batchResults.length; i++) {
    File('$outDir/05_batch_$i.webp').writeAsBytesSync(batchResults[i].data);
  }
  print('   → ${batchResults.length} images processed\n');

  // High-priority task
  print('   Critical task: urgent thumbnail');
  final urgent = await batch.enqueue(
    ImagePipeline(gradientBytes).resize(32, 32).toFormat(ImageFormat.png),
    priority: TaskPriority.critical,
  );
  File('$outDir/05_urgent.png').writeAsBytesSync(urgent.data);
  print('   → ${urgent.width}x${urgent.height}\n');

  // ─────────────────────────────────────
  // 6. Format conversion
  // ─────────────────────────────────────
  print('6. Format conversion: BMP → JPEG, PNG, WebP');
  for (final fmt in [ImageFormat.jpeg, ImageFormat.png, ImageFormat.webp]) {
    final converted = await ImagePipeline(
      gradientBytes,
    ).toFormat(fmt).quality(90).execute();
    final ext = fmt.value;
    File('$outDir/06_converted.$ext').writeAsBytesSync(converted.data);
    print('   → $ext: ${converted.sizeInBytes} bytes');
  }

  print('\n═══════════════════════════════════════');
  print('  ✅ All examples completed');
  print('  📂 Output saved to: $outDir/');
  print('═══════════════════════════════════════');

  engine.dispose();
}
