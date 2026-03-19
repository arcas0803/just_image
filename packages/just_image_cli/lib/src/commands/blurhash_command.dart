import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:just_image/just_image.dart';

/// The `blurhash` command — encode/decode BlurHash strings.
class BlurHashCommand extends Command<void> {
  @override
  final name = 'blurhash';

  @override
  final description = 'Encode an image to BlurHash or decode a hash to image.';

  BlurHashCommand() {
    addSubcommand(_EncodeSubcommand());
    addSubcommand(_DecodeSubcommand());
  }
}

class _EncodeSubcommand extends Command<void> {
  @override
  final name = 'encode';

  @override
  final description = 'Encode an image file to a BlurHash string.';

  _EncodeSubcommand() {
    argParser
      ..addOption('input', abbr: 'i', mandatory: true, help: 'Input file path')
      ..addOption('components-x', defaultsTo: '4', help: 'X components (1-9)')
      ..addOption('components-y', defaultsTo: '3', help: 'Y components (1-9)');
  }

  @override
  Future<void> run() async {
    final inputPath = argResults!['input'] as String;

    final inputFile = File(inputPath);
    if (!inputFile.existsSync()) {
      stderr.writeln('Error: File not found: $inputPath');
      exitCode = 1;
      return;
    }

    final cx = int.tryParse(argResults!['components-x'] as String) ?? 4;
    final cy = int.tryParse(argResults!['components-y'] as String) ?? 3;

    final engine = JustImageEngine();
    try {
      final bytes = inputFile.readAsBytesSync();
      final hash = await engine.blurHashEncode(
        bytes,
        componentsX: cx,
        componentsY: cy,
      );
      stdout.writeln(hash);
    } on JustImageException catch (e) {
      stderr.writeln('Error: $e');
      exitCode = 1;
    } finally {
      engine.dispose();
    }
  }
}

class _DecodeSubcommand extends Command<void> {
  @override
  final name = 'decode';

  @override
  final description = 'Decode a BlurHash string to a PNG image.';

  _DecodeSubcommand() {
    argParser
      ..addOption('hash', mandatory: true, help: 'BlurHash string')
      ..addOption(
        'output',
        abbr: 'o',
        mandatory: true,
        help: 'Output PNG file path',
      )
      ..addOption('width', defaultsTo: '32', help: 'Output width')
      ..addOption('height', defaultsTo: '32', help: 'Output height');
  }

  @override
  Future<void> run() async {
    final hash = argResults!['hash'] as String;
    final outputPath = argResults!['output'] as String;
    final width = int.tryParse(argResults!['width'] as String) ?? 32;
    final height = int.tryParse(argResults!['height'] as String) ?? 32;

    final engine = JustImageEngine();
    try {
      final result = await engine.blurHashDecode(
        hash,
        width: width,
        height: height,
      );
      File(outputPath).writeAsBytesSync(result.data);
      stdout.writeln(
        'Done: ${result.width}x${result.height} PNG -> $outputPath',
      );
    } on JustImageException catch (e) {
      stderr.writeln('Error: $e');
      exitCode = 1;
    } finally {
      engine.dispose();
    }
  }
}
