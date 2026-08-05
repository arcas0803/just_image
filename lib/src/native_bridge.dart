import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'exceptions.dart';
import 'native_bindings.g.dart' as native;

const _supportedAbiVersion = 1;

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

  NativeBridge._() {
    try {
      final actualAbi = native.rust_abi_version();
      if (actualAbi != _supportedAbiVersion) {
        throw NativeLibraryException(
          'Unsupported native ABI $actualAbi; expected $_supportedAbiVersion.',
        );
      }
    } on NativeLibraryException {
      rethrow;
    } catch (e) {
      throw NativeLibraryException(
        'Failed to resolve the bundled just_image native asset: $e',
      );
    }
  }

  /// Returns the singleton instance of the bridge.
  factory NativeBridge() {
    _instance ??= NativeBridge._();
    return _instance!;
  }

  /// Version string reported by the Rust native library.
  String get nativeVersion {
    final ptr = native.rust_version();
    final version = ptr.cast<Utf8>().toDartString();
    native.rust_free_string(ptr);
    return version;
  }

  /// List of available artistic filter names.
  List<String> get availableFilters {
    final ptr = native.rust_available_filters();
    final jsonStr = ptr.cast<Utf8>().toDartString();
    native.rust_free_string(ptr);
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

      final result = native.rust_process_pipeline(
        inputPtr,
        request.inputBytes.length,
        configPtr.cast<Char>(),
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

      final result = native.rust_image_info(inputPtr, bytes.length);
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

      final result = native.rust_blurhash_encode(
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
      final result = native.rust_blurhash_decode(
        hashPtr.cast<Char>(),
        width,
        height,
      );
      return _unwrapFfiResult(result);
    });
  }

  /// Converts a Rust [FfiResult] into a Dart [PipelineResponse], freeing
  /// native memory in the process.
  PipelineResponse _unwrapFfiResult(native.FfiResult result) {
    if (result.error != nullptr) {
      final errorMsg = result.error.cast<Utf8>().toDartString();
      native.rust_free_error(result.error);
      if (result.data != nullptr) {
        native.rust_free_buffer(result.data, result.len);
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
    native.rust_free_buffer(result.data, result.len);

    return PipelineResponse(
      data: outputData,
      width: result.width,
      height: result.height,
    );
  }
}
