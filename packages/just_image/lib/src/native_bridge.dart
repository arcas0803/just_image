import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'exceptions.dart';

// ──────────────────────────────────────────────
// FFI struct mirrors for Rust types
// ──────────────────────────────────────────────

/// Mirrors the `FfiResult` struct defined in Rust.
final class FfiResult extends Struct {
  external Pointer<Uint8> data;

  @IntPtr()
  external int len;

  @Uint32()
  external int width;

  @Uint32()
  external int height;

  external Pointer<Utf8> error;
}

// ──────────────────────────────────────────────
// Native function typedefs
// ──────────────────────────────────────────────

typedef _RustProcessPipelineNative =
    FfiResult Function(
      Pointer<Uint8> inputPtr,
      IntPtr inputLen,
      Pointer<Utf8> configJson,
      Pointer<Uint8> watermarkPtr,
      IntPtr watermarkLen,
    );
typedef _RustProcessPipelineDart =
    FfiResult Function(
      Pointer<Uint8> inputPtr,
      int inputLen,
      Pointer<Utf8> configJson,
      Pointer<Uint8> watermarkPtr,
      int watermarkLen,
    );

typedef _RustFreeBufferNative = Void Function(Pointer<Uint8> ptr, IntPtr len);
typedef _RustFreeBufferDart = void Function(Pointer<Uint8> ptr, int len);

typedef _RustFreeErrorNative = Void Function(Pointer<Utf8> ptr);
typedef _RustFreeErrorDart = void Function(Pointer<Utf8> ptr);

typedef _RustVersionNative = Pointer<Utf8> Function();
typedef _RustVersionDart = Pointer<Utf8> Function();

typedef _RustFreeStringNative = Void Function(Pointer<Utf8> ptr);
typedef _RustFreeStringDart = void Function(Pointer<Utf8> ptr);

typedef _RustImageInfoNative =
    FfiResult Function(Pointer<Uint8> inputPtr, IntPtr inputLen);
typedef _RustImageInfoDart =
    FfiResult Function(Pointer<Uint8> inputPtr, int inputLen);

typedef _RustBlurHashEncodeNative =
    FfiResult Function(
      Pointer<Uint8> inputPtr,
      IntPtr inputLen,
      Uint32 componentsX,
      Uint32 componentsY,
    );
typedef _RustBlurHashEncodeDart =
    FfiResult Function(
      Pointer<Uint8> inputPtr,
      int inputLen,
      int componentsX,
      int componentsY,
    );

typedef _RustBlurHashDecodeNative =
    FfiResult Function(Pointer<Utf8> hashPtr, Uint32 width, Uint32 height);
typedef _RustBlurHashDecodeDart =
    FfiResult Function(Pointer<Utf8> hashPtr, int width, int height);

typedef _RustAvailableFiltersNative = Pointer<Utf8> Function();
typedef _RustAvailableFiltersDart = Pointer<Utf8> Function();

// ──────────────────────────────────────────────
// Data transferred across Isolate boundaries
// ──────────────────────────────────────────────

/// Payload sent to the background isolate for processing.
final class PipelineRequest {
  final Uint8List inputBytes;
  final String configJson;
  final Uint8List? watermarkBytes;

  const PipelineRequest({
    required this.inputBytes,
    required this.configJson,
    this.watermarkBytes,
  });
}

/// Result returned from the background processing isolate.
final class PipelineResponse {
  final Uint8List data;
  final int width;
  final int height;
  final String? error;

  const PipelineResponse({
    required this.data,
    required this.width,
    required this.height,
    this.error,
  });
}

// ──────────────────────────────────────────────
// NativeBridge — Singleton FFI bridge
// ──────────────────────────────────────────────

/// Low-level FFI bridge to the Rust native library.
///
/// This class is intentionally not exported from the public API. Use the
/// high-level [ImagePipeline] and [JustImage] API instead.
class NativeBridge {
  static NativeBridge? _instance;
  late final DynamicLibrary _lib;

  late final _RustProcessPipelineDart _processPipeline;
  late final _RustFreeBufferDart _freeBuffer;
  late final _RustFreeErrorDart _freeError;
  late final _RustVersionDart _version;
  late final _RustFreeStringDart _freeString;
  late final _RustImageInfoDart _imageInfo;
  late final _RustBlurHashEncodeDart _blurHashEncode;
  late final _RustBlurHashDecodeDart _blurHashDecode;
  late final _RustAvailableFiltersDart _availableFilters;

