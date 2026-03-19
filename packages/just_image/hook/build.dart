// hook/build.dart — Native Assets build hook for just_image.
//
// This hook is invoked automatically by `dart run` / `flutter build` when
// the Dart SDK detects `hook/build.dart` in the package root.
//
// Protocol: https://dart.dev/interop/c-interop#native-assets
//
// It compiles the Rust crate located at `src/native/` into a dynamic
// library and registers it as a native code asset so that `dart:ffi`
// DynamicLibrary.open() can find it at runtime.

import 'dart:io';

import 'package:native_assets_cli/code_assets.dart';
import 'package:native_assets_cli/native_assets_cli.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final packageRoot = input.packageRoot;
    final crateDir = packageRoot.resolve('src/native/');

    final targetArch = input.config.code.targetArchitecture;

    // Map Dart target OS + architecture to Rust target triple.
    final rustTarget = _rustTarget(input.config.code.targetOS, targetArch);

    // Determine output library name per platform convention.
    final libName = input.config.code.targetOS.dylibFileName(
      'just_image_native',
    );

    // Run cargo build.
    final cargoArgs = <String>[
      'build',
      '--release',
      '--target',
      rustTarget,
      '--manifest-path',
      crateDir.resolve('Cargo.toml').toFilePath(),
    ];

    final result = await Process.run(
      'cargo',
      cargoArgs,
      workingDirectory: crateDir.toFilePath(),
      environment: _cargoEnv(input.config.code.targetOS),
    );

    if (result.exitCode != 0) {
      throw Exception(
        'Cargo build failed (exit ${result.exitCode}):\n'
        '${result.stdout}\n${result.stderr}',
      );
    }

    // Locate the compiled library.
    final libPath = crateDir.resolve('target/$rustTarget/release/$libName');

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'src/native/just_image_native',
        linkMode: DynamicLoadingBundled(),
        file: libPath,
      ),
    );

    // Declare dependency on the Cargo manifest so incremental builds work.
    output.addDependencies([
      crateDir.resolve('Cargo.toml'),
      crateDir.resolve('src/'),
    ]);
  });
}

/// Maps [OS] + [Architecture] to a Rust target triple.
String _rustTarget(OS os, Architecture arch) {
  return switch ((os, arch)) {
    // macOS
    (OS.macOS, Architecture.arm64) => 'aarch64-apple-darwin',
    (OS.macOS, Architecture.x64) => 'x86_64-apple-darwin',

    // Linux
    (OS.linux, Architecture.x64) => 'x86_64-unknown-linux-gnu',
    (OS.linux, Architecture.arm64) => 'aarch64-unknown-linux-gnu',

    // Windows
    (OS.windows, Architecture.x64) => 'x86_64-pc-windows-msvc',
    (OS.windows, Architecture.arm64) => 'aarch64-pc-windows-msvc',

    // Android
    (OS.android, Architecture.arm64) => 'aarch64-linux-android',
    (OS.android, Architecture.arm) => 'armv7-linux-androideabi',
    (OS.android, Architecture.x64) => 'x86_64-linux-android',

    // iOS
    (OS.iOS, Architecture.arm64) => 'aarch64-apple-ios',
    (OS.iOS, Architecture.x64) => 'x86_64-apple-ios',

    _ => throw UnsupportedError('Unsupported target: $os $arch'),
  };
}

/// Additional environment variables for cargo when targeting Android.
Map<String, String>? _cargoEnv(OS os) {
  if (os == OS.android) {
    final ndkHome = Platform.environment['ANDROID_NDK_HOME'];
    if (ndkHome != null) {
      return {'ANDROID_NDK_HOME': ndkHome};
    }
  }
  return null;
}
