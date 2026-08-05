# just_image

High-performance image processing for Dart and Flutter, powered by a Rust FFI
engine and Dart Native Assets.

## Why just_image

- JPEG, PNG, WebP, TIFF and BMP decoding and encoding.
- AVIF encoding.
- Resize, crop, rotate, flip and aspect-preserving thumbnails.
- Blur, sharpen, Sobel edges, HSL, brightness and contrast.
- Fifteen artistic filters, watermarks and BlurHash.
- EXIF auto-orientation and JPEG EXIF/ICC preservation.
- Immutable pipelines executed outside the UI isolate.
- Verified prebuilt native binaries: consumers do not install Rust.

HEIC and Flutter Web are not supported. AVIF is currently an output format;
AVIF input decoding is not included because it would require shipping libdav1d
for every mobile and desktop target.

## Installation

```yaml
dependencies:
  just_image: ^2.0.0
```

That is the complete consumer configuration. `dart run`, `dart test`,
`dart build` and Flutter builds automatically download, verify, cache and bundle
the correct native asset. No Cargo, NDK variables, Gradle, CMake, CocoaPods or
Xcode changes are required specifically for this package.

The first build needs access to GitHub Releases. Later builds reuse the
SHA-256-verified local cache.

Requirements:

- Dart 3.10.8 or newer.
- Flutter 3.38 or newer for Flutter applications.
- A normal platform toolchain when building a Flutter application, such as
  Xcode for iOS or the Android SDK for Android.

## Quick start

```dart
import 'dart:io';

import 'package:just_image/just_image.dart';

Future<void> main() async {
  final result = await File('photo.jpg')
      .justImage
      .resize(1280, 720)
      .filter(ArtisticFilterName.cinematic)
      .encode(OutputFormat.webp, quality: 85)
      .run();

  await File('photo.webp').writeAsBytes(result.data);
}
```

`run()` reads the source asynchronously and executes the CPU-heavy native
pipeline in a background isolate.

## Sources

```dart
ImagePipeline.bytes(imageBytes);
ImagePipeline.file(File('photo.jpg'));
ImagePipeline.xfile(xFile);
ImagePipeline.fromSource(customSource);
```

The same constructors are available through `.justImage` extensions on
`Uint8List`, `File` and `XFile`.

## Operations

```dart
final result = await ImagePipeline.bytes(imageBytes)
    .crop(20, 20, 800, 600)
    .rotate(90)
    .flipHorizontal()
    .blur(1.2)
    .sharpen(0.6)
    .brightness(0.05)
    .contrast(0.1)
    .hsl(hue: 8, saturation: 0.05, lightness: 0)
    .thumbnail(400, 300)
    .encode(OutputFormat.jpeg, quality: 90)
    .run();
```

Arguments are validated before crossing FFI. Invalid dimensions, ranges,
qualities or concurrency values produce an immediate Dart error.

### Watermark

```dart
final result = await ImagePipeline.bytes(imageBytes)
    .watermark(
      BytesSource(watermarkBytes),
      x: 24,
      y: 24,
      opacity: 0.7,
    )
    .encode(OutputFormat.png)
    .run();
```

### BlurHash

```dart
final hash = await JustImage.blurHashEncode(BytesSource(imageBytes));
final placeholder = await JustImage.blurHashDecode(
  hash,
  width: 32,
  height: 32,
);
```

### Image information

```dart
final info = await JustImage.info(FileSource(File('photo.jpg')));
print('${info.width}×${info.height}');
```

### Batch processing

```dart
final pipelines = files
    .map(
      (file) => ImagePipeline.file(file)
          .thumbnail(800, 800)
          .encode(OutputFormat.webp, quality: 85),
    )
    .toList();

final batch = await JustImage.processBatch(pipelines, concurrency: 4);
print('${batch.successCount} succeeded; ${batch.failureCount} failed');

for (var index = 0; index < batch.results.length; index++) {
  final result = batch.results[index];
  final error = batch.errors[index];
  // Exactly one of result or error is non-null.
}
```

## Output formats

| Format | Default quality | Input | Output |
|---|---:|:---:|:---:|
| JPEG | 90 | ✅ | ✅ |
| PNG | 100 | ✅ | ✅ |
| WebP | 90 | ✅ | ✅ |
| AVIF | 80 | — | ✅ |
| TIFF | 100 | ✅ | ✅ |
| BMP | 100 | ✅ | ✅ |

The legacy `JpegOutput`, `PngOutput`, `WebpOutput`, `AvifOutput`,
`TiffOutput` and `BmpOutput` classes remain available for source compatibility.

## Supported targets

| Platform | Architectures | Minimum |
|---|---|---|
| Android | arm64, arm32, x64 | API 24 |
| iOS device | arm64 | iOS 13 |
| iOS simulator | arm64, x64 | iOS 13 |
| macOS | arm64, x64 | macOS 10.15 |
| Windows | arm64, x64 | Windows 10 |
| Linux glibc | arm64, x64 | Ubuntu 20.04 / compatible glibc 2.31 |

Support means that the release pipeline produces a dedicated binary and checks
its integrity. Web, Fuchsia, musl/Alpine and 32-bit desktop targets are not part
of the 2.0.0 support matrix.

## Error model

All engine errors extend `JustImageException`:

- `ImageDecodeException`
- `ImageEncodeException`
- `PipelineExecutionException`
- `NativeLibraryException`
- `UnsupportedPlatformException`
- `EmptyInputException`

Batch operations capture per-item errors in `BatchResult` instead of aborting
the complete batch.

## Examples

- [`example/cli`](example/cli) is an independent Dart CLI consumer.
- [`example/flutter_app`](example/flutter_app) is an independent Flutter
  application with Android, iOS, Linux, macOS and Windows projects.
- [`example/just_image_example.dart`](example/just_image_example.dart) shows the
  complete API in a single script.

Both independent examples contain real native smoke tests and no package-
specific platform configuration.

## Developing just_image

Consumers use prebuilt binaries. Maintainers can compile the Rust source by
setting the package hook user define:

```yaml
hooks:
  user_defines:
    just_image:
      local_build: true
      debug_build: true
```

Run the complete local verification with:

```bash
cargo test --manifest-path src/native/Cargo.toml --locked
cargo clippy --manifest-path src/native/Cargo.toml --all-targets -- -D warnings
dart analyze --fatal-infos
dart test
(cd example/cli && dart run bin/main.dart)
(cd example/flutter_app && flutter test)
```

See [RELEASING.md](RELEASING.md) for the binary and pub.dev release process.

## License

See [LICENSE](LICENSE).
