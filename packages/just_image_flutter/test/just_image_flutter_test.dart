import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
// ignore_for_file: deprecated_export_use
import 'package:just_image_flutter/just_image_flutter.dart';

void main() {
  group('just_image_flutter re-exports', () {
    test('OutputConfig classes are accessible', () {
      expect(const JpegOutput().format, 'jpeg');
      expect(const PngOutput().format, 'png');
      expect(const WebpOutput().format, 'webp');
      expect(const AvifOutput().format, 'avif');
    });

    test('ImageResult is constructible', () {
      final result = ImageResult(
        data: Uint8List(0),
        width: 100,
        height: 100,
        format: 'png',
      );
      expect(result.width, 100);
      expect(result.height, 100);
      expect(result.format, 'png');
      expect(result.sizeInBytes, 0);
    });

    test('ImagePipeline is constructible', () {
      final pipeline = ImagePipeline.bytes(Uint8List(10));
      expect(pipeline, isA<ImagePipeline>());
    });

    test('filter and thumbnail are chainable', () {
      final pipeline = ImagePipeline.bytes(
        Uint8List(10),
      ).filter(ArtisticFilterName.vintage).thumbnail(200, 200);
      expect(pipeline, isA<ImagePipeline>());
    });

    test('JustImage is accessible', () {
      expect(JustImage, isNotNull);
    });

    test('flip methods are accessible', () {
      final pipeline = ImagePipeline.bytes(
        Uint8List(10),
      ).flipHorizontal().flipVertical();
      expect(pipeline, isA<ImagePipeline>());
    });

    test('Exception hierarchy is accessible', () {
      const base = JustImageException('test');
      expect(base, isA<Exception>());
      expect(base.message, 'test');

      const decode = ImageDecodeException('bad');
      expect(decode, isA<JustImageException>());

      const encode = ImageEncodeException('bad');
      expect(encode, isA<JustImageException>());

      const pipeline = PipelineExecutionException('bad');
      expect(pipeline, isA<JustImageException>());

      const native = NativeLibraryException('bad');
      expect(native, isA<JustImageException>());

      const empty = EmptyInputException();
      expect(empty, isA<JustImageException>());
    });
  });
}