  NativeBridge._() {
    try {
      _lib = _loadLibrary();
      _bindFunctions();
    } on UnsupportedPlatformException {
      rethrow;
    } on JustImageException {
      rethrow;
    } catch (e) {
      throw NativeLibraryException('Failed to load native library: $e');
    }
  }

  /// Returns the singleton instance of the bridge.
  factory NativeBridge() {
    _instance ??= NativeBridge._();
    return _instance!;
  }

  /// Loads the native library for the current platform.
  static DynamicLibrary _loadLibrary() {
    const baseName = 'just_image_native';

    if (Platform.isIOS) {
      return DynamicLibrary.process();
    }

    final libName = _platformLibName(baseName);

    // 1. Native Assets registered library (used by Flutter builds).
    try {
      return DynamicLibrary.open(libName);
    } catch (_) {}

    // 2. macOS framework bundle layout used by Flutter.
    if (Platform.isMacOS) {
      try {
        return DynamicLibrary.open('$baseName.framework/$baseName');
      } catch (_) {}
    }

    // 3. Native Assets JIT copy in .dart_tool/lib (produced by dart run).
    try {
      final nativeAssetsCopy =
          '${Directory.current.path}/.dart_tool/lib/$libName';
      return DynamicLibrary.open(nativeAssetsCopy);
    } catch (_) {}

    final hostTriple = _hostRustTarget();

    // 4. Cargo host-target build when running from the package root.
    if (hostTriple != null) {
      try {
        final cargoHostPath =
            '${Directory.current.path}/src/native/target/$hostTriple/release/$libName';
        return DynamicLibrary.open(cargoHostPath);
      } catch (_) {}
    }

    // 5. Cargo default target directory (no --target).
    try {
      final cargoDefaultPath =
          '${Directory.current.path}/src/native/target/release/$libName';
      return DynamicLibrary.open(cargoDefaultPath);
    } catch (_) {}

    // 6. Workspace-relative cargo build (running from repo root).
    if (hostTriple != null) {
      try {
        final workspacePath =
            '${Directory.current.path}/packages/just_image/src/native/target/$hostTriple/release/$libName';
        return DynamicLibrary.open(workspacePath);
      } catch (_) {}
    }

    try {
      final workspaceDefaultPath =
          '${Directory.current.path}/packages/just_image/src/native/target/release/$libName';
      return DynamicLibrary.open(workspaceDefaultPath);
    } catch (_) {}

    // 7. Legacy fallback.
    try {
      final legacyPath =
          '${Directory.current.path}/native/target/release/$libName';
      return DynamicLibrary.open(legacyPath);
    } catch (_) {}

    throw NativeLibraryException(
      'Could not load $libName. '
      'Ensure Rust is compiled: cd src/native && cargo build --release',
    );
  }

  static String _platformLibName(String baseName) {
    if (Platform.isAndroid || Platform.isLinux) return 'lib$baseName.so';
    if (Platform.isMacOS) return 'lib$baseName.dylib';
    if (Platform.isWindows) return '$baseName.dll';
    throw UnsupportedPlatformException(Platform.operatingSystem);
  }

  /// Best-effort guess of the Rust target triple for the current host.
  static String? _hostRustTarget() {
    return switch (Abi.current()) {
      Abi.macosArm64 => 'aarch64-apple-darwin',
      Abi.macosX64 => 'x86_64-apple-darwin',
      Abi.linuxX64 => 'x86_64-unknown-linux-gnu',
      Abi.linuxArm64 => 'aarch64-unknown-linux-gnu',
      Abi.windowsX64 => 'x86_64-pc-windows-msvc',
      Abi.windowsArm64 => 'aarch64-pc-windows-msvc',
      _ => null,
    };
  }

