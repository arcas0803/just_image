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

    final env = await _cargoEnv(input.config.code.targetOS);

    // Ensure the required Rust target is installed (auto-installs if missing).
    await _ensureRustTarget(rustTarget);

    final result = await Process.run(
      'cargo',
      cargoArgs,
      workingDirectory: crateDir.toFilePath(),
      environment: env,
    );

    if (result.exitCode != 0) {
      throw Exception(
        'Cargo build failed (exit ${result.exitCode}):\n'
        'stdout: ${result.stdout}\n'
        'stderr: ${result.stderr}',
      );
    }

    // Locate the compiled library and verify it was actually produced.
    final libPath = crateDir.resolve('target/$rustTarget/release/$libName');
    final libFile = File(libPath.toFilePath());
    if (!libFile.existsSync()) {
      throw Exception(
        'Cargo build succeeded (exit 0) but expected output was not found:\n'
        '  ${libPath.toFilePath()}\n'
        'stdout: ${result.stdout}\n'
        'stderr: ${result.stderr}',
      );
    }

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

/// Build a clean environment for cargo, stripping Xcode build-system
/// variables that would otherwise confuse the Rust `cc` crate and linker.
Future<Map<String, String>> _cargoEnv(OS os) async {
  // Start from the inherited environment.
  final env = Map<String, String>.from(Platform.environment);

  if (os == OS.macOS || os == OS.iOS) {
    // Remove Xcode / CocoaPods injected build-settings that break Rust
    // compilation.
    const xcodeVars = [
      // Tool overrides — let Rust's cc crate discover its own tools.
      'CC',
      'CXX',
      'LD',
      'AR',
      'RANLIB',
      'STRIP',
      'NM',
      // Flag overrides — Xcode flags can conflict with Rust's LTO/codegen.
      'CFLAGS',
      'CXXFLAGS',
      'LDFLAGS',
      'CPPFLAGS',
      'ASFLAGS',
      'OTHER_CFLAGS',
      'OTHER_LDFLAGS',
      'OTHER_CPLUSPLUSFLAGS',
      'OTHER_SWIFT_FLAGS',
      'GCC_PREPROCESSOR_DEFINITIONS',
      // Wrong-platform deployment targets.
      'IPHONEOS_DEPLOYMENT_TARGET',
      'TVOS_DEPLOYMENT_TARGET',
      'WATCHOS_DEPLOYMENT_TARGET',
      // Xcode build-directory overrides that confuse cc build scripts.
      'ARCHS',
      'VALID_ARCHS',
      'NATIVE_ARCH',
      'ONLY_ACTIVE_ARCH',
      'CURRENT_ARCH',
      'CONFIGURATION',
      'CONFIGURATION_BUILD_DIR',
      'BUILT_PRODUCTS_DIR',
      'TARGET_BUILD_DIR',
      'DERIVED_FILE_DIR',
      'OBJECT_FILE_DIR',
      'SHARED_PRECOMPS_DIR',
      'BUILD_DIR',
      'BUILD_ROOT',
      'OBJROOT',
      'SYMROOT',
      'DSTROOT',
      'PROJECT_TEMP_DIR',
      'TARGET_TEMP_DIR',
      'ACTION',
      'HEADER_SEARCH_PATHS',
      'FRAMEWORK_SEARCH_PATHS',
      'LIBRARY_SEARCH_PATHS',
      'PLATFORM_DIR',
      'PLATFORM_NAME',
      'EFFECTIVE_PLATFORM_NAME',
      'DT_TOOLCHAIN_DIR',
      'TOOLCHAIN_DIR',
    ];
    for (final v in xcodeVars) {
      env.remove(v);
    }

    // Ensure SDKROOT is set — on modern macOS the system headers and
    // libraries live exclusively inside the SDK.  Without SDKROOT the
    // linker invoked by Rust's cc crate cannot find libSystem and friends.
    if (!env.containsKey('SDKROOT') || env['SDKROOT']!.isEmpty) {
      final sdkResult = await Process.run('xcrun', ['--show-sdk-path']);
      final sdkPath = sdkResult.stdout.toString().trim();
      if (sdkResult.exitCode == 0 && sdkPath.isNotEmpty) {
        env['SDKROOT'] = sdkPath;
      }
    }
  }

  if (os == OS.android) {
    final ndkHome = _findNdkHome();
    if (ndkHome == null) {
      throw Exception(
        'Android NDK not found. Set ANDROID_NDK_HOME to the NDK directory, '
        'e.g. export ANDROID_NDK_HOME=\$HOME/Library/Android/sdk/ndk/28.2.13676358',
      );
    }

    // API level: configurable via ANDROID_MIN_SDK_VERSION, default 21.
    final apiLevel =
        Platform.environment['ANDROID_MIN_SDK_VERSION'] ?? '21';

    final hostTag = _ndkHostTag();

    // Verify the prebuilt toolchain directory exists; if the primary host
    // tag doesn't exist (e.g. darwin-arm64 on NDK < 23), fall back to
    // darwin-x86_64 (works via Rosetta on Apple Silicon).
    var toolchain = '$ndkHome/toolchains/llvm/prebuilt/$hostTag/bin';
    if (!Directory(toolchain).existsSync() && hostTag == 'darwin-arm64') {
      toolchain =
          '$ndkHome/toolchains/llvm/prebuilt/darwin-x86_64/bin';
    }

    env['ANDROID_NDK_HOME'] = ndkHome;

    // Linker: controls final linking of Rust-compiled code.
    env['CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER'] =
        '$toolchain/aarch64-linux-android$apiLevel-clang';
    env['CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_LINKER'] =
        '$toolchain/armv7a-linux-androideabi$apiLevel-clang';
    env['CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER'] =
        '$toolchain/x86_64-linux-android$apiLevel-clang';

    // C compiler: required by cc-rs build scripts inside Rust dependencies
    // (e.g. libdeflate-sys, lcms2).  Without these, cc-rs falls back to
    // guessing "arm-linux-androideabi-clang" which does not exist in the NDK.
    env['CC_aarch64_linux_android'] =
        '$toolchain/aarch64-linux-android$apiLevel-clang';
    env['CC_armv7_linux_androideabi'] =
        '$toolchain/armv7a-linux-androideabi$apiLevel-clang';
    env['CC_x86_64_linux_android'] =
        '$toolchain/x86_64-linux-android$apiLevel-clang';

    // C++ compiler: some build scripts may also need it.
    env['CXX_aarch64_linux_android'] =
        '$toolchain/aarch64-linux-android$apiLevel-clang++';
    env['CXX_armv7_linux_androideabi'] =
        '$toolchain/armv7a-linux-androideabi$apiLevel-clang++';
    env['CXX_x86_64_linux_android'] =
        '$toolchain/x86_64-linux-android$apiLevel-clang++';

    // Archiver: used by cc-rs when building static libraries.
    env['AR_aarch64_linux_android'] = '$toolchain/llvm-ar';
    env['AR_armv7_linux_androideabi'] = '$toolchain/llvm-ar';
    env['AR_x86_64_linux_android'] = '$toolchain/llvm-ar';
  }

  return env;
}

