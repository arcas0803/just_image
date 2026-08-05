import 'dart:typed_data';

/// Builds a deterministic 24-bit BMP without depending on another image
/// package. This keeps the FFI integration tests self-contained.
Uint8List createTestBmp({int width = 8, int height = 6}) {
  final rowSize = ((width * 3 + 3) ~/ 4) * 4;
  final pixelBytes = rowSize * height;
  final bytes = Uint8List(54 + pixelBytes);
  final data = ByteData.sublistView(bytes);

  bytes[0] = 0x42;
  bytes[1] = 0x4d;
  data.setUint32(2, bytes.length, Endian.little);
  data.setUint32(10, 54, Endian.little);
  data.setUint32(14, 40, Endian.little);
  data.setInt32(18, width, Endian.little);
  data.setInt32(22, height, Endian.little);
  data.setUint16(26, 1, Endian.little);
  data.setUint16(28, 24, Endian.little);
  data.setUint32(34, pixelBytes, Endian.little);

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final offset = 54 + y * rowSize + x * 3;
      bytes[offset] = (x * 31 + y * 17) & 0xff;
      bytes[offset + 1] = (x * 13 + y * 43) & 0xff;
      bytes[offset + 2] = (x * 47 + y * 7) & 0xff;
    }
  }
  return bytes;
}
