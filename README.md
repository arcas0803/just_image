# just_image

High-performance image processing for Dart and Flutter, powered by a Rust
engine and Dart Native Assets.

`just_image` works without package-specific platform configuration. Add the
dependency and use the API: consumers do not install Rust, configure Cargo,
edit Gradle or CMake files, add CocoaPods, or copy dynamic libraries.

## Features

- Decode and encode JPEG, PNG, WebP, TIFF and BMP.
- Resize, crop, rotate, flip and create aspect-preserving thumbnails.
- Blur, sharpen, Sobel edge detection, brightness, contrast and HSL changes.
- Apply 15 built-in artistic filters.
- Composite an image watermark with position and opacity.
- Encode and decode BlurHash placeholders.
- Read image dimensions without running a transformation pipeline.
- Auto-orient from EXIF and preserve JPEG EXIF/ICC data.
- Process batches concurrently while keeping per-image successes and errors.
- Run CPU-heavy work in a background Dart isolate.
- Download and verify the correct precompiled native binary automatically.

## Requirements

- Dart 3.10.8 or newer.
- Flutter 3.38 or newer for Flutter applications.
- The normal SDK/toolchain for the platform targeted by a Flutter app, such as
  Xcode for iOS or the Android SDK for Android.
- Network access to GitHub Releases on the first build. The verified binary is
  cached for subsequent builds.

## Installation

```yaml
dependencies:
  just_image: ^2.0.0
```

No additional consumer configuration is required.

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
  print('${result.width}x${result.height} · ${result.sizeInBytes} bytes');
}
```

`ImagePipeline` is immutable: every operation returns a new pipeline. `run()`
loads the source asynchronously and executes native processing in a background
isolate.

## Image sources

Use raw bytes, `dart:io` files, `cross_file` files or an explicit source:

```dart
ImagePipeline.bytes(imageBytes);
ImagePipeline.file(File('photo.jpg'));
ImagePipeline.xfile(xFile);
ImagePipeline.fromSource(BytesSource(imageBytes));
ImagePipeline.fromSource(FileSource(File('photo.jpg')));
ImagePipeline.fromSource(XFileSource(xFile));
```

`Uint8List`, `File` and `XFile` also expose the `.justImage` extension.

## Output formats

```dart
pipeline.encode(OutputFormat.jpeg, quality: 90);
pipeline.encode(OutputFormat.png);
pipeline.encode(OutputFormat.webp, quality: 85);
pipeline.encode(OutputFormat.tiff);
pipeline.encode(OutputFormat.bmp);
```

| Format | Decode | Encode | Default quality |
|---|:---:|:---:|---:|
| JPEG | Yes | Yes | 90 |
| PNG | Yes | Yes | 100 |
| WebP | Yes | Yes | 90 |
| TIFF | Yes | Yes | 100 |
| BMP | Yes | Yes | 100 |

The typed `JpegOutput`, `PngOutput`, `WebpOutput`, `TiffOutput` and `BmpOutput`
classes remain available:

```dart
pipeline.encode(const WebpOutput(quality: 85));
```

Quality must be between 1 and 100. For PNG, a value below 100 enables an
additional optimization pass; TIFF and BMP are lossless formats.

## Transformations

```dart
final result = await imageBytes.justImage
    .resize(1600, 900)          // Exact dimensions, Lanczos3.
    .crop(100, 50, 1200, 700)  // x, y, width, height.
    .rotate(12.5)               // Degrees; arbitrary angles are accepted.
    .flipHorizontal()
    .flipVertical()
    .thumbnail(400, 300)        // Fits inside the box; preserves ratio.
    .encode(OutputFormat.jpeg, quality: 90)
    .run();
```

Crop coordinates must remain inside the current image bounds. `resize()` uses
the exact requested dimensions and can change the aspect ratio; `thumbnail()`
does not upscale and preserves it.

## Effects and colour

```dart
final result = await imageBytes.justImage
    .blur(1.2)
    .sharpen(0.7, 0.05)
    .brightness(0.08) // -1.0 to 1.0.
    .contrast(0.12)   // -1.0 to 1.0.
    .hsl(
      hue: 10,        // Rotation in degrees.
      saturation: 0.1,
      lightness: -0.05,
    )
    .encode(OutputFormat.png)
    .run();
```

Saturation and lightness accept values from -1.0 to 1.0. Blur and sharpen
values must be finite and non-negative.

Sobel edge detection returns an opaque greyscale edge image:

```dart
final edges = await imageBytes.justImage
    .sobel()
    .encode(OutputFormat.png)
    .run();
```

## Artistic filters

```dart
final result = await imageBytes.justImage
    .filter(ArtisticFilterName.goldenHour)
    .encode(OutputFormat.webp, quality: 90)
    .run();
```

Available values are `vintage`, `sepia`, `cool`, `warm`, `marine`, `dramatic`,
`lomo`, `retro`, `noir`, `bloom`, `polaroid`, `goldenHour`, `arctic`,
`cinematic` and `fade`.

## Watermarks

```dart
final result = await imageBytes.justImage
    .watermark(
      FileSource(File('logo.png')),
      x: 24,
      y: 24,
      opacity: 0.7,
    )
    .encode(OutputFormat.png)
    .run();
