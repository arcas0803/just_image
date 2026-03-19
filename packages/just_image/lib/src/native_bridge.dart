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

// rust_process_pipeline
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

// rust_free_buffer
typedef _RustFreeBufferNative = Void Function(Pointer<Uint8> ptr, IntPtr len);
typedef _RustFreeBufferDart = void Function(Pointer<Uint8> ptr, int len);

// rust_free_error
typedef _RustFreeErrorNative = Void Function(Pointer<Utf8> ptr);
typedef _RustFreeErrorDart = void Function(Pointer<Utf8> ptr);

// rust_version
typedef _RustVersionNative = Pointer<Utf8> Function();
typedef _RustVersionDart = Pointer<Utf8> Function();

// rust_free_string
typedef _RustFreeStringNative = Void Function(Pointer<Utf8> ptr);
typedef _RustFreeStringDart = void Function(Pointer<Utf8> ptr);

// rust_image_info
typedef _RustImageInfoNative =
    FfiResult Function(Pointer<Uint8> inputPtr, IntPtr inputLen);
typedef _RustImageInfoDart =
    FfiResult Function(Pointer<Uint8> inputPtr, int inputLen);

// rust_blurhash_encode
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

// rust_blurhash_decode
typedef _RustBlurHashDecodeNative =
    FfiResult Function(Pointer<Utf8> hashPtr, Uint32 width, Uint32 height);
typedef _RustBlurHashDecodeDart =
    FfiResult Function(Pointer<Utf8> hashPtr, int width, int height);

// rust_available_filters
typedef _RustAvailableFiltersNative = Pointer<Utf8> Function();
typedef _RustAvailableFiltersDart = Pointer<Utf8> Function();

// ──────────────────────────────────────────────
// Data transferred across Isolate boundaries
// ──────────────────────────────────────────────

