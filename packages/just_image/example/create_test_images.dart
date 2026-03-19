/// Generador de imágenes de prueba para los ejemplos de just_image.
/// Ejecutar: dart run example/create_test_images.dart
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

void main() {
  final dir = Directory('example/images');
  if (!dir.existsSync()) dir.createSync(recursive: true);

  // 1. Imagen con degradado rojo-azul (200x150)
  _writeBmp24('example/images/gradient.bmp', 200, 150, (x, y, w, h) {
    final r = (x / w * 255).round();
    final g = 50;
    final b = ((1 - x / w) * 255).round();
    return (r, g, b);
  });
  print('✓ gradient.bmp (200x150)');

  // 2. Imagen con patrón de tablero de ajedrez (160x160)
  _writeBmp24('example/images/checkerboard.bmp', 160, 160, (x, y, w, h) {
    final cellSize = 20;
    final isWhite = ((x ~/ cellSize) + (y ~/ cellSize)) % 2 == 0;
    return isWhite ? (240, 240, 240) : (30, 30, 30);
  });
  print('✓ checkerboard.bmp (160x160)');

  // 3. Imagen paisaje simulado con cielo y suelo (320x240)
  _writeBmp24('example/images/landscape.bmp', 320, 240, (x, y, w, h) {
    final ny = y / h;
    if (ny < 0.5) {
      // Cielo: degradado azul
      final t = ny / 0.5;
      return ((135 + t * 70).round(), (206 + t * 30).round(), 235);
    } else {
      // Suelo: verde con variación
      final t = (ny - 0.5) / 0.5;
      final noise = (sin(x * 0.3) * 15).round();
      return (
        (34 + t * 60 + noise).round().clamp(0, 255),
        (139 - t * 40 + noise).round().clamp(0, 255),
        34,
      );
    }
  });
  print('✓ landscape.bmp (320x240)');

  // 4. Imagen con círculos concéntricos (200x200)
  _writeBmp24('example/images/circles.bmp', 200, 200, (x, y, w, h) {
    final cx = w / 2, cy = h / 2;
    final dist = sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));
    final ring = (dist / 15).floor() % 2 == 0;
    if (ring) {
      return (255, (100 + dist).round().clamp(0, 255), 50);
    } else {
      return (50, 50, (200 - dist).round().clamp(0, 255));
    }
  });
  print('✓ circles.bmp (200x200)');

  // 5. Imagen para usar como watermark (80x30) — fondo oscuro con banda clara
  _writeBmp24('example/images/watermark.bmp', 80, 30, (x, y, w, h) {
    final inBand = y >= 8 && y <= 22 && x >= 5 && x <= 75;
    return inBand ? (255, 255, 255) : (40, 40, 40);
  });
  print('✓ watermark.bmp (80x30)');

  print('\n✅ Todas las imágenes creadas en example/images/');
}

/// Escribe una imagen BMP de 24 bits (sin compresión).
void _writeBmp24(
  String path,
  int width,
  int height,
  (int, int, int) Function(int x, int y, int w, int h) pixelFn,
) {
  // BMP rows must be padded to 4-byte boundary
  final rowBytes = width * 3;
  final padding = (4 - (rowBytes % 4)) % 4;
  final rowStride = rowBytes + padding;
  final pixelDataSize = rowStride * height;
  final fileSize = 54 + pixelDataSize;

  final data = ByteData(fileSize);
  var offset = 0;

  // File header (14 bytes)
  data.setUint8(offset++, 0x42); // 'B'
  data.setUint8(offset++, 0x4D); // 'M'
  data.setUint32(offset, fileSize, Endian.little);
  offset += 4;
  data.setUint32(offset, 0, Endian.little); // reserved
  offset += 4;
  data.setUint32(offset, 54, Endian.little); // pixel data offset
  offset += 4;

  // Info header (40 bytes)
  data.setUint32(offset, 40, Endian.little); // header size
  offset += 4;
  data.setInt32(offset, width, Endian.little);
  offset += 4;
  data.setInt32(offset, -height, Endian.little); // negative = top-down
  offset += 4;
  data.setUint16(offset, 1, Endian.little); // planes
  offset += 2;
  data.setUint16(offset, 24, Endian.little); // bits per pixel
  offset += 2;
  data.setUint32(offset, 0, Endian.little); // compression
  offset += 4;
  data.setUint32(offset, pixelDataSize, Endian.little); // image size
  offset += 4;
  data.setUint32(offset, 2835, Endian.little); // X pixels/meter (~72 DPI)
  offset += 4;
  data.setUint32(offset, 2835, Endian.little); // Y pixels/meter
  offset += 4;
  data.setUint32(offset, 0, Endian.little); // colors used
  offset += 4;
  data.setUint32(offset, 0, Endian.little); // important colors
  offset += 4;

  // Pixel data (BGR order)
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final (r, g, b) = pixelFn(x, y, width, height);
      data.setUint8(offset++, b.clamp(0, 255));
      data.setUint8(offset++, g.clamp(0, 255));
      data.setUint8(offset++, r.clamp(0, 255));
    }
    for (var p = 0; p < padding; p++) {
      data.setUint8(offset++, 0);
    }
  }

  File(path).writeAsBytesSync(data.buffer.asUint8List());
}
