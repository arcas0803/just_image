import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_image_flutter/just_image_flutter.dart';

void main() {
  group('just_image_flutter re-exports', () {
    test('ImageFormat enum is accessible', () {
      expect(ImageFormat.jpeg.value, 'jpeg');
      expect(ImageFormat.png.value, 'png');
      expect(ImageFormat.webp.value, 'webp');
      expect(ImageFormat.avif.value, 'avif');
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
      final pipeline = ImagePipeline(Uint8List(10));
      expect(pipeline, isA<ImagePipeline>());
    });

    test('filter and thumbnail are chainable', () {
      final pipeline = ImagePipeline(
        Uint8List(10),
      ).filter('vintage').thumbnail(200, 200);
      expect(pipeline, isA<ImagePipeline>());
    });

    test('JustImageEngine is constructible', () {
      // JustImageEngine loads the native library via FFI.
      // In unit-test mode the Rust dylib may not be compiled,
      // so we accept NativeLibraryException as a valid outcome.
      try {
        final engine = JustImageEngine();
        expect(engine, isA<JustImageEngine>());
      } on NativeLibraryException {
        // Expected when the Rust library is not compiled.
      }
    });

    test('FlipDirection is accessible', () {
      expect(FlipDirection.horizontal, isNotNull);
      expect(FlipDirection.vertical, isNotNull);
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
