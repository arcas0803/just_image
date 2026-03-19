import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:just_image/just_image.dart';

/// The `info` command — displays metadata about an image file.
class InfoCommand extends Command<void> {
  @override
  final name = 'info';

  @override
  final description = 'Display image dimensions, format, and file size.';

  InfoCommand() {
    argParser.addOption(
      'input',
      abbr: 'i',
      mandatory: true,
      help: 'Image file path',
    );
  }

  @override
  Future<void> run() async {
    final inputPath = argResults!['input'] as String;
    final file = File(inputPath);

    if (!file.existsSync()) {
      stderr.writeln('Error: File not found: $inputPath');
      exitCode = 1;
      return;
    }

    final bytes = file.readAsBytesSync();
    final fileSize = bytes.length;

    try {
      final bridge = NativeBridge();
      final response = bridge.imageInfo(bytes);

      if (response.error != null) {
        stderr.writeln('Error reading image info: ${response.error}');
        exitCode = 1;
        return;
      }

      stdout.writeln('File:       $inputPath');
      stdout.writeln('Dimensions: ${response.width}x${response.height}');
      stdout.writeln('File size:  ${_humanSize(fileSize)}');
    } on JustImageException catch (e) {
      stderr.writeln('Error: $e');
      exitCode = 1;
    }
  }

  String _humanSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
