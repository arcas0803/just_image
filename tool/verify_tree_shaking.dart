// Copyright (c) 2026 just_image contributors.
// SPDX-License-Identifier: MIT

import 'dart:io';

Future<void> main() async {
  final packageRoot = Platform.script.resolve('../');
  final temporary = await Directory.systemTemp.createTemp(
    'just_image_tree_shaking_',
  );

  try {
    final core = await _build(packageRoot, temporary, 'core');
    final full = await _build(packageRoot, temporary, 'full');
    final extended = await _build(packageRoot, temporary, 'extended');
    final unused = await _build(packageRoot, temporary, 'unused');

    final coreLibrary = _nativeLibrary(core);
    final fullLibrary = _nativeLibrary(full);
    final unusedLibrary = _nativeLibrary(unused);
    final extendedLibrary = _nativeLibrary(extended);

    _require(await coreLibrary.exists(), 'Core native library was not built.');
    _require(await fullLibrary.exists(), 'Full native library was not built.');
    _require(
      !await unusedLibrary.exists(),
      'Unused native library must be omitted from the bundle.',
    );
    _require(
      await extendedLibrary.exists(),
      'Extended native library was not built.',
    );

    final coreSymbols = await _exportedSymbols(coreLibrary);
    final fullSymbols = await _exportedSymbols(fullLibrary);
    final extendedSymbols = await _exportedSymbols(extendedLibrary);
    if (coreSymbols != null && fullSymbols != null && extendedSymbols != null) {
      _require(
        coreSymbols.contains('rust_process_core_pipeline'),
        'Core entry point is missing.',
      );
      _require(
        !coreSymbols.contains('rust_process_pipeline'),
        'Full pipeline leaked into the core bundle.',
      );
      _require(
        !coreSymbols.contains('rust_process_extended_pipeline'),
        'Extended pipeline leaked into the core bundle.',
      );
      _require(
        fullSymbols.contains('rust_process_pipeline'),
        'Full entry point is missing.',
      );
      _require(
        !fullSymbols.contains('rust_process_extended_pipeline'),
        'Extended pipeline leaked into the standard bundle.',
      );
      _require(
        extendedSymbols.contains('rust_process_extended_pipeline'),
        'Extended entry point is missing.',
      );
    }

    final coreBytes = await coreLibrary.length();
    final fullBytes = await fullLibrary.length();
    final extendedBytes = await extendedLibrary.length();
    _require(
      coreBytes < fullBytes,
      'Expected core library ($coreBytes bytes) to be smaller than full '
      'library ($fullBytes bytes).',
    );
    _require(
      fullBytes < extendedBytes,
      'Expected standard library ($fullBytes bytes) to be smaller than '
      'extended library ($extendedBytes bytes).',
    );

    final reduction = (1 - coreBytes / fullBytes) * 100;
    stdout.writeln(
      'Native tree shaking verified: core=$coreBytes bytes, '
      'standard=$fullBytes bytes, extended=$extendedBytes bytes; '
      'core-to-standard reduction='
      '${reduction.toStringAsFixed(1)}%.',
    );
  } finally {
    await temporary.delete(recursive: true);
  }
}

Future<Directory> _build(
  Uri packageRoot,
  Directory temporary,
  String fixture,
) async {
  final output = Directory.fromUri(temporary.uri.resolve('$fixture/'));
  final result = await Process.run(Platform.resolvedExecutable, [
    'build',
    'cli',
    '--target=tool/tree_shaking/$fixture.dart',
    '--output=${output.path}',
  ], workingDirectory: Directory.fromUri(packageRoot).path);
  if (result.exitCode != 0) {
    throw StateError(
      'AOT fixture $fixture failed (${result.exitCode}):\n'
      '${result.stdout}\n${result.stderr}',
    );
  }
  return Directory.fromUri(output.uri.resolve('bundle/'));
}

File _nativeLibrary(Directory bundle) {
  final name = switch (Platform.operatingSystem) {
    'macos' => 'libjust_image_native.dylib',
    'linux' || 'android' => 'libjust_image_native.so',
    'windows' => 'just_image_native.dll',
    final os => throw UnsupportedError('Unsupported verification host: $os'),
  };
  return File.fromUri(bundle.uri.resolve('lib/$name'));
}

Future<Set<String>?> _exportedSymbols(File library) async {
  if (Platform.isWindows) {
    // Bundle omission and size are still verified on Windows. The Visual
    // Studio developer shell is not guaranteed to expose dumpbin to PATH.
    return null;
  }
  final (command, arguments) = switch (Platform.operatingSystem) {
    'macos' => ('nm', ['-gU', library.path]),
    'linux' => ('nm', ['-D', '--defined-only', library.path]),
    final os => throw UnsupportedError('Unsupported verification host: $os'),
  };
  final result = await Process.run(command, arguments);
  if (result.exitCode != 0) {
    throw StateError('Could not inspect ${library.path}: ${result.stderr}');
  }
  return RegExp(r'_?(rust_[A-Za-z0-9_]+)')
      .allMatches(result.stdout as String)
      .map((match) => match.group(1)!)
      .toSet();
}

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}
