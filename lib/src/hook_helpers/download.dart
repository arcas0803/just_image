// Download helper for pre-built native libraries.
//
// Downloads a platform-specific binary from GitHub releases and verifies
// its SHA-256 hash against the expected value in [binaryHashes].

import 'dart:io';

import 'package:crypto/crypto.dart';

import 'hashes.dart';

/// Constructs the download URI for a given platform binary name.
Uri _downloadUri(String fileName) {
  return Uri.parse(
    'https://github.com/arcas0803/just_image/releases/download/v$binaryVersion/$fileName',
  );
}

/// Returns the platform-specific binary file name for the current target.
String binaryFileName(String os, String arch, {String? variant}) {
  const base = 'just_image_native';
  return switch ((os, arch, variant)) {
    ('macos', 'arm64', _) => 'lib$base-macos-arm64.dylib',
    ('macos', 'x64', _) => 'lib$base-macos-x64.dylib',
    ('ios', 'arm64', 'simulator') => 'lib$base-ios-simulator-arm64.dylib',
    ('ios', 'x64', 'simulator') => 'lib$base-ios-simulator-x64.dylib',
    ('ios', 'arm64', _) => 'lib$base-ios-arm64.dylib',
    ('linux', 'x64', _) => 'lib$base-linux-x64.so',
    ('linux', 'arm64', _) => 'lib$base-linux-arm64.so',
    ('windows', 'x64', _) => '$base-windows-x64.dll',
    ('windows', 'arm64', _) => '$base-windows-arm64.dll',
    ('android', 'arm64', _) => 'lib$base-android-arm64.so',
    ('android', 'arm', _) => 'lib$base-android-arm.so',
    ('android', 'x64', _) => 'lib$base-android-x64.so',
    _ => throw ArgumentError(
      'No pre-built binary for $os-$arch${variant == null ? '' : '-$variant'}',
    ),
  };
}

/// Whether a release artifact has a real integrity hash assigned.
bool hasPublishedBinary(String fileName) {
  final hash = binaryHashes[fileName];
  return hash != null && hash != 'PENDING';
}

/// Downloads a pre-built native library for [os] / [arch] into [outputDir].
///
/// Verifies the SHA-256 hash against [binaryHashes]. Throws on mismatch.
Future<File> downloadBinary({
  required String os,
  required String arch,
  String? variant,
  required Directory outputDir,
}) async {
  final fileName = binaryFileName(os, arch, variant: variant);
  final uri = _downloadUri(fileName);
  final expectedHash = binaryHashes[fileName];

  if (expectedHash == null || expectedHash == 'PENDING') {
    throw StateError(
      'No hash registered for $fileName. '
      'The binary may not be available for this release yet.',
    );
  }

  final cacheDir = Directory.fromUri(
    outputDir.uri.resolve('just_image/$binaryVersion/'),
  );
  final targetFile = File.fromUri(cacheDir.uri.resolve(fileName));
  await targetFile.parent.create(recursive: true);

  if (await targetFile.exists()) {
    final cachedHash = sha256
        .convert(await targetFile.readAsBytes())
        .toString();
    if (cachedHash == expectedHash) {
      stderr.writeln('[just_image] Using cached $fileName');
      return targetFile;
    }
    await targetFile.delete();
  }

  final client = HttpClient()..findProxy = HttpClient.findProxyFromEnvironment;
  client.connectionTimeout = const Duration(seconds: 20);
  final partialFile = File('${targetFile.path}.partial');

  try {
    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        if (await partialFile.exists()) await partialFile.delete();
        stderr.writeln(
          '[just_image] Downloading $fileName (attempt $attempt/3)...',
        );
        final request = await client
            .getUrl(uri)
            .timeout(const Duration(seconds: 30));
        request.headers.set(
          HttpHeaders.userAgentHeader,
          'just_image/$binaryVersion',
        );
        final response = await request.close().timeout(
          const Duration(seconds: 60),
        );
        if (response.statusCode != HttpStatus.ok) {
          await response.drain<void>();
          throw HttpException(
            'HTTP ${response.statusCode} while downloading $fileName',
            uri: uri,
          );
        }
        await response.pipe(partialFile.openWrite());

        final actualHash = sha256
            .convert(await partialFile.readAsBytes())
            .toString();
        if (actualHash != expectedHash) {
          throw StateError(
            'Hash mismatch for $fileName: expected $expectedHash, got $actualHash',
          );
        }
        await partialFile.rename(targetFile.path);
        stderr.writeln('[just_image] Verified $fileName ($actualHash)');
        return targetFile;
      } catch (error) {
        lastError = error;
        if (await partialFile.exists()) await partialFile.delete();
      }
    }
    throw StateError(
      'Failed to download $fileName after 3 attempts: $lastError',
    );
  } finally {
    client.close(force: true);
  }
}

/// Checks whether the Rust toolchain (cargo) is available on the system.
Future<bool> hasRustToolchain() async {
  try {
    final result = await Process.run('cargo', ['--version']);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}