```

Opacity accepts 0.0 to 1.0. The watermark is clipped when it extends beyond the
base image. A pipeline supports one watermark source; calling `watermark()`
again replaces the source associated with all watermark operations.

## BlurHash

```dart
final hash = await JustImage.blurHashEncode(
  BytesSource(imageBytes),
  componentsX: 4,
  componentsY: 3,
);

final placeholder = await JustImage.blurHashDecode(
  hash,
  width: 32,
  height: 32,
);
```

BlurHash components must be between 1 and 9. Decoding returns a PNG
`ImageResult`.

## Image information

```dart
final info = await JustImage.info(FileSource(File('photo.jpg')));
print('${info.width}x${info.height}');
```

This decodes enough of the image to return its dimensions and reports invalid
or unsupported input as `ImageDecodeException`.

## Batch processing

```dart
final pipelines = files
    .map(
      (file) => file.justImage
          .thumbnail(800, 800)
          .encode(OutputFormat.webp, quality: 85),
    )
    .toList();

final batch = await JustImage.processBatch(pipelines, concurrency: 4);

print('${batch.successCount} succeeded');
print('${batch.failureCount} failed');

for (var index = 0; index < batch.results.length; index++) {
  final image = batch.results[index];
  final error = batch.errors[index];
  // Exactly one of image or error is non-null.
}
```

Input order is preserved. A failure does not cancel the remaining images.
Concurrency must be greater than zero and should be chosen according to the
memory available to the application.

## Orientation, EXIF and colour profiles

These options default to `true`:

```dart
final result = await imageBytes.justImage
    .autoOrient(true)
    .preserveMetadata(true)
    .preserveIcc(true)
    .encode(OutputFormat.jpeg)
    .run();
```

EXIF orientation is applied when present. Raw EXIF and ICC reinjection is
implemented for JPEG output. Other output formats retain processed pixels but
do not currently receive the original metadata blocks.

## Errors and validation

Public arguments are validated before crossing FFI. Native panics are contained
and converted into Dart errors. All package errors extend
`JustImageException`:

- `EmptyInputException`
- `ImageDecodeException`
- `ImageEncodeException`
- `PipelineExecutionException`
- `NativeLibraryException`
- `UnsupportedPlatformException`

```dart
try {
  await File('input.jpg').justImage
      .crop(0, 0, 10000, 10000)
      .encode(OutputFormat.webp)
      .run();
} on ImageDecodeException catch (error) {
  print('The input cannot be decoded: $error');
} on PipelineExecutionException catch (error) {
  print('An operation failed: $error');
} on JustImageException catch (error) {
  print('Image processing failed: $error');
}
```

## Supported platforms

Every published version provides a dedicated SHA-256-verified binary for each
entry below.

| Platform | Architectures | Minimum |
|---|---|---|
| Android | arm32, arm64, x64 | API 24 |
| iOS device | arm64 | iOS 13 |
| iOS simulator | arm64, x64 | iOS 13 |
| macOS | arm64, x64 | macOS 10.15 |
| Windows | arm64, x64 | Windows 10 |
| Linux glibc | arm64, x64 | glibc 2.31 |

## Limitations

- AVIF, HEIC/HEIF, GIF, SVG, RAW camera formats and animated images are not
  supported.
- Flutter Web, Fuchsia, Alpine/musl and 32-bit desktop systems are not
  supported.
- Linux binaries target glibc 2.31 or newer; musl-based distributions need a
  future dedicated build.
- Processing is in memory. Large images and high batch concurrency can require
  substantial RAM; there is no streaming/tiled decoder.
- Output animation is not supported; every result is a single raster image.
- Metadata preservation is limited to JPEG EXIF and ICC output blocks. GPS or
  other sensitive EXIF data is preserved when `preserveMetadata(true)` is used.
- Rotation by non-right angles keeps the original canvas size, can clip the
  corners and introduces transparent pixels in newly exposed areas.
- WebP quality 100 selects lossless encoding. PNG quality below 100 controls an
  optimization pass rather than visual quality.
- The first build requires access to the package's GitHub Releases. Offline
  first-time installation is not supported.

## Examples

- [`example/cli`](example/cli) is an independent Dart CLI project.
- [`example/flutter_app`](example/flutter_app) is an independent Flutter app
  with Android, iOS, Linux, macOS and Windows projects.
- [`example/just_image_example.dart`](example/just_image_example.dart) contains
  additional API examples.

Both independent projects consume `just_image` without platform-specific
package configuration.

## Native binary delivery

Release automation compiles 12 native binaries, publishes them as immutable
GitHub Release assets and embeds their SHA-256 hashes in the pub.dev package.
The Native Assets build hook chooses the correct target, verifies the download,
caches it by version and registers it with Dart or Flutter. Temporary GitHub
Actions artifacts are retained for one day and deleted after publication.

When developing this package itself, maintainers can opt into a local Cargo
build with Native Assets user defines:

```yaml
hooks:
  user_defines:
    just_image:
      local_build: true
      debug_build: true
```

Consumers should not add these settings.

## License

See [LICENSE](LICENSE).