/// Payload sent to the background isolate for processing.
///
/// All fields are simple, serialisable types that can cross isolate
/// boundaries without extra work.
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
/// This singleton loads the dynamic library on first access and exposes
/// strongly-typed bindings for every exported Rust function. All native
/// memory management (alloc / free) is handled internally.
///
/// You rarely need to use this class directly — prefer [ImagePipeline]
/// or [JustImageEngine] for a higher-level API.
///
/// ```dart
/// final bridge = NativeBridge();
/// print('Rust engine version: ${bridge.nativeVersion}');
/// print('Available filters: ${bridge.availableFilters}');
/// ```
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
  ///
  /// The native library is loaded lazily on the first call.
  factory NativeBridge() {
    _instance ??= NativeBridge._();
    return _instance!;
  }

  /// Loads the native library for the current platform.
  ///
  /// With Native Assets (`hook/build.dart`) the Dart/Flutter SDK
  /// registers the compiled library automatically.  On macOS Flutter
  /// bundles it as a `.framework` inside the app bundle; on iOS the
  /// library is statically linked into the runner.
  static DynamicLibrary _loadLibrary() {
    const baseName = 'just_image_native';

    if (Platform.isIOS) {
      return DynamicLibrary.process();
    }

    // Native Assets places the library where the system can resolve it.
    final libName = _platformLibName(baseName);

    // 1. Direct open by conventional name (works on Linux, Windows,
    //    and on macOS when the dylib is on the process rpath).
    try {
      return DynamicLibrary.open(libName);
    } catch (_) {}

    // 2. On macOS, Flutter bundles native assets as .framework inside
    //    <app>.app/Contents/Frameworks/<name>.framework/<name>.
    //    Opening the framework-relative name works because Flutter
    //    configures @rpath at link time.
    if (Platform.isMacOS) {
      try {
        return DynamicLibrary.open('$baseName.framework/$baseName');
      } catch (_) {}
    }

    // 3. Development fallback: look in target/release next to the crate.
    try {
      final devPath =
          '${Directory.current.path}/packages/just_image/src/native/target/release/$libName';
      return DynamicLibrary.open(devPath);
    } catch (_) {}

    // 4. Legacy fallback.
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

  /// Returns the platform-specific library filename.
  static String _platformLibName(String baseName) {
    if (Platform.isAndroid || Platform.isLinux) return 'lib$baseName.so';
    if (Platform.isMacOS) return 'lib$baseName.dylib';
    if (Platform.isWindows) return '$baseName.dll';
    throw UnsupportedPlatformException(Platform.operatingSystem);
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
  ///
  /// ```dart
  /// final bridge = NativeBridge();
  /// print(bridge.nativeVersion); // e.g. "1.0.1"
  /// ```
  String get nativeVersion {
    final ptr = _version();
    final version = ptr.toDartString();
    _freeString(ptr);
    return version;
  }

  /// Processes an image through the native Rust pipeline.
  ///
  /// **Memory lifecycle:**
  /// 1. Dart allocates `inputPtr` via `calloc` and copies the input bytes.
  /// 2. Rust reads the input, processes it, and allocates the output.
  /// 3. Dart copies the output into a Dart-managed `Uint8List`.
  /// 4. Dart frees both the input (`calloc.free`) and the output
  ///    (`rust_free_buffer`).
  ///
  /// Prefer [ImagePipeline.execute] or [JustImageEngine.process] instead
  /// of calling this method directly.
  PipelineResponse processPipeline(PipelineRequest request) {
    // 1. Allocate and copy input bytes into native memory.
    final inputPtr = calloc<Uint8>(request.inputBytes.length);
    final inputList = inputPtr.asTypedList(request.inputBytes.length);
    inputList.setAll(0, request.inputBytes);

    // 2. Serialise the config JSON to a C string.
    final configPtr = request.configJson.toNativeUtf8();

    // 3. Watermark overlay (optional).
    Pointer<Uint8> watermarkPtr = nullptr;
    int watermarkLen = 0;
    if (request.watermarkBytes != null && request.watermarkBytes!.isNotEmpty) {
      watermarkLen = request.watermarkBytes!.length;
      watermarkPtr = calloc<Uint8>(watermarkLen);
      watermarkPtr.asTypedList(watermarkLen).setAll(0, request.watermarkBytes!);
    }

    try {
      // 4. Call into Rust.
      final result = _processPipeline(
        inputPtr,
        request.inputBytes.length,
        configPtr.cast<Utf8>(),
        watermarkPtr,
        watermarkLen,
      );

      // 5. Check for errors.
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

      // 6. Copy result into Dart-managed memory so Rust can be freed.
      final outputData = Uint8List(result.len);
      if (result.len > 0 && result.data != nullptr) {
        outputData.setAll(0, result.data.asTypedList(result.len));
      }

      // 7. Free Rust-allocated memory.
      _freeBuffer(result.data, result.len);

      return PipelineResponse(
        data: outputData,
        width: result.width,
        height: result.height,
      );
    } finally {
      // 8. Free Dart-allocated native memory.
      calloc.free(inputPtr);
      calloc.free(configPtr);
      if (watermarkPtr != nullptr) {
        calloc.free(watermarkPtr);
      }
    }
  }

  /// Reads basic metadata from an image without processing it.
  ///
  /// Returns a [PipelineResponse] whose `data` contains a JSON-encoded
  /// string with image dimensions, format, and colour information.
  ///
  /// ```dart
  /// final bridge = NativeBridge();
  /// final info = bridge.imageInfo(imageBytes);
  /// print('${info.width}x${info.height}');
  /// ```
  PipelineResponse imageInfo(Uint8List bytes) {
    final inputPtr = calloc<Uint8>(bytes.length);
    inputPtr.asTypedList(bytes.length).setAll(0, bytes);

    try {
      final result = _imageInfo(inputPtr, bytes.length);

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
    } finally {
      calloc.free(inputPtr);
    }
  }

  /// Encodes an image into a BlurHash string.
  ///
  /// [componentsX] and [componentsY] control the hash complexity
  /// (typically 4×3). Higher values capture more detail but produce
  /// longer hashes.
  ///
  /// ```dart
  /// final bridge = NativeBridge();
  /// final resp = bridge.blurHashEncode(imageBytes,
  ///     componentsX: 4, componentsY: 3);
  /// final hash = String.fromCharCodes(resp.data);
  /// print(hash); // e.g. "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
  /// ```
  PipelineResponse blurHashEncode(
    Uint8List bytes, {
    int componentsX = 4,
    int componentsY = 3,
  }) {
    final inputPtr = calloc<Uint8>(bytes.length);
    inputPtr.asTypedList(bytes.length).setAll(0, bytes);

    try {
      final result = _blurHashEncode(
        inputPtr,
        bytes.length,
        componentsX,
        componentsY,
      );

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
    } finally {
      calloc.free(inputPtr);
    }
  }

  /// Decodes a BlurHash string into PNG image bytes.
  ///
  /// [width] and [height] define the dimensions of the generated image.
  /// Use small values (e.g. 32×32) for lightweight placeholders.
  ///
  /// ```dart
  /// final bridge = NativeBridge();
  /// final resp = bridge.blurHashDecode('LEHV6nWB2yk8...', 32, 32);
  /// File('placeholder.png').writeAsBytesSync(resp.data);
  /// ```
  PipelineResponse blurHashDecode(String hash, int width, int height) {
    final hashPtr = hash.toNativeUtf8();

    try {
      final result = _blurHashDecode(hashPtr.cast<Utf8>(), width, height);

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
    } finally {
      calloc.free(hashPtr);
    }
  }

  /// Returns the list of available artistic filter names.
  ///
  /// ```dart
  /// final bridge = NativeBridge();
  /// print(bridge.availableFilters);
  /// // [vintage, sepia, cool, warm, marine, dramatic, lomo, retro,
  /// //  noir, bloom, polaroid, golden_hour, arctic, cinematic, fade]
  /// ```
  List<String> get availableFilters {
    final ptr = _availableFilters();
    final jsonStr = ptr.toDartString();
    _freeString(ptr);
    final list = (jsonDecode(jsonStr) as List).cast<String>();
    return list;
  }
}
