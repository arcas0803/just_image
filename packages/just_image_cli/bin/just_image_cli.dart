import 'dart:io';

import 'package:just_image_cli/src/cli_runner.dart';

Future<void> main(List<String> args) async {
  stderr.writeln(
    'WARNING: just_image_cli is discontinued. '
    'Use the just_image package directly (just_image: ^1.0.3).',
  );
  final runner = buildCliRunner();
  await runner.run(args);
}
