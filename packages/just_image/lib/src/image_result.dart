import 'dart:typed_data';

/// Resultado inmutable de una operación de procesamiento de imagen.
final class ImageResult {
  /// Bytes codificados de la imagen resultante.
  final Uint8List data;

  /// Ancho de la imagen resultante en píxeles.
  final int width;

  /// Alto de la imagen resultante en píxeles.
  final int height;

  /// Formato de salida utilizado.
  final String format;

  const ImageResult({
    required this.data,
    required this.width,
    required this.height,
    required this.format,
  });

  /// Tamaño en bytes de la imagen resultante.
  int get sizeInBytes => data.length;
}
