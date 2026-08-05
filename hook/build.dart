// hook/build.dart — Native Assets build hook for just_image.
//
// Compiles the Rust crate at src/native/ into a dynamic library and registers
// it as a native code asset with DynamicLoadingBundled link mode on all
// platforms (macOS, iOS, Linux, Windows, Android).
//
// StaticLinking is not yet supported by the Dart/Flutter SDK (see
// https://github.com/dart-lang/sdk/issues/49418), so we always produce cdylib
// and register DynamicLoadingBundled. This resolves the intermittent build
// failures on iOS simulator, iOS device, and production builds.

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:just_image/src/hook_helpers/download.dart';

const _baseName = 'just_image_native';

Future<void> main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }

    final packageRoot = input.packageRoot;
    final crateDir = packageRoot.resolve('src/native/');
    final codeConfig = input.config.code;

    final targetTriple = _rustTarget(codeConfig);
    final linkMode = DynamicLoadingBundled();
    final libName = codeConfig.targetOS.libraryFileName(_baseName, linkMode);

    // Determine whether to compile locally or download a pre-built binary.
    final localBuild = input.userDefines['local_build'] as bool? ?? false;

    if (localBuild || await hasRustToolchain()) {
      await _compileWithCargo(
        input: input,
        output: output,
        crateDir: crateDir,
        codeConfig: codeConfig,
        targetTriple: targetTriple,
        linkMode: linkMode,
        libName: libName,
      );
    } else {
      await _downloadPrebuilt(
        input: input,
        output: output,
        codeConfig: codeConfig,
        linkMode: linkMode,
        libName: libName,
      );
    }
  });
}

/// Compiles the Rust crate with cargo (local build).
Future<void> _compileWithCargo({
  required BuildInput input,
  required BuildOutputBuilder output,
  required Uri crateDir,
  required CodeConfig codeConfig,
  required String targetTriple,
  required LinkMode linkMode,
  required String libName,
}) async {
  final env = await _cargoEnv(codeConfig);
  if (codeConfig.targetOS == OS.macOS || codeConfig.targetOS == OS.iOS) {
    final appleEnv = await _appleEnv(
      codeConfig,
      codeConfig.cCompiler,
      input.outputDirectory,
    );
    env.addAll(appleEnv);
  }

  await _ensureRustTarget(targetTriple);

  // Check user-defines for debug builds.
  final debugBuild = input.userDefines['debug_build'] as bool? ?? false;
  final profileArgs = debugBuild ? ['--profile', 'dev'] : ['--release'];
  final subdir = debugBuild ? 'debug' : 'release';

  final cargoArgs = <String>[
    'build',
    ...profileArgs,
    '--target',
    targetTriple,
    '--manifest-path',
    crateDir.resolve('Cargo.toml').toFilePath(),
  ];

  final result = await Process.run(
    'cargo',
    cargoArgs,
    workingDirectory: crateDir.toFilePath(),
    environment: env,
  );

  if (result.exitCode != 0) {
    throw BuildError(
      message:
          'Cargo build failed for $targetTriple (exit ${result.exitCode}):\n'
          'stdout: ${result.stdout}\n'
          'stderr: ${result.stderr}',
    );
  }

  // Resolve the output library path, respecting CARGO_TARGET_DIR.
  final cargoTargetDir = env['CARGO_TARGET_DIR'];
  final targetBase = cargoTargetDir != null
      ? Uri.directory('$cargoTargetDir/$targetTriple/$subdir/')
      : crateDir.resolve('target/$targetTriple/$subdir/');
  final libPath = targetBase.resolve(libName);
  final libFile = File(libPath.toFilePath());
  if (!libFile.existsSync()) {
    throw BuildError(
      message:
          'Cargo build succeeded but expected output was not found:\n'
          '  ${libPath.toFilePath()}\n'
          'If CARGO_TARGET_DIR is set, ensure the path is correct.',
    );
  }

  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: 'src/native_bindings.g.dart',
      linkMode: linkMode,
      file: libPath,
    ),
  );

  output.dependencies.addAll([
    crateDir.resolve('Cargo.toml'),
    crateDir.resolve('Cargo.lock'),
    ...Directory.fromUri(crateDir.resolve('src/'))
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.rs'))
        .map((file) => file.uri),
    crateDir.resolve('include/just_image.h'),
  ]);
}

