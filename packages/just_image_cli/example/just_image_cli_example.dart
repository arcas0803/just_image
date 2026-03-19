// Example: Using just_image_cli programmatically via its library API.
//
// This file demonstrates how to build and invoke the CLI runner from Dart code.
// For command-line usage, install globally and run:
//
//   dart pub global activate just_image_cli
//   just_image_cli process -i photo.jpg -o result.webp -f webp -q 85
//   just_image_cli info -i photo.jpg

import 'package:just_image_cli/just_image_cli.dart';

void main() async {
  final runner = buildCliRunner();

  // Display help.
  await runner.run(['help']);

  // Inspect an image (requires a real file).
  // await runner.run(['info', '-i', 'photo.jpg']);

  // Process an image (requires real files).
  // await runner.run([
  //   'process',
  //   '-i', 'photo.jpg',
  //   '-o', 'output.webp',
  //   '--resize', '800x600',
  //   '-f', 'webp',
  //   '-q', '85',
  // ]);
}
