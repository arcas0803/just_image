import 'package:args/command_runner.dart';

import 'commands/blurhash_command.dart';
import 'commands/filters_command.dart';
import 'commands/info_command.dart';
import 'commands/process_command.dart';

/// Builds and returns the CLI [CommandRunner] with all registered commands.
CommandRunner<void> buildCliRunner() {
  final runner = CommandRunner<void>(
    'just_image_cli',
    'High-performance image processing from the command line.',
  );

  runner.addCommand(ProcessCommand());
  runner.addCommand(InfoCommand());
  runner.addCommand(FiltersCommand());
  runner.addCommand(BlurHashCommand());

  return runner;
}
