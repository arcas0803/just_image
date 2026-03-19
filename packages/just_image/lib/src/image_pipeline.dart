import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'exceptions.dart';
import 'image_format.dart';
import 'image_result.dart';
import 'native_bridge.dart';

/// Pipeline de procesamiento de imágenes con API fluent encadenable.
///
/// Ejemplo:
/// ```dart
/// final result = await ImagePipeline(bytes)
///     .resize(1920, 1080)
///     .sharpen(1.5)
///     .toFormat(ImageFormat.avif)
///     .execute();
/// ```
class ImagePipeline {
  final Uint8List _inputBytes;
  final List<Map<String, dynamic>> _operations = [];
  Uint8List? _watermarkBytes;
  String _outputFormat = 'jpeg';
  int _quality = 90;
  bool _autoOrient = true;
  bool _preserveMetadata = true;
  bool _preserveIcc = true;

  /// Crea un pipeline a partir de bytes de imagen raw.
  ImagePipeline(this._inputBytes);

  // ────────────────────────────────
  // Configuración
  // ────────────────────────────────

  /// Formato de salida.
  ImagePipeline toFormat(ImageFormat format) {
    _outputFormat = format.value;
    return this;
  }

  /// Calidad de compresión (1-100).
  ImagePipeline quality(int q) {
    _quality = q.clamp(1, 100);
    return this;
  }

  /// Habilita/deshabilita auto-orientación EXIF.
  ImagePipeline autoOrient(bool enabled) {
    _autoOrient = enabled;
    return this;
  }

  /// Habilita/deshabilita preservación de metadatos EXIF.
  ImagePipeline preserveMetadata(bool enabled) {
    _preserveMetadata = enabled;
    return this;
  }

  /// Habilita/deshabilita preservación del perfil ICC.
  ImagePipeline preserveIcc(bool enabled) {
    _preserveIcc = enabled;
    return this;
  }

  // ────────────────────────────────
  // Transformaciones
  // ────────────────────────────────

  /// Resize con Lanczos3.
  ImagePipeline resize(int width, int height) {
    _operations.add({'type': 'resize', 'width': width, 'height': height});
    return this;
  }

  /// Recorte rectangular.
  ImagePipeline crop(int x, int y, int width, int height) {
    _operations.add({
      'type': 'crop',
      'x': x,
      'y': y,
      'width': width,
      'height': height,
    });
    return this;
  }

  /// Rotación en grados (ángulos libres).
  ImagePipeline rotate(double degrees) {
    _operations.add({'type': 'rotate', 'degrees': degrees});
    return this;
  }

  /// Flip horizontal o vertical.
  ImagePipeline flip(FlipDirection direction) {
    _operations.add({
      'type': direction == FlipDirection.horizontal
          ? 'flip_horizontal'
          : 'flip_vertical',
    });
    return this;
  }

  // ────────────────────────────────
  // Efectos
  // ────────────────────────────────

  /// Gaussian Blur con sigma dinámico.
  ImagePipeline blur(double sigma) {
    _operations.add({'type': 'blur', 'sigma': sigma});
    return this;
  }

  /// Unsharp Mask (sharpen).
  ImagePipeline sharpen(double amount, [double threshold = 0.0]) {
    _operations.add({
      'type': 'sharpen',
      'amount': amount,
      'threshold': threshold,
    });
    return this;
  }

  /// Detección de bordes (Sobel).
  ImagePipeline sobel() {
    _operations.add({'type': 'sobel'});
    return this;
  }

  /// Ajuste de brillo [-1.0, 1.0].
  ImagePipeline brightness(double value) {
    _operations.add({'type': 'brightness', 'value': value});
    return this;
  }

  /// Ajuste de contraste [-1.0, 1.0].
  ImagePipeline contrast(double value) {
    _operations.add({'type': 'contrast', 'value': value});
    return this;
  }

  /// Ajuste HSL.
  /// [hue] rotación en grados, [saturation] y [lightness] en [-1.0, 1.0].
  ImagePipeline hsl({
    double hue = 0,
    double saturation = 0,
    double lightness = 0,
  }) {
    _operations.add({
      'type': 'hsl',
      'hue': hue,
      'saturation': saturation,
      'lightness': lightness,
    });
    return this;
  }

  /// Marca de agua con bytes de imagen overlay.
  ImagePipeline watermark(
    Uint8List overlayBytes, {
    int x = 0,
    int y = 0,
    double opacity = 1.0,
  }) {
    _watermarkBytes = overlayBytes;
    _operations.add({'type': 'watermark', 'x': x, 'y': y, 'opacity': opacity});
    return this;
  }

  // ────────────────────────────────
  // Ejecución
  // ────────────────────────────────

  /// Construye el JSON de configuración del pipeline.
  String _buildConfigJson() {
    final config = {
      'output_format': _outputFormat,
      'quality': _quality,
      'auto_orient': _autoOrient,
      'preserve_metadata': _preserveMetadata,
      'preserve_icc': _preserveIcc,
      'operations': _operations,
    };
    return jsonEncode(config);
  }

  /// Ejecuta el pipeline de forma síncrona (bloquea el hilo actual).
  /// Úsese solo en isolates o scripts CLI.
  ImageResult executeSync() {
    if (_inputBytes.isEmpty) {
      throw const EmptyInputException();
    }

    final bridge = NativeBridge();
    final request = PipelineRequest(
      inputBytes: _inputBytes,
      configJson: _buildConfigJson(),
      watermarkBytes: _watermarkBytes,
    );

    final response = bridge.processPipeline(request);

    if (response.error != null) {
      throw _classifyNativeError(response.error!);
    }

    return ImageResult(
      data: response.data,
      width: response.width,
      height: response.height,
      format: _outputFormat,
    );
  }

  /// Ejecuta el pipeline en un Isolate de fondo.
  /// Esta es la forma recomendada de usar el pipeline.
  Future<ImageResult> execute() async {
    final configJson = _buildConfigJson();
    final watermark = _watermarkBytes;
    final input = _inputBytes;
    final format = _outputFormat;

    final response = await Isolate.run(() {
      final bridge = NativeBridge();
      final request = PipelineRequest(
        inputBytes: input,
        configJson: configJson,
        watermarkBytes: watermark,
      );
      return bridge.processPipeline(request);
    });

    if (response.error != null) {
      throw _classifyNativeError(response.error!);
    }

    return ImageResult(
      data: response.data,
      width: response.width,
      height: response.height,
      format: format,
    );
  }
}

/// Clasifica el mensaje de error del motor nativo en la excepción apropiada.
JustImageException _classifyNativeError(String message) {
  final lower = message.toLowerCase();
  if (lower.contains('decode error') ||
      lower.contains('unsupported image format')) {
    return ImageDecodeException(message);
  }
  if (lower.contains('encode error') ||
      lower.contains('unsupported output format')) {
    return ImageEncodeException(message);
  }
  if (lower.contains('null or empty input')) {
    return const EmptyInputException();
  }
  return PipelineExecutionException(message);
}
