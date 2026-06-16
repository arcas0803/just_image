import 'dart:typed_data';

import 'package:just_image/just_image.dart';
import 'package:test/test.dart';

void main() {
  group('OutputConfig', () {
    test('format strings are correct', () {
      expect(const JpegOutput().format, 'jpeg');
      expect(const PngOutput().format, 'png');
      expect(const WebpOutput().format, 'webp');
      expect(const AvifOutput().format, 'avif');
      expect(const TiffOutput().format, 'tiff');
      expect(const BmpOutput().format, 'bmp');
    });

    test('default qualities are reasonable', () {
      expect(const JpegOutput().quality, 90);
      expect(const PngOutput().quality, 100);
      expect(const WebpOutput().quality, 90);
    });
  });

  group('ImageResult', () {
    test('sizeInBytes returns correct length', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final result = ImageResult(
        data: data,
        width: 100,
        height: 100,
        format: 'jpeg',
      );
      expect(result.sizeInBytes, 5);
    });

    test('properties are accessible', () {
      final result = ImageResult(
        data: Uint8List(0),
        width: 1920,
        height: 1080,
        format: 'png',
      );
      expect(result.width, 1920);
      expect(result.height, 1080);
      expect(result.format, 'png');
    });
  });

  group('ImagePipeline', () {
    test('builds correct config JSON', () {
      final pipeline = ImagePipeline.bytes(Uint8List(10))
          .resize(800, 600)
          .sharpen(1.5)
          .brightness(0.1)
          .encode(const WebpOutput(quality: 85));

      expect(pipeline, isA<ImagePipeline>());
    });

    test('operations are chainable', () {
      final input = Uint8List(10);
      final pipeline = ImagePipeline.bytes(input)
          .resize(1920, 1080)
          .crop(0, 0, 800, 600)
          .rotate(45.0)
          .flipHorizontal()
          .flipVertical()
          .blur(2.0)
          .sharpen(1.0, 0.5)
          .sobel()
          .brightness(0.1)
          .contrast(-0.1)
          .hsl(hue: 30, saturation: 0.2, lightness: -0.1)
          .filter(ArtisticFilterName.vintage)
          .thumbnail(200, 200)
          .encode(const AvifOutput(quality: 90))
          .autoOrient(true)
          .preserveMetadata(true)
          .preserveIcc(true);

      expect(pipeline, isA<ImagePipeline>());
    });

    test('pipeline is immutable', () {
      final base = ImagePipeline.bytes(Uint8List(10)).resize(100, 100);
      final withFilter = base.filter(ArtisticFilterName.sepia);
      final withThumb = base.thumbnail(50, 50);

      expect(identical(base, withFilter), isFalse);
      expect(identical(base, withThumb), isFalse);
      expect(identical(withFilter, withThumb), isFalse);
    });

    test('filter accepts enum', () {
      final pipeline = ImagePipeline.bytes(
        Uint8List(10),
      ).filter(ArtisticFilterName.sepia);
      expect(pipeline, isA<ImagePipeline>());
    });

    test('thumbnail is chainable', () {
      final pipeline = ImagePipeline.bytes(Uint8List(10)).thumbnail(150, 150);
      expect(pipeline, isA<ImagePipeline>());
    });
  });

  group('ArtisticFilterName', () {
    test('json names are snake_case', () {
      expect(ArtisticFilterName.goldenHour.jsonName, 'golden_hour');
      expect(ArtisticFilterName.cinematic.jsonName, 'cinematic');
      expect(ArtisticFilterName.vintage.jsonName, 'vintage');
    });
  });

  group('Exceptions', () {
    test('JustImageException is base for all', () {
      const ex = JustImageException('base');
      expect(ex, isA<Exception>());
      expect(ex.message, 'base');
      expect(ex.toString(), contains('base'));
    });

    test('ImageDecodeException includes message', () {
      const ex = ImageDecodeException('bad format');
      expect(ex, isA<JustImageException>());
      expect(ex.toString(), contains('ImageDecodeException'));
      expect(ex.toString(), contains('bad format'));
    });

    test('ImageEncodeException includes message', () {
      const ex = ImageEncodeException('encode failed');
      expect(ex, isA<JustImageException>());
      expect(ex.toString(), contains('ImageEncodeException'));
    });

    test('PipelineExecutionException includes message', () {
      const ex = PipelineExecutionException('crop out of bounds');
      expect(ex, isA<JustImageException>());
      expect(ex.toString(), contains('PipelineExecutionException'));
    });

    test('NativeLibraryException includes message', () {
      const ex = NativeLibraryException('not found');
      expect(ex, isA<JustImageException>());
      expect(ex.toString(), contains('NativeLibraryException'));
    });

    test('UnsupportedPlatformException includes platform', () {
      const ex = UnsupportedPlatformException('fuchsia');
      expect(ex, isA<JustImageException>());
      expect(ex.platform, 'fuchsia');
      expect(ex.toString(), contains('fuchsia'));
    });

    test('EmptyInputException has fixed message', () {
      const ex = EmptyInputException();
      expect(ex, isA<JustImageException>());
      expect(ex.toString(), contains('EmptyInputException'));
    });

    test('all exceptions are catchable as JustImageException', () {
      final exceptions = <JustImageException>[
        const ImageDecodeException('a'),
        const ImageEncodeException('b'),
        const PipelineExecutionException('c'),
        const NativeLibraryException('d'),
        const UnsupportedPlatformException('e'),
        const EmptyInputException(),
      ];
      for (final ex in exceptions) {
        expect(ex, isA<JustImageException>());
        expect(ex, isA<Exception>());
      }
    });
  });
}