/// Downloads a pre-built binary from GitHub releases (no Rust required).
Future<void> _downloadPrebuilt({
  required BuildInput input,
  required BuildOutputBuilder output,
  required CodeConfig codeConfig,
  required LinkMode linkMode,
  required String libName,
}) async {
  final osName = codeConfig.targetOS.name;
  final archName = codeConfig.targetArchitecture.name;

  final outputDir = Directory.fromUri(input.outputDirectoryShared);
  final file = await downloadBinary(
    os: osName,
    arch: archName,
    outputDir: outputDir,
  );

  // Copy/rename to the expected library name.
  final targetPath = outputDir.uri.resolve(libName);
  final targetFile = File.fromUri(targetPath);
  if (file.path != targetFile.path) {
    await file.rename(targetFile.path);
  }

  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: 'src/native_bindings.g.dart',
      linkMode: linkMode,
      file: targetPath,
    ),
  );
}

// ──────────────────────────────────────────────
// Target triple mapping
// ──────────────────────────────────────────────

/// Maps the Dart/Native Assets target to a Rust target triple.
String _rustTarget(CodeConfig code) {
  final os = code.targetOS;
  final arch = code.targetArchitecture;

  return switch ((os, arch)) {
    (OS.macOS, Architecture.arm64) => 'aarch64-apple-darwin',
    (OS.macOS, Architecture.x64) => 'x86_64-apple-darwin',
    (OS.iOS, Architecture.arm64) => _iosDeviceOrSimulator(code, isArm64: true),
    (OS.iOS, Architecture.x64) => 'x86_64-apple-ios-sim',
    (OS.linux, Architecture.x64) => 'x86_64-unknown-linux-gnu',
    (OS.linux, Architecture.arm64) => 'aarch64-unknown-linux-gnu',
    (OS.windows, Architecture.x64) => 'x86_64-pc-windows-msvc',
    (OS.windows, Architecture.arm64) => 'aarch64-pc-windows-msvc',
    (OS.android, Architecture.arm64) => 'aarch64-linux-android',
    (OS.android, Architecture.arm) => 'armv7-linux-androideabi',
    (OS.android, Architecture.x64) => 'x86_64-linux-android',
    _ => throw BuildError(message: 'Unsupported target: $os $arch'),
  };
}

/// Chooses the correct iOS target triple based on whether we are building
/// for a physical device or the simulator.
String _iosDeviceOrSimulator(CodeConfig code, {required bool isArm64}) {
  final sdk = code.iOS.targetSdk;
  final isSimulator = sdk == IOSSdk.iPhoneSimulator;
  if (isArm64) {
    return isSimulator ? 'aarch64-apple-ios-sim' : 'aarch64-apple-ios';
  }
  return 'x86_64-apple-ios-sim';
}

// ──────────────────────────────────────────────
// Cargo environment setup
// ──────────────────────────────────────────────

/// Builds the environment for cargo, stripping Xcode-injected variables that
/// conflict with Rust's cc crate and configuring cross-compilation toolchains.
Future<Map<String, String>> _cargoEnv(CodeConfig code) async {
  final env = Map<String, String>.from(Platform.environment);

  // Always strip Xcode / CocoaPods build-settings on Apple platforms so the
  // Rust cc crate uses a clean toolchain.
  if (code.targetOS == OS.macOS || code.targetOS == OS.iOS) {
    _stripXcodeVars(env);
  }

  final cCompiler = code.cCompiler;
  if (code.targetOS == OS.android) {
    if (cCompiler != null) {
      _applyAndroidCCompilerConfig(env, code, cCompiler);
    } else {
      _configureAndroid(env, code);
    }
  } else if (cCompiler != null) {
    _applyCCompilerConfig(env, code, cCompiler);
  }

  return env;
}

