import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:just_image/just_image.dart';

/// The `process` command — applies transformations and saves the result.
class ProcessCommand extends Command<void> {
  @override
  final name = 'process';

  @override
  final description = 'Process an image: resize, convert, apply effects.';

  ProcessCommand() {
    argParser
      ..addOption('input', abbr: 'i', mandatory: true, help: 'Input file path')
      ..addOption(
        'output',
        abbr: 'o',
        mandatory: true,
        help: 'Output file path',
      )
      ..addOption('resize', help: 'Resize to WxH (e.g. 1920x1080)')
      ..addOption(
        'format',
        abbr: 'f',
        allowed: ['jpeg', 'png', 'webp', 'avif', 'tiff', 'bmp'],
        help: 'Output format',
      )
      ..addOption('quality', abbr: 'q', defaultsTo: '90', help: 'Quality 1-100')
      ..addOption('blur', help: 'Gaussian blur sigma (e.g. 2.0)')
      ..addOption('sharpen', help: 'Sharpen amount (e.g. 1.5)')
      ..addOption('brightness', help: 'Brightness adjustment [-1.0, 1.0]')
      ..addOption('contrast', help: 'Contrast adjustment [-1.0, 1.0]')
      ..addOption('rotate', help: 'Rotation in degrees (e.g. 90)')
      ..addOption(
        'flip',
        allowed: ['horizontal', 'vertical'],
        help: 'Flip direction',
      )
      ..addOption('crop', help: 'Crop as X,Y,W,H (e.g. 0,0,800,600)')
      ..addOption('watermark', help: 'Watermark image path')
      ..addOption('watermark-x', defaultsTo: '0')
      ..addOption('watermark-y', defaultsTo: '0')
      ..addOption('watermark-opacity', defaultsTo: '1.0');
  }

  @override
  Future<void> run() async {
    final inputPath = argResults!['input'] as String;
    final outputPath = argResults!['output'] as String;

    final inputFile = File(inputPath);
    if (!inputFile.existsSync()) {
      stderr.writeln('Error: Input file not found: $inputPath');
      exitCode = 1;
      return;
    }

    final bytes = inputFile.readAsBytesSync();
    var pipeline = ImagePipeline(bytes);

    // Resize
    final resize = argResults!['resize'] as String?;
    if (resize != null) {
      final parts = resize.split('x');
      if (parts.length != 2) {
        stderr.writeln('Error: --resize must be WxH (e.g. 1920x1080)');
        exitCode = 1;
        return;
      }
      final w = int.tryParse(parts[0]);
      final h = int.tryParse(parts[1]);
      if (w == null || h == null || w <= 0 || h <= 0) {
        stderr.writeln('Error: Invalid resize dimensions');
        exitCode = 1;
        return;
      }
      pipeline = pipeline.resize(w, h);
    }

    // Crop
    final crop = argResults!['crop'] as String?;
    if (crop != null) {
      final parts = crop.split(',');
      if (parts.length != 4) {
        stderr.writeln('Error: --crop must be X,Y,W,H');
        exitCode = 1;
        return;
      }
      final nums = parts.map(int.tryParse).toList();
      if (nums.any((n) => n == null)) {
        stderr.writeln('Error: Invalid crop values');
        exitCode = 1;
        return;
      }
      pipeline = pipeline.crop(nums[0]!, nums[1]!, nums[2]!, nums[3]!);
    }

    // Rotate
    final rotate = argResults!['rotate'] as String?;
    if (rotate != null) {
      final deg = double.tryParse(rotate);
      if (deg == null) {
        stderr.writeln('Error: Invalid rotation degrees');
        exitCode = 1;
        return;
      }
      pipeline = pipeline.rotate(deg);
    }

    // Flip
    final flip = argResults!['flip'] as String?;
    if (flip != null) {
      pipeline = pipeline.flip(
        flip == 'horizontal'
            ? FlipDirection.horizontal
            : FlipDirection.vertical,
      );
    }

    // Effects
    final blur = argResults!['blur'] as String?;
    if (blur != null) {
      final sigma = double.tryParse(blur);
      if (sigma == null) {
        stderr.writeln('Error: Invalid blur sigma');
        exitCode = 1;
        return;
      }
      pipeline = pipeline.blur(sigma);
    }

    final sharpen = argResults!['sharpen'] as String?;
    if (sharpen != null) {
      final amount = double.tryParse(sharpen);
      if (amount == null) {
        stderr.writeln('Error: Invalid sharpen amount');
        exitCode = 1;
        return;
      }
      pipeline = pipeline.sharpen(amount);
    }

    final brightness = argResults!['brightness'] as String?;
    if (brightness != null) {
      final val = double.tryParse(brightness);
      if (val == null) {
        stderr.writeln('Error: Invalid brightness value');
        exitCode = 1;
        return;
      }
      pipeline = pipeline.brightness(val);
    }

    final contrast = argResults!['contrast'] as String?;
    if (contrast != null) {
      final val = double.tryParse(contrast);
      if (val == null) {
        stderr.writeln('Error: Invalid contrast value');
        exitCode = 1;
        return;
      }
      pipeline = pipeline.contrast(val);
    }

    // Format & quality
    final format = argResults!['format'] as String?;
    if (format != null) {
      pipeline = pipeline.toFormat(
        ImageFormat.values.firstWhere((f) => f.value == format),
      );
    }

    final quality = int.tryParse(argResults!['quality'] as String);
    if (quality != null) {
      pipeline = pipeline.quality(quality);
    }

    // Watermark
    final watermarkPath = argResults!['watermark'] as String?;
    if (watermarkPath != null) {
      final wmFile = File(watermarkPath);
      if (!wmFile.existsSync()) {
        stderr.writeln('Error: Watermark file not found: $watermarkPath');
        exitCode = 1;
        return;
      }
      final wmBytes = wmFile.readAsBytesSync();
      final wmX = int.tryParse(argResults!['watermark-x'] as String) ?? 0;
      final wmY = int.tryParse(argResults!['watermark-y'] as String) ?? 0;
      final wmOpacity =
          double.tryParse(argResults!['watermark-opacity'] as String) ?? 1.0;
      pipeline = pipeline.watermark(
        wmBytes,
        x: wmX,
        y: wmY,
        opacity: wmOpacity,
      );
    }

    // Execute
    try {
      final result = await pipeline.execute();
      File(outputPath).writeAsBytesSync(result.data);
      stdout.writeln(
        'Done: ${result.width}x${result.height} ${result.format} '
        '(${result.sizeInBytes} bytes) -> $outputPath',
      );
    } on JustImageException catch (e) {
      stderr.writeln('Error: $e');
      exitCode = 1;
    }
  }
}
