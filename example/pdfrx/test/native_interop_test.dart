import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_image/just_image.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PDFium renders a JPEG produced by the native image engine', () async {
    final svg = Uint8List.fromList(
      utf8.encode(
        '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="8">'
        '<rect width="16" height="8" fill="red"/></svg>',
      ),
    );
    final jpeg = await ImagePipeline.svg(BytesSource(svg))
        .encode(OutputFormat.jpeg)
        .run();

    Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
    await pdfrxFlutterInitialize();
    final document = await PdfDocument.createFromJpegData(
      jpeg.data,
      width: 16,
      height: 8,
      sourceName: 'just_image.jpg',
    );
    addTearDown(document.dispose);
    final reopened = await PdfDocument.openData(await document.encodePdf());
    addTearDown(reopened.dispose);
    final raster = await reopened.pages.single.render();
    expect(raster, isNotNull);
    addTearDown(raster!.dispose);
    expect((raster.width, raster.height), (16, 8));
    // PDFium returns BGRA. A blank page would also have the expected size.
    expect(raster.pixels[0], lessThan(30));
    expect(raster.pixels[1], lessThan(30));
    expect(raster.pixels[2], greaterThan(220));
  });
}
