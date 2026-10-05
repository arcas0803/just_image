import 'dart:typed_data';

import 'package:just_image/just_image.dart';
import 'package:test/test.dart';

import 'support/test_image.dart';

void main() {
  late Uint8List source;

  setUpAll(() {
    source = createTestBmp();
  });

  group('native pipeline', () {
    test('reads real image dimensions through FFI', () async {
      final info = await JustImage.info(BytesSource(source));
      expect(info.width, 8);
      expect(info.height, 6);
    });

    test('core ABI processes JPEG, PNG and BMP operations', () async {
      for (final format in [
        OutputFormat.jpeg,
        OutputFormat.png,
        OutputFormat.bmp,
      ]) {
        final result = await ImagePipeline.bytes(source)
            .resize(6, 4)
            .brightness(0.05)
            .encode(format)
            .runCore();
        expect(result.width, 6);
        expect(result.height, 4);
        expect(result.format.name, format.name);
        expect(result.data, isNotEmpty);
      }
    });

    test('core ABI rejects feature groups that require the full engine', () {
      expect(
        ImagePipeline.bytes(source).encode(OutputFormat.webp).runCore,
        throwsUnsupportedError,
      );
      expect(
        ImagePipeline.bytes(source)
            .filter(ArtisticFilterName.cinematic)
            .runCore,
        throwsUnsupportedError,
      );
    });

    for (final format in OutputFormat.values) {
      test('encodes a real ${format.name} image', () async {
        final result = await ImagePipeline.bytes(source)
            .resize(4, 3)
            .encode(format)
            .run();

        expect(result.width, 4);
        expect(result.height, 3);
        expect(result.format.name, format.name);
        expect(result.data, isNotEmpty);

        final decoded = await JustImage.info(BytesSource(result.data));
        expect(decoded.width, 4);
        expect(decoded.height, 3);
      });
    }

    test(
      'decodes AVIF input through the transparent extended pipeline',
      () async {
        final avif = await ImagePipeline.bytes(source)
            .encode(const AvifOutput(speed: 10))
            .run();
        final png = await ImagePipeline.avif(BytesSource(avif.data))
            .encode(const PngOutput())
            .run();
        expect((png.width, png.height), (8, 6));
        expect(png.data, isNotEmpty);
      },
    );

    test('rasterizes SVG input at an explicit size', () async {
      final svg = Uint8List.fromList(
        '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="10">'
                '<rect width="20" height="10" fill="#ff0000"/></svg>'
            .codeUnits,
      );
      final result = await ImagePipeline.svg(
        BytesSource(svg),
        width: 40,
      ).encode(const PngOutput()).run();
      expect((result.width, result.height), (40, 20));
    });

    test('arbitrary rotation expands or clips the canvas explicitly', () async {
      final expanded = await ImagePipeline.bytes(source)
          .rotate(45)
          .encode(const PngOutput())
          .run();
      final clipped = await ImagePipeline.bytes(source)
          .rotate(45, canvas: RotationCanvas.clip)
          .encode(const PngOutput())
          .run();
      expect(expanded.width, greaterThan(clipped.width));
      expect(expanded.height, greaterThan(clipped.height));
    });

    test('executes transforms, effects and a filter', () async {
      final result = await ImagePipeline.bytes(source)
          .resize(12, 10)
          .crop(2, 2, 8, 6)
          .rotate(90)
          .flipHorizontal()
          .blur(0.5)
          .sharpen(0.4)
          .brightness(0.05)
          .contrast(0.05)
          .hsl(hue: 10, saturation: 0.05, lightness: 0.05)
          .filter(ArtisticFilterName.cinematic)
          .thumbnail(3, 4)
          .encode(OutputFormat.png)
          .run();

      expect(result.width, lessThanOrEqualTo(3));
      expect(result.height, lessThanOrEqualTo(4));
      expect(result.data, isNotEmpty);
    });

    test('composites a real watermark', () async {
      final watermark = createTestBmp(width: 2, height: 2);
      final result = await ImagePipeline.bytes(source)
          .watermark(BytesSource(watermark), x: 1, y: 1, opacity: 0.5)
          .encode(OutputFormat.png)
          .run();
      expect(result.width, 8);
      expect(result.height, 6);
    });

    test('encodes and decodes BlurHash', () async {
      final hash = await JustImage.blurHashEncode(BytesSource(source));
      expect(hash, isNotEmpty);

      final decoded = await JustImage.blurHashDecode(hash, width: 5, height: 4);
      expect(decoded.width, 5);
      expect(decoded.height, 4);
      expect(decoded.format, ImageFormat.png);
      expect(decoded.data, isNotEmpty);
    });

    test('returns a typed error for invalid image bytes', () {
      expect(
        ImagePipeline.bytes(Uint8List.fromList([1, 2, 3]))
            .encode(OutputFormat.png)
            .run,
        throwsA(isA<ImageDecodeException>()),
      );
    });

    test('batch preserves successes and native failures', () async {
      final batch = await JustImage.processBatch([
        ImagePipeline.bytes(source).encode(OutputFormat.png),
        ImagePipeline.bytes(Uint8List.fromList([1, 2, 3]))
            .encode(OutputFormat.png),
        ImagePipeline.bytes(source).resize(2, 2).encode(OutputFormat.webp),
      ], concurrency: 2);

      expect(batch.successCount, 2);
      expect(batch.failureCount, 1);
      expect(batch.results[0], isNotNull);
      expect(batch.errors[1], isA<ImageDecodeException>());
      expect(batch.results[2]?.width, 2);
    });
  });

  group('public validation', () {
    test('rejects invalid dimensions and numeric ranges', () {
      expect(() => ImagePipeline.bytes(source).resize(0, 1), throwsRangeError);
      expect(
        () => ImagePipeline.bytes(source).crop(-1, 0, 1, 1),
        throwsRangeError,
      );
      expect(() => ImagePipeline.bytes(source).brightness(2), throwsRangeError);
      expect(
        () => ImagePipeline.bytes(source).blur(double.nan),
        throwsArgumentError,
      );
      expect(
        () => ImagePipeline.bytes(source).encode(OutputFormat.jpeg, quality: 0),
        throwsRangeError,
      );
    });

    test('rejects invalid batch concurrency without hanging', () {
      expect(
        JustImage.processBatch(const [], concurrency: 0),
        throwsRangeError,
      );
    });

    test('rejects incomplete resize arguments', () {
      expect(
        JustImage.process(BytesSource(source), width: 10),
        throwsArgumentError,
      );
    });
  });
}
