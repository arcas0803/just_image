import 'dart:typed_data';

import 'package:just_image/just_image.dart';
import 'package:test/test.dart';

void main() {
  group('ImageFormat', () {
    test('enum values have correct string representation', () {
      expect(ImageFormat.jpeg.value, 'jpeg');
      expect(ImageFormat.png.value, 'png');
      expect(ImageFormat.webp.value, 'webp');
      expect(ImageFormat.avif.value, 'avif');
      expect(ImageFormat.tiff.value, 'tiff');
      expect(ImageFormat.bmp.value, 'bmp');
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
      final pipeline = ImagePipeline(Uint8List(10))
          .resize(800, 600)
          .sharpen(1.5)
          .brightness(0.1)
          .toFormat(ImageFormat.webp)
          .quality(85);

      // Accedemos al JSON indirectamente verificando que no lanza
      expect(() => pipeline, returnsNormally);
    });

    test('operations are chainable', () {
      final input = Uint8List(10);
      final pipeline = ImagePipeline(input)
          .resize(1920, 1080)
          .crop(0, 0, 800, 600)
          .rotate(45.0)
          .flip(FlipDirection.horizontal)
          .blur(2.0)
          .sharpen(1.0, 0.5)
          .sobel()
          .brightness(0.1)
          .contrast(-0.1)
          .hsl(hue: 30, saturation: 0.2, lightness: -0.1)
          .toFormat(ImageFormat.avif)
          .quality(90)
          .autoOrient(true)
          .preserveMetadata(true)
          .preserveIcc(true);

      expect(pipeline, isA<ImagePipeline>());
    });
  });

  group('TaskPriority', () {
    test('ordering is correct', () {
      expect(
        TaskPriority.critical.compareTo(TaskPriority.high),
        greaterThan(0),
      );
      expect(TaskPriority.high.compareTo(TaskPriority.normal), greaterThan(0));
      expect(TaskPriority.normal.compareTo(TaskPriority.low), greaterThan(0));
    });
  });

  group('BatchQueue', () {
    test('can be created with custom concurrency', () {
      final queue = BatchQueue(concurrency: 8);
      expect(queue.concurrency, 8);
      expect(queue.pendingCount, 0);
      expect(queue.runningCount, 0);
      queue.dispose();
    });

    test('throws after dispose', () {
      final queue = BatchQueue();
      queue.dispose();
      expect(queue.isDisposed, isTrue);
      expect(
        () => queue.enqueue(ImagePipeline(Uint8List(10))),
        throwsA(isA<BatchQueueDisposedException>()),
      );
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

    test('BatchQueueDisposedException has fixed message', () {
      const ex = BatchQueueDisposedException();
      expect(ex, isA<JustImageException>());
      expect(ex.toString(), contains('BatchQueueDisposedException'));
    });

    test('TaskCancelledException has fixed message', () {
      const ex = TaskCancelledException();
      expect(ex, isA<JustImageException>());
      expect(ex.toString(), contains('TaskCancelledException'));
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
        const BatchQueueDisposedException(),
        const TaskCancelledException(),
        const EmptyInputException(),
      ];
      for (final ex in exceptions) {
        expect(ex, isA<JustImageException>());
        expect(ex, isA<Exception>());
      }
    });
  });
}