/// Locates the Android NDK installation directory.
///
/// Search order:
/// 1. ANDROID_NDK_HOME env var
/// 2. ANDROID_NDK_ROOT env var
/// 3. Newest version under ANDROID_HOME/ndk/ or ANDROID_SDK_ROOT/ndk/
/// 4. Platform-specific defaults (~/Library/Android/sdk/ndk on macOS,
///    ~/Android/Sdk/ndk on Linux)
///
/// Returns null if no NDK can be found.
String? _findNdkHome() {
  // 1. Explicit NDK env vars.
  for (final key in ['ANDROID_NDK_HOME', 'ANDROID_NDK_ROOT']) {
    final val = Platform.environment[key];
    if (val != null && val.isNotEmpty && Directory(val).existsSync()) {
      return val;
    }
  }

  // 2. Scan <sdk>/ndk/ for the highest-version subdirectory.
  final sdkCandidates = [
    Platform.environment['ANDROID_HOME'],
    Platform.environment['ANDROID_SDK_ROOT'],
  ];
  for (final sdk in sdkCandidates) {
    if (sdk == null || sdk.isEmpty) continue;
    final ndkDir = Directory('$sdk/ndk');
    if (ndkDir.existsSync()) {
      final latest = _latestNdkVersion(ndkDir);
      if (latest != null) return latest;
    }
  }

  // 3. Platform default locations.
  final home = Platform.environment['HOME'] ?? '';
  final defaults = Platform.isMacOS
      ? ['$home/Library/Android/sdk/ndk']
      : ['$home/Android/Sdk/ndk', '$home/android/sdk/ndk'];
  for (final base in defaults) {
    final ndkDir = Directory(base);
    if (ndkDir.existsSync()) {
      final latest = _latestNdkVersion(ndkDir);
      if (latest != null) return latest;
    }
  }

  return null;
}

/// Returns the path to the latest NDK version directory under [ndkParent],
/// determined by lexicographic sort of subdirectory names.
String? _latestNdkVersion(Directory ndkParent) {
  try {
    final versions = ndkParent
        .listSync()
        .whereType<Directory>()
        .map((d) => d.path)
        .toList()
      ..sort();
    return versions.isNotEmpty ? versions.last : null;
  } catch (_) {
    return null;
  }
}

/// Returns the NDK prebuilt toolchain host tag for the current build machine.
String _ndkHostTag() {
  if (Platform.isMacOS) {
    // NDK ≥ 23 ships native arm64 binaries; older NDKs only have x86_64.
    // _cargoEnv() will fall back to darwin-x86_64 if the directory is absent.
    return 'darwin-arm64';
  } else if (Platform.isWindows) {
    return 'windows-x86_64';
  } else {
    return 'linux-x86_64';
  }
}

/// Ensures the given Rust target triple is installed via rustup.
/// If not installed, installs it automatically.
Future<void> _ensureRustTarget(String rustTarget) async {
  final listResult = await Process.run(
    'rustup',
    ['target', 'list', '--installed'],
  );
  if (listResult.exitCode != 0) {
    throw Exception(
      'Failed to query installed Rust targets. Is rustup in PATH?\n'
      '${listResult.stderr}',
    );
  }

  final installed = listResult.stdout.toString().split('\n');
  if (installed.any((line) => line.trim() == rustTarget)) return;

  // Target not installed — add it automatically.
  final addResult = await Process.run(
    'rustup',
    ['target', 'add', rustTarget],
  );
  if (addResult.exitCode != 0) {
    throw Exception(
      'Failed to install Rust target "$rustTarget":\n'
      '${addResult.stderr}',
    );
  }
}
