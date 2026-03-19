import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'exceptions.dart';

// ──────────────────────────────────────────────
// Estructuras FFI que mapean a las de Rust
// ──────────────────────────────────────────────

/// Mapea a `FfiResult` en Rust.
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
// Typedefs para las funciones nativas
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

// ──────────────────────────────────────────────
// Datos transferidos al Isolate
// ──────────────────────────────────────────────

/// Datos para enviar al isolate de procesamiento.
/// Todos los campos son tipos simples serializables entre isolates.
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

/// Resultado del isolate de procesamiento.
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
// NativeBridge — Singleton FFI
// ──────────────────────────────────────────────

/// Puente FFI manual hacia la librería nativa de Rust.
///
/// Gestiona la carga de la librería dinámica y expone bindings tipados.
/// Toda la gestión de memoria (alloc/free) se maneja aquí.
class NativeBridge {
  static NativeBridge? _instance;
  late final DynamicLibrary _lib;

  late final _RustProcessPipelineDart _processPipeline;
  late final _RustFreeBufferDart _freeBuffer;
  late final _RustFreeErrorDart _freeError;
  late final _RustVersionDart _version;
  late final _RustFreeStringDart _freeString;
  late final _RustImageInfoDart _imageInfo;

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

  /// Obtiene la instancia singleton del bridge.
  factory NativeBridge() {
    _instance ??= NativeBridge._();
    return _instance!;
  }

  /// Carga la librería nativa según la plataforma.
  ///
  /// Con Native Assets (`hook/build.dart`) el SDK registra el asset
  /// automáticamente, por lo que basta con abrir por nombre convencional.
  /// En iOS la librería se enlaza estáticamente al runner.
  static DynamicLibrary _loadLibrary() {
    const baseName = 'just_image_native';

    if (Platform.isIOS) {
      return DynamicLibrary.process();
    }

    // Native Assets coloca la librería donde el sistema puede resolverla.
    final libName = _platformLibName(baseName);
    try {
      return DynamicLibrary.open(libName);
    } catch (e) {
      // Fallback: busca en src/native/target/release (dev sin Native Assets).
      try {
        final devPath =
            '${Directory.current.path}/packages/just_image/src/native/target/release/$libName';
        return DynamicLibrary.open(devPath);
      } catch (_) {
        // Último intento: ruta legacy raíz para backwards compat.
        try {
          final legacyPath =
              '${Directory.current.path}/native/target/release/$libName';
          return DynamicLibrary.open(legacyPath);
        } catch (_) {
          throw NativeLibraryException(
            'Could not load $libName. '
            'Ensure Rust is compiled: cd src/native && cargo build --release',
          );
        }
      }
    }
  }

  /// Devuelve el nombre del fichero de librería según la plataforma.
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
  }

  /// Versión de la librería nativa.
  String get nativeVersion {
    final ptr = _version();
    final version = ptr.toDartString();
    _freeString(ptr);
    return version;
  }

  /// Procesa una imagen a través del pipeline nativo.
  ///
  /// Gestión de memoria:
  /// 1. Dart alloca `inputPtr` con calloc y copia los bytes.
  /// 2. Rust lee el input, procesa y alloca el output.
  /// 3. Dart copia el output a un Uint8List de Dart.
  /// 4. Dart libera: el input (calloc.free) y el output (rust_free_buffer).
  PipelineResponse processPipeline(PipelineRequest request) {
    // 1. Alocar y copiar input a memoria nativa
    final inputPtr = calloc<Uint8>(request.inputBytes.length);
    final inputList = inputPtr.asTypedList(request.inputBytes.length);
    inputList.setAll(0, request.inputBytes);

    // 2. Serializar config JSON a C-string
    final configPtr = request.configJson.toNativeUtf8();

    // 3. Watermark (opcional)
    Pointer<Uint8> watermarkPtr = nullptr;
    int watermarkLen = 0;
    if (request.watermarkBytes != null && request.watermarkBytes!.isNotEmpty) {
      watermarkLen = request.watermarkBytes!.length;
      watermarkPtr = calloc<Uint8>(watermarkLen);
      watermarkPtr.asTypedList(watermarkLen).setAll(0, request.watermarkBytes!);
    }

    try {
      // 4. Llamar a Rust
      final result = _processPipeline(
        inputPtr,
        request.inputBytes.length,
        configPtr.cast<Utf8>(),
        watermarkPtr,
        watermarkLen,
      );

      // 5. Verificar error
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

      // 6. Copiar resultado a memoria de Dart (para liberar la de Rust)
      final outputData = Uint8List(result.len);
      if (result.len > 0 && result.data != nullptr) {
        outputData.setAll(0, result.data.asTypedList(result.len));
      }

      // 7. Liberar memoria de Rust
      _freeBuffer(result.data, result.len);

      return PipelineResponse(
        data: outputData,
        width: result.width,
        height: result.height,
      );
    } finally {
      // 8. Liberar memoria alocada por Dart
      calloc.free(inputPtr);
      calloc.free(configPtr);
      if (watermarkPtr != nullptr) {
        calloc.free(watermarkPtr);
      }
    }
  }

  /// Lee info básica de una imagen sin procesarla.
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
}