/// Configures Apple target toolchain and linker wrapper.
Future<Map<String, String>> _appleEnv(
  CodeConfig code,
  CCompilerConfig? cCompiler,
  Uri outputDirectory,
) async {
  final env = <String, String>{};
  await _configureAppleTarget(env, code, cCompiler, outputDirectory);
  return env;
}

/// Removes Xcode-injected variables that break Rust's cc crate / linker.
void _stripXcodeVars(Map<String, String> env) {
  const xcodeVars = [
    'CC',
    'CXX',
    'LD',
    'AR',
    'RANLIB',
    'STRIP',
    'NM',
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
    'IPHONEOS_DEPLOYMENT_TARGET',
    'TVOS_DEPLOYMENT_TARGET',
    'WATCHOS_DEPLOYMENT_TARGET',
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
}

/// Configures the Apple target toolchain with sysroot and deployment target
/// flags applied only to the cross-compilation target, leaving the host
/// build-script environment untouched so that crates' build.rs files compile.
Future<void> _configureAppleTarget(
  Map<String, String> env,
  CodeConfig code,
  CCompilerConfig? cCompiler,
  Uri outputDirectory,
) async {
  final os = code.targetOS;

  String sdk;
  String deploymentTargetKey;
  int? deploymentTarget;
  String versionFlag;
  String arch;

  if (os == OS.iOS) {
    final isSimulator = code.iOS.targetSdk == IOSSdk.iPhoneSimulator;
    sdk = isSimulator ? 'iphonesimulator' : 'iphoneos';
    deploymentTargetKey = 'IPHONEOS_DEPLOYMENT_TARGET';
    deploymentTarget = code.iOS.targetVersion;
    versionFlag = isSimulator
        ? '-mios-simulator-version-min'
        : '-miphoneos-version-min';
    arch = switch (code.targetArchitecture) {
      Architecture.arm64 => 'arm64',
      Architecture.x64 => 'x86_64',
      _ => throw BuildError(
        message: 'Unsupported iOS architecture: ${code.targetArchitecture}',
      ),
    };
  } else if (os == OS.macOS) {
    sdk = 'macosx';
    deploymentTargetKey = 'MACOSX_DEPLOYMENT_TARGET';
    deploymentTarget = code.macOS.targetVersion;
    versionFlag = '-mmacosx-version-min';
    arch = code.targetArchitecture == Architecture.arm64 ? 'arm64' : 'x86_64';
  } else {
    return;
  }

  final sdkPath = await _xcrunSdkPath(sdk);
  final target = _rustTarget(code);
  final ccTarget = _ccTargetEnv(target);
  final cargoTarget = _cargoTargetEnv(target);

  final compilerPath =
      cCompiler?.compiler.toFilePath() ?? await _xcrunToolPath(sdk, 'clang');
  final archiverPath =
      cCompiler?.archiver.toFilePath() ?? await _xcrunToolPath(sdk, 'ar');

  if (compilerPath == null || archiverPath == null) {
    throw BuildError(
      message:
          'Could not locate Apple toolchain for $sdk. '
          'Ensure Xcode Command Line Tools are installed.',
    );
  }

  final targetFlags = <String>[
    '-isysroot',
    sdkPath ?? '',
    '-arch',
    arch,
    '$versionFlag=$deploymentTarget',
  ]..removeWhere((s) => s.isEmpty);

  final targetCFlags = targetFlags.join(' ');

  env[deploymentTargetKey] = deploymentTarget.toString();

  // For iOS cross-compilation, leave the host build-script environment
  // pointing at the macOS SDK so proc-macros and build.rs binaries link.
  if (os == OS.iOS) {
    final macosSdkPath = await _xcrunSdkPath('macosx');
    if (macosSdkPath != null) {
      env['SDKROOT'] = macosSdkPath;
      env['MACOSX_DEPLOYMENT_TARGET'] = '11.0';
    }
  }

  // cc crate expects lowercase target names; Cargo uses uppercase.
  env['CC_$ccTarget'] = compilerPath;
  env['CXX_$ccTarget'] = compilerPath;
  env['AR_$ccTarget'] = archiverPath;
  env['CFLAGS_$ccTarget'] = targetCFlags;
  env['CXXFLAGS_$ccTarget'] = targetCFlags;

  // Cargo's CARGO_TARGET_<TRIPLE>_LINKER must be a single executable path.
  // Use a wrapper script so linker flags are applied only to the target.
  // Use the compiler driver (clang) so it can parse -isysroot / -arch /
  // -m*-version-min instead of passing them raw to ld.
  final wrapperUri = outputDirectory.resolve('${target}_linker_wrapper.sh');
  final wrapperFile = File(wrapperUri.toFilePath());
  final escapedFlags = targetFlags.map((f) => '"$f"').join(' ');
  await wrapperFile.writeAsString('''
#!/bin/sh
exec "$compilerPath" $escapedFlags "\$@"
''');
  await Process.run('chmod', ['+x', wrapperFile.path]);
  env['CARGO_TARGET_${cargoTarget}_LINKER'] = wrapperFile.path;
}

// ──────────────────────────────────────────────
// xcrun helpers
// ──────────────────────────────────────────────

/// Runs `xcrun --sdk <sdk> --show-sdk-path` and returns the path.
Future<String?> _xcrunSdkPath(String sdk) async {
  try {
    final result = await Process.run('xcrun', [
      '--sdk',
      sdk,
      '--show-sdk-path',
    ]);
    if (result.exitCode == 0) {
      final path = result.stdout.toString().trim();
      if (path.isNotEmpty) return path;
    } else {
      stderr.writeln(
        '[just_image] xcrun --sdk $sdk --show-sdk-path failed: '
        '${result.stderr}',
      );
    }
  } catch (e) {
    stderr.writeln('[just_image] xcrun not available: $e');
  }
  return null;
}

/// Runs `xcrun --sdk <sdk> --find <tool>` and returns the tool path.
Future<String?> _xcrunToolPath(String sdk, String tool) async {
  try {
    final result = await Process.run('xcrun', ['--sdk', sdk, '--find', tool]);
    if (result.exitCode == 0) {
      final path = result.stdout.toString().trim();
      if (path.isNotEmpty) return path;
    } else {
      stderr.writeln(
        '[just_image] xcrun --sdk $sdk --find $tool failed: '
        '${result.stderr}',
      );
    }
  } catch (e) {
    stderr.writeln('[just_image] xcrun not available: $e');
  }
  return null;
}

// ──────────────────────────────────────────────
// C compiler config (non-Android)
// ──────────────────────────────────────────────

/// Applies the C compiler configuration provided by Native Assets.
///
/// Uses lowercase target names for the `cc` crate (`CC_*`, `CXX_*`, `AR_*`)
/// and the uppercase Cargo convention for `CARGO_TARGET_*_LINKER`.
void _applyCCompilerConfig(
  Map<String, String> env,
  CodeConfig code,
  CCompilerConfig cCompiler,
) {
  final target = _rustTarget(code);
  final ccTarget = _ccTargetEnv(target);
  final cargoTarget = _cargoTargetEnv(target);

  env['CC_$ccTarget'] = cCompiler.compiler.toFilePath();
  env['CXX_$ccTarget'] = _cxxFromCompiler(cCompiler.compiler.toFilePath());
  env['AR_$ccTarget'] = cCompiler.archiver.toFilePath();
  env['CARGO_TARGET_${cargoTarget}_LINKER'] = cCompiler.linker.toFilePath();
}

// ──────────────────────────────────────────────
// Android NDK
// ──────────────────────────────────────────────

/// Applies the C compiler configuration from Native Assets specifically for
/// Android, where the NDK clang compiler doubles as the linker.
///
/// `cCompiler.compiler` is the generic NDK `clang` binary (e.g.
/// `darwin-x86_64/bin/clang`). When used as a linker driver without an
/// explicit `--target`, it defaults to the host platform (macOS) and injects
/// Mach-O flags that the ELF linker rejects. Instead we resolve the
/// versioned, Android-targeted wrapper script (e.g.
/// `aarch64-linux-android29-clang`) which has the correct target baked in and
/// routes to the NDK's own `ld.lld` automatically — no wrapper needed.
void _applyAndroidCCompilerConfig(
  Map<String, String> env,
  CodeConfig code,
  CCompilerConfig cCompiler,
) {
  final target = _rustTarget(code);
  final ccTarget = _ccTargetEnv(target);
  final cargoTarget = _cargoTargetEnv(target);
  final compiler = cCompiler.compiler.toFilePath();

  env['CC_$ccTarget'] = compiler;
  env['CXX_$ccTarget'] = _cxxFromCompiler(compiler);
  env['AR_$ccTarget'] = cCompiler.archiver.toFilePath();

  final toolchainBin = File(compiler).parent.path;
  final clangPrefix = _androidClangPrefix(target);
  final linker =
      _findAndroidCompiler(
        toolchainBin,
        clangPrefix,
        code.android.targetNdkApi,
      ) ??
      compiler;
  env['CARGO_TARGET_${cargoTarget}_LINKER'] = linker;
}

/// Derives a likely C++ compiler path from a C compiler path.
String _cxxFromCompiler(String compiler) {
  final cxx = '$compiler++';
  return File(cxx).existsSync() ? cxx : compiler;
}

/// Lowercase target triple used by the `cc` crate for environment variables.
String _ccTargetEnv(String rustTarget) =>
    rustTarget.toLowerCase().replaceAll('-', '_');

/// Uppercase target triple used by Cargo for target configuration.
String _cargoTargetEnv(String rustTarget) =>
    rustTarget.toUpperCase().replaceAll('-', '_');

/// Configures Android NDK toolchain environment variables for the current
/// target only (not all targets, to avoid unnecessary env pollution).
void _configureAndroid(Map<String, String> env, CodeConfig code) {
  final ndkHome = _findNdkHome();
  if (ndkHome == null) {
    throw BuildError(
      message:
          'Android NDK not found. Set ANDROID_NDK_HOME to the NDK directory, '
          'e.g. export ANDROID_NDK_HOME=\$HOME/Library/Android/sdk/ndk/28.2.13676358',
    );
  }

  final requestedApi = code.android.targetNdkApi;
  final hostTag = _ndkHostTag();

  var toolchain = '$ndkHome/toolchains/llvm/prebuilt/$hostTag/bin';
  if (!Directory(toolchain).existsSync() && hostTag == 'darwin-arm64') {
    toolchain = '$ndkHome/toolchains/llvm/prebuilt/darwin-x86_64/bin';
  }

  if (!Directory(toolchain).existsSync()) {
    throw BuildError(
      message:
          'Android NDK toolchain directory not found: $toolchain. '
          'Ensure the NDK is installed and $hostTag is supported.',
    );
  }

  env['ANDROID_NDK_HOME'] = ndkHome;

  final rustTarget = _rustTarget(code);
  final clangPrefix = _androidClangPrefix(rustTarget);
  final ccTarget = _ccTargetEnv(rustTarget);
  final cargoTarget = _cargoTargetEnv(rustTarget);

  final compiler = _findAndroidCompiler(toolchain, clangPrefix, requestedApi);
  if (compiler == null) {
    throw BuildError(
      message:
          'Could not find an Android clang compiler for $rustTarget in '
          '$toolchain. Tried $clangPrefix$requestedApi-clang, '
          '$clangPrefix-clang, and $clangPrefix<api>-clang.',
    );
  }

  env['CC_$ccTarget'] = compiler;
  env['CXX_$ccTarget'] = _cxxFromCompiler(compiler);
  env['AR_$ccTarget'] = _findAndroidAr(toolchain);
  // The versioned clang script already has the correct --target and uses the
  // NDK's own ld.lld, so no wrapper is needed on any platform.
  env['CARGO_TARGET_${cargoTarget}_LINKER'] = compiler;
}

/// Maps a Rust Android target triple to the clang prefix used by the NDK.
String _androidClangPrefix(String rustTarget) => switch (rustTarget) {
  'aarch64-linux-android' => 'aarch64-linux-android',
  'armv7-linux-androideabi' => 'armv7a-linux-androideabi',
  'x86_64-linux-android' => 'x86_64-linux-android',
  _ => rustTarget,
};

/// Finds the Android archiver, preferring `llvm-ar` in the toolchain.
String _findAndroidAr(String toolchain) {
  final llvmAr = '$toolchain/llvm-ar';
  if (File(llvmAr).existsSync()) return llvmAr;
  // Very old NDKs shipped a target-prefixed ar.
  return '$toolchain/llvm-ar';
}

/// Finds a working Android clang compiler in [toolchainDir] for [clangPrefix].
///
/// Tries, in order:
/// 1. `$clangPrefix<requestedApi>-clang`
/// 2. `$clangPrefix-clang` (unversioned symlink)
/// 3. The highest available `$clangPrefix<api>-clang`
String? _findAndroidCompiler(
  String toolchainDir,
  String clangPrefix,
  int requestedApi,
) {
  final candidates = <String>[
    '$toolchainDir/$clangPrefix$requestedApi-clang',
    '$toolchainDir/$clangPrefix-clang',
  ];

  // Find all versioned compilers and pick the highest API level as a fallback.
  final dir = Directory(toolchainDir);
  if (dir.existsSync()) {
    final versioned = dir
        .listSync()
        .whereType<File>()
        .map((f) => f.path)
        .where(
          (p) =>
              p.startsWith('$toolchainDir/$clangPrefix') &&
              p.endsWith('-clang') &&
              p != '$toolchainDir/$clangPrefix-clang',
        )
        .toList();
    versioned.sort();
    candidates.addAll(versioned.reversed);
  }

  for (final candidate in candidates) {
    if (File(candidate).existsSync()) return candidate;
  }
  return null;
}

/// Locates the Android NDK installation directory.
String? _findNdkHome() {
  for (final key in ['ANDROID_NDK_HOME', 'ANDROID_NDK_ROOT']) {
    final val = Platform.environment[key];
    if (val != null && val.isNotEmpty && Directory(val).existsSync()) {
      return val;
    }
  }

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

String? _latestNdkVersion(Directory ndkParent) {
  try {
    final versions =
        ndkParent.listSync().whereType<Directory>().map((d) => d.path).toList()
          ..sort();
    return versions.isNotEmpty ? versions.last : null;
  } catch (_) {
    return null;
  }
}

String _ndkHostTag() {
  if (Platform.isMacOS) return 'darwin-arm64';
  if (Platform.isWindows) return 'windows-x86_64';
  return 'linux-x86_64';
}

// ──────────────────────────────────────────────
// Rust target installation
// ──────────────────────────────────────────────

/// Ensures the given Rust target triple is installed via rustup.
/// Uses a cache file to avoid repeated `rustup target list` calls.
Future<void> _ensureRustTarget(String rustTarget) async {
  // Quick check: does the target directory already exist?
  // This implies the target was installed in a previous build.
  final listResult = await Process.run('rustup', [
    'target',
    'list',
    '--installed',
  ]);
  if (listResult.exitCode != 0) {
    throw BuildError(
      message: 'Failed to query installed Rust targets: ${listResult.stderr}',
    );
  }

  final installed = listResult.stdout.toString().split('\n');
  if (installed.any((line) => line.trim() == rustTarget)) return;

  stderr.writeln('[just_image] Installing Rust target $rustTarget...');
  final addResult = await Process.run('rustup', ['target', 'add', rustTarget]);
  if (addResult.exitCode != 0) {
    throw BuildError(
      message:
          'Failed to install Rust target "$rustTarget": ${addResult.stderr}',
    );
  }
}
