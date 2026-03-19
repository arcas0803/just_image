/// Sistema de excepciones de just_image.
///
/// Todas las excepciones extienden [JustImageException], lo que permite
/// capturarlas de forma granular o con un solo `catch`.
///
/// ```dart
/// try {
///   final result = await pipeline.execute();
/// } on ImageDecodeException catch (e) {
///   print('Formato no reconocido: $e');
/// } on ImageEncodeException catch (e) {
///   print('Error al codificar: $e');
/// } on JustImageException catch (e) {
///   print('Error general de just_image: $e');
/// }
/// ```
library;

/// Excepción base de just_image.
///
/// Todas las excepciones del paquete heredan de esta clase.
/// Captúrala para manejar cualquier error del motor de forma genérica.
class JustImageException implements Exception {
  /// Descripción legible del error.
  final String message;

  const JustImageException(this.message);

  @override
  String toString() => 'JustImageException: $message';
}

// ─────────────────────────────────────────
// Errores de entrada / decodificación
// ─────────────────────────────────────────

/// Los bytes de entrada no representan una imagen válida o el formato
/// no es soportado.
///
/// **Causa común:** se pasaron bytes que no son una imagen (p. ej. un PDF)
/// o el archivo está corrupto.
class ImageDecodeException extends JustImageException {
  const ImageDecodeException(super.message);

  @override
  String toString() => 'ImageDecodeException: $message';
}

// ─────────────────────────────────────────
// Errores de codificación / salida
// ─────────────────────────────────────────

/// El motor no pudo codificar la imagen en el formato de salida solicitado.
///
/// **Causa común:** formato de salida no soportado, o parámetros de calidad
/// incompatibles con el codec (p. ej. quality > 100).
class ImageEncodeException extends JustImageException {
  const ImageEncodeException(super.message);

  @override
  String toString() => 'ImageEncodeException: $message';
}

// ─────────────────────────────────────────
// Errores de procesamiento / pipeline
// ─────────────────────────────────────────

/// Una operación dentro del pipeline falló durante la ejecución.
///
/// **Causa común:** parámetros inválidos en una operación (p. ej.
/// `crop` con coordenadas fuera de los límites de la imagen, o
/// `resize` con dimensiones cero).
class PipelineExecutionException extends JustImageException {
  const PipelineExecutionException(super.message);

  @override
  String toString() => 'PipelineExecutionException: $message';
}

// ─────────────────────────────────────────
// Errores de la librería nativa
// ─────────────────────────────────────────

/// No se pudo cargar la librería nativa de Rust (.dylib/.so/.dll).
///
/// **Causa común:** la librería nativa no se compiló, no se encuentra en la
/// ruta esperada, o la plataforma actual no tiene un binario compatible.
///
/// **Solución:** ejecuta `cd native && cargo build --release` y asegúrate
/// de que el binario resultante está accesible.
class NativeLibraryException extends JustImageException {
  const NativeLibraryException(super.message);

  @override
  String toString() => 'NativeLibraryException: $message';
}

/// La plataforma actual no está soportada por el motor nativo.
///
/// **Causa común:** se ejecuta en una plataforma para la que no existe
/// un binario compilado (p. ej. Fuchsia).
class UnsupportedPlatformException extends JustImageException {
  /// Sistema operativo detectado.
  final String platform;

  const UnsupportedPlatformException(this.platform)
    : super('Platform "$platform" is not supported');

  @override
  String toString() =>
      'UnsupportedPlatformException: Platform "$platform" is not supported';
}

// ─────────────────────────────────────────
// Errores de la cola batch
// ─────────────────────────────────────────

/// Se intentó operar sobre un [BatchQueue] que ya fue desechado.
///
/// **Causa común:** se llamó a `enqueue()` después de `dispose()`.
///
/// **Solución:** crea un nuevo `BatchQueue` si necesitas seguir procesando.
class BatchQueueDisposedException extends JustImageException {
  const BatchQueueDisposedException()
    : super('BatchQueue has been disposed. Create a new one to continue.');

  @override
  String toString() => 'BatchQueueDisposedException: $message';
}

/// Una tarea fue cancelada porque el [BatchQueue] se cerró antes de
/// que pudiera ejecutarse.
///
/// **Causa común:** se llamó a `dispose()` mientras había tareas pendientes
/// en la cola.
class TaskCancelledException extends JustImageException {
  const TaskCancelledException()
    : super('Task was cancelled because the BatchQueue was disposed.');

  @override
  String toString() => 'TaskCancelledException: $message';
}

// ─────────────────────────────────────────
// Error de input vacío
// ─────────────────────────────────────────

/// Se proporcionó un buffer de entrada vacío al pipeline.
///
/// **Causa común:** se leyó un archivo de 0 bytes, o se pasó un
/// `Uint8List` vacío a `ImagePipeline`.
class EmptyInputException extends JustImageException {
  const EmptyInputException()
    : super('Input image bytes are empty. Provide a non-empty Uint8List.');

  @override
  String toString() => 'EmptyInputException: $message';
}