  void _bindFunctions() {
    _processPipeline = _lib
        .lookupFunction<_RustProcessPipelineNative, _RustProcessPipelineDart>(
          'rust_process_pipeline',
        );
    _freeBuffer = _lib
        .lookupFunction<_RustFreeBufferNative, _RustFreeBufferDart>(
          'rust_free_buffer',
        );
    _freeError = _lib.lookupFunction<_RustFreeErrorNative, _RustFreeErrorDart>(
      'rust_free_error',
    );
    _version = _lib.lookupFunction<_RustVersionNative, _RustVersionDart>(
      'rust_version',
    );
    _freeString = _lib
        .lookupFunction<_RustFreeStringNative, _RustFreeStringDart>(
          'rust_free_string',
        );
    _imageInfo = _lib.lookupFunction<_RustImageInfoNative, _RustImageInfoDart>(
      'rust_image_info',
    );
    _blurHashEncode = _lib
        .lookupFunction<_RustBlurHashEncodeNative, _RustBlurHashEncodeDart>(
          'rust_blurhash_encode',
        );
    _blurHashDecode = _lib
        .lookupFunction<_RustBlurHashDecodeNative, _RustBlurHashDecodeDart>(
          'rust_blurhash_decode',
        );
    _availableFilters = _lib
        .lookupFunction<_RustAvailableFiltersNative, _RustAvailableFiltersDart>(
          'rust_available_filters',
        );
  }

  /// Version string reported by the Rust native library.
  String get nativeVersion {
    final ptr = _version();
    final version = ptr.toDartString();
    _freeString(ptr);
    return version;
  }

  /// List of available artistic filter names.
  List<String> get availableFilters {
    final ptr = _availableFilters();
    final jsonStr = ptr.toDartString();
    _freeString(ptr);
    return (jsonDecode(jsonStr) as List).cast<String>();
  }

  /// Processes an image through the native Rust pipeline.
  PipelineResponse processPipeline(PipelineRequest request) {
    return using((arena) {
      final inputPtr = arena<Uint8>(request.inputBytes.length);
      inputPtr
          .asTypedList(request.inputBytes.length)
          .setAll(0, request.inputBytes);

      final configPtr = request.configJson.toNativeUtf8(allocator: arena);

      Pointer<Uint8> watermarkPtr = nullptr;
      var watermarkLen = 0;
      if (request.watermarkBytes != null &&
          request.watermarkBytes!.isNotEmpty) {
        watermarkLen = request.watermarkBytes!.length;
        watermarkPtr = arena<Uint8>(watermarkLen);
        watermarkPtr
            .asTypedList(watermarkLen)
            .setAll(0, request.watermarkBytes!);
      }

      final result = _processPipeline(
        inputPtr,
        request.inputBytes.length,
        configPtr.cast<Utf8>(),
        watermarkPtr,
        watermarkLen,
      );

      return _unwrapFfiResult(result);
    });
  }

  /// Reads basic metadata from an image without processing it.
  PipelineResponse imageInfo(Uint8List bytes) {
    return using((arena) {
      final inputPtr = arena<Uint8>(bytes.length);
      inputPtr.asTypedList(bytes.length).setAll(0, bytes);

      final result = _imageInfo(inputPtr, bytes.length);
      return _unwrapFfiResult(result);
    });
  }

  /// Encodes an image into a BlurHash string.
  PipelineResponse blurHashEncode(
    Uint8List bytes, {
    int componentsX = 4,
    int componentsY = 3,
  }) {
    return using((arena) {
      final inputPtr = arena<Uint8>(bytes.length);
      inputPtr.asTypedList(bytes.length).setAll(0, bytes);

      final result = _blurHashEncode(
        inputPtr,
        bytes.length,
        componentsX,
        componentsY,
      );
      return _unwrapFfiResult(result);
    });
  }

  /// Decodes a BlurHash string into PNG image bytes.
  PipelineResponse blurHashDecode(String hash, int width, int height) {
    return using((arena) {
      final hashPtr = hash.toNativeUtf8(allocator: arena);
      final result = _blurHashDecode(hashPtr.cast<Utf8>(), width, height);
      return _unwrapFfiResult(result);
    });
  }

  /// Converts a Rust [FfiResult] into a Dart [PipelineResponse], freeing
  /// native memory in the process.
  PipelineResponse _unwrapFfiResult(FfiResult result) {
    if (result.error != nullptr) {
      final errorMsg = result.error.toDartString();
      _freeError(result.error);
      if (result.data != nullptr) {
        _freeBuffer(result.data, result.len);
      }
      return PipelineResponse(
        data: Uint8List(0),
        width: 0,
        height: 0,
        error: errorMsg,
      );
    }

    final outputData = Uint8List(result.len);
    if (result.len > 0 && result.data != nullptr) {
      outputData.setAll(0, result.data.asTypedList(result.len));
    }
    _freeBuffer(result.data, result.len);

    return PipelineResponse(
      data: outputData,
      width: result.width,
      height: result.height,
    );
  }
}
