import 'dart:typed_data';

import 'batch_queue.dart';
import 'image_format.dart';
import 'image_pipeline.dart';
import 'image_result.dart';
import 'native_bridge.dart';

/// Motor principal de procesamiento de imágenes.
///
/// Punto de entrada de alto nivel que encapsula el bridge nativo,
/// la creación de pipelines y el batch processing.
///
/// ```dart
/// final engine = JustImageEngine();
/// final result = await engine
///     .load(imageBytes)
///     .resize(1920, 1080)
///     .sharpen(1.5)
///     .toFormat(ImageFormat.avif)
///     .execute();
/// ```
class JustImageEngine {
  late final NativeBridge _bridge;
  BatchQueue? _batchQueue;

  JustImageEngine() {
    _bridge = NativeBridge();
  }

  /// Versión de la librería nativa subyacente.
  String get nativeVersion => _bridge.nativeVersion;

  /// Crea un nuevo pipeline de procesamiento a partir de bytes de imagen.
  ImagePipeline load(Uint8List bytes) => ImagePipeline(bytes);

  /// Obtiene la cola de batch processing. Crea una nueva si no existe.
  BatchQueue get batch {
    _batchQueue ??= BatchQueue();
    return _batchQueue!;
  }

  /// Crea una cola de batch con concurrencia personalizada.
  BatchQueue createBatch({int concurrency = 4}) {
    _batchQueue?.dispose();
    _batchQueue = BatchQueue(concurrency: concurrency);
    return _batchQueue!;
  }

  /// Procesamiento rápido: carga, procesa y devuelve en una sola llamada.
  Future<ImageResult> process(
    Uint8List bytes, {
    int? width,
    int? height,
    ImageFormat format = ImageFormat.jpeg,
    int quality = 90,
  }) {
    var pipeline = load(bytes).toFormat(format).quality(quality);
    if (width != null && height != null) {
      pipeline = pipeline.resize(width, height);
    }
    return pipeline.execute();
  }

  /// Libera recursos del engine.
  void dispose() {
    _batchQueue?.dispose();
  }
}
