import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:just_image/just_image.dart';

/// The `filters` command — lists all available artistic filters.
class FiltersCommand extends Command<void> {
  @override
  final name = 'filters';

  @override
  final description = 'List all available artistic filters.';

  @override
  void run() {
    final engine = JustImageEngine();
    try {
      final filters = engine.availableFilters;
      stdout.writeln('Available filters (${filters.length}):');
      for (final filter in filters) {
        stdout.writeln('  • $filter');
      }
    } finally {
      engine.dispose();
    }
  }
}
