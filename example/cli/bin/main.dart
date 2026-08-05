import 'dart:io';
import 'dart:typed_data';

import 'package:just_image/just_image.dart';

Future<void> main(List<String> arguments) async {
  final outputOnly = arguments.firstOrNull?.startsWith('--output=') ?? false;
  final input = arguments.isEmpty || outputOnly
      ? _createBmp()
      : await File(arguments.first).readAsBytes();
  final outputPath = outputOnly
      ? arguments.first.substring('--output='.length)
      : arguments.length > 1
      ? arguments[1]
      : 'thumbnail.webp';

  final result = await ImagePipeline.bytes(input)
      .thumbnail(320, 240)
      .filter(ArtisticFilterName.cinematic)
      .encode(OutputFormat.webp, quality: 85)
      .run();

  await File(outputPath).writeAsBytes(result.data, flush: true);
  stdout.writeln(
    'Created $outputPath (${result.width}x${result.height}, '
    '${result.sizeInBytes} bytes)',
  );
}

Uint8List _createBmp() {
  const width = 640;
  const height = 360;
  const rowSize = width * 3;
  final bytes = Uint8List(54 + rowSize * height);
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
  data.setUint32(34, rowSize * height, Endian.little);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final offset = 54 + y * rowSize + x * 3;
      bytes[offset] = (255 * x ~/ width);
      bytes[offset + 1] = (255 * y ~/ height);
      bytes[offset + 2] = 180;
    }
  }
  return bytes;
}
