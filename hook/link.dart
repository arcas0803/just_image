// Copyright (c) 2026 just_image contributors.
// SPDX-License-Identifier: MIT

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:just_image/src/native_bindings.record_use_mapping.g.dart';
import 'package:just_image/src/hook_helpers/android.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:record_use/record_use.dart';

const _baseName = 'just_image_native';
const _assetName = 'src/native_bindings.g.dart';

Future<void> main(List<String> arguments) async {
  await link(arguments, (input, output) async {
    final staticLibraries = input.assets.code
        .where((asset) => asset.id.endsWith(_assetName))
        .map((asset) => asset.file)
        .nonNulls
        .map((uri) => uri.toFilePath())
        .toList();

    if (staticLibraries.isEmpty) {
      return;
    }

    final symbolsToKeep = _symbolsToKeep(input);
    final os = input.config.code.targetOS;

    await CLinker.library(
      name: _baseName,
      assetName: _assetName,
      sources: staticLibraries,
      libraries: _nativeLibraries(os),
      flags: os == OS.android ? androidPageSizeLinkerFlags : const [],
      linkModePreference: LinkModePreference.dynamic,
      linkerOptions: LinkerOptions.treeshake(symbolsToKeep: symbolsToKeep),
    ).run(input: input, output: output);
  });
}

Iterable<String>? _symbolsToKeep(LinkInput input) {
  final recordedUses = input.recordedUses;
  if (recordedUses == null) {
    return null;
  }

  return recordedUses.calls.keys
      .whereType<Method>()
      .map((method) => recordUseMapping[method.name])
      .nonNulls
      .toSet();
}

List<String> _nativeLibraries(OS os) => switch (os) {
  OS.macOS || OS.iOS => const ['iconv'],
  OS.linux => const ['gcc_s', 'util', 'rt', 'pthread', 'm', 'dl', 'c'],
  OS.android => const ['dl', 'log', 'm'],
  OS.windows => const [
    'advapi32',
    'bcrypt',
    'kernel32',
    'ntdll',
    'userenv',
    'ws2_32',
  ],
  _ => const [],
};
