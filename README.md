# just_image

High-performance image processing for Dart and Flutter, powered by a Rust
engine and Dart Native Assets.

`just_image` works without package-specific platform configuration. Add the
dependency and use the API: consumers do not install Rust, configure Cargo,
edit Gradle or CMake files, add CocoaPods, or copy dynamic libraries.

## Features

- Decode and encode JPEG, PNG, WebP, TIFF, BMP and AVIF; rasterize SVG input.
- Resize, crop, rotate, flip and create aspect-preserving thumbnails.
- Blur, sharpen, Sobel edge detection, brightness, contrast and HSL changes.
- Apply 15 built-in artistic filters.
- Composite an image watermark with position and opacity.
- Encode and decode BlurHash placeholders.
- Read image dimensions without running a transformation pipeline.
- Auto-orient from EXIF and preserve EXIF/ICC data with an optional privacy-safe policy.
- Process batches concurrently while keeping per-image successes and errors.
- Run CPU-heavy work in a background Dart isolate.
- Download and verify the correct precompiled native binary automatically.
- Tree-shake unused Rust entry points and optional native feature groups in
  Dart 3.13 release builds.

## Requirements

- Dart 3.13 or newer.
- Flutter 3.47 or newer for Flutter applications.
- The normal SDK/toolchain for the platform targeted by a Flutter app, such as
  Xcode for iOS or the Android SDK for Android.
- A C linker for standalone Dart release/AOT builds (normally Clang, GCC or
  the Visual Studio toolchain). Flutter supplies the corresponding linker via
  Xcode, the Android NDK or Visual Studio.
- Network access to GitHub Releases on the first build. The verified binary is
  cached for subsequent builds.

## Installation

```yaml
dependencies:
  just_image: ^3.0.0
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

## Transparent native tree shaking

Release/AOT builds use Dart 3.13 recorded usages to retain only the native FFI
entry points reached by the application. If no native API is used, the Rust
library is omitted from the bundle entirely.

Use the normal `run()` API. The immutable pipeline records which native group
is required while it is built and dispatches internally:

```dart
final result = await imageBytes.justImage
    .resize(1280, 720)
    .brightness(0.05)
    .encode(OutputFormat.png)
    .run();
```

JPEG/PNG/BMP and basic operations stay in the core group; WebP/TIFF,
EXIF/ICC, watermarks and filters select the standard group; AVIF/SVG select
the extended group. Typed output configurations and explicit AVIF/SVG input
constructors make that choice visible to Dart's tree shaker without requiring
a separate execution method. The deprecated `runCore()` and `processCore()`
remain only as migration aids.

Reference macOS arm64 AOT measurement for this release:

| Reachable group | Native bundle |
|---|---:|
| Core | 1,924,992 bytes |
| Standard | 4,097,520 bytes |
| Extended | 9,875,952 bytes |

Core is 53.0% smaller than standard in that build. Exact sizes vary by target
and linker; CI rebuilds all four fixtures and verifies symbol isolation and
ordering on every change.

## Image sources

Use raw bytes, `dart:io` files, `cross_file` files or an explicit source:

```dart
ImagePipeline.bytes(imageBytes);
ImagePipeline.file(File('photo.jpg'));
ImagePipeline.xfile(xFile);
ImagePipeline.fromSource(BytesSource(imageBytes));
ImagePipeline.fromSource(FileSource(File('photo.jpg')));
ImagePipeline.fromSource(XFileSource(xFile));
ImagePipeline.avif(BytesSource(avifBytes));
ImagePipeline.svg(BytesSource(svgBytes), width: 1200);
```

`Uint8List`, `File` and `XFile` also expose the `.justImage` extension.

## Output formats

```dart
pipeline.encode(OutputFormat.jpeg, quality: 90);
pipeline.encode(OutputFormat.png);
pipeline.encode(OutputFormat.webp, quality: 85);
pipeline.encode(OutputFormat.tiff);
pipeline.encode(OutputFormat.bmp);
pipeline.encode(OutputFormat.avif);
```

| Format | Decode | Encode | Default quality |
|---|:---:|:---:|---:|
| JPEG | Yes | Yes | 90 |
| PNG | Yes | Yes | 100 |
| WebP | Yes | Yes | 90 |
| TIFF | Yes | Yes | 100 |
| BMP | Yes | Yes | 100 |
| AVIF | Yes | Yes | 80 |
| SVG | Rasterize | No | — |

Typed configurations expose codec-specific controls:

```dart
pipeline.encode(const PngOutput(
  compression: PngCompression.best,
  filter: PngFilter.adaptive,
  optimizationLevel: 4,
));
pipeline.encode(const WebpOutput.lossless());
pipeline.encode(const AvifOutput(quality: 80, speed: 6, threads: 4));
```

Quality must be between 1 and 100. PNG `optimizationLevel` ranges from 0 to 6;
AVIF `speed` ranges from 1 (smallest/slower) to 10 (fastest). TIFF and BMP are
lossless formats. `WebpOutput.lossless()` explicitly selects lossless WebP;
quality 100 retains the v2 lossless behavior for compatibility.

## Transformations

```dart
final result = await imageBytes.justImage
    .resize(1600, 900)          // Exact dimensions, Lanczos3.
    .crop(100, 50, 1200, 700)  // x, y, width, height.
    .rotate(12.5)               // Expands the canvas; no clipped corners.
    .flipHorizontal()
    .flipVertical()
    .thumbnail(400, 300)        // Fits inside the box; preserves ratio.
    .encode(OutputFormat.jpeg, quality: 90)
    .run();
```

Crop coordinates must remain inside the current image bounds. `resize()` uses
the exact requested dimensions and can change the aspect ratio; `thumbnail()`
does not upscale and preserves it.

Arbitrary rotations expand the canvas by default. To preserve the old clipped
canvas, or select a fill colour, configure the operation explicitly:

```dart
pipeline.rotate(
  12.5,
  canvas: RotationCanvas.clip,
  background: 0xff202020, // ARGB.
);
```

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

These options default to disabled so an ordinary JPEG/PNG/BMP pipeline remains
in the smallest native group. Enabling one upgrades the pipeline automatically:

```dart
final result = await imageBytes.justImage
    .autoOrient(true)
    .metadataPolicy(MetadataPolicy.safe)
    .preserveIcc(true)
    .encode(OutputFormat.jpeg)
    .run();
```

`MetadataPolicy.none` strips metadata. `safe` retains useful photographic EXIF
while removing GPS, owner/device serials, image identifiers, user comments and
MakerNote. `preserveAll` retains supported EXIF including GPS; the legacy
`preserveMetadata(true)` maps to this policy. EXIF is written to JPEG, PNG,
WebP, TIFF and AVIF. ICC profiles are retained for JPEG, PNG, WebP and TIFF. When
auto-orientation changes pixels, the output orientation tag is cleared.

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

- HEIC/HEIF, GIF, RAW camera formats and animated images are not supported.
- Flutter Web, Fuchsia, Alpine/musl and 32-bit desktop systems are not
  supported.
- Linux binaries target glibc 2.31 or newer; musl-based distributions need a
  future dedicated build.
- Processing is in memory and does not provide streaming/tiled decoding. Input
  buffers are transferred to the worker isolate without a second Dart-heap
  copy and intermediate native buffers are released between operations, but
  large images and high batch concurrency can still require substantial RAM.
- Output animation is not supported; every result is a single raster image.
- XMP preservation and AVIF ICC preservation are not yet guaranteed. SVG is
  rasterized to a single image and its vector structure is not preserved.
- `preserveMetadata(true)` intentionally preserves GPS; use
  `metadataPolicy(MetadataPolicy.safe)` to remove sensitive EXIF fields.
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

Android binaries support 4 KB and 16 KB memory pages. Both local Rust builds
and the release link hook apply 16 KB linker alignment. Release CI checks
LOAD and GNU_RELRO alignment before publication and verifies the final
Flutter release library and APK packaging.

Release automation compiles 12 dynamic and 12 static native libraries,
publishes them as immutable
GitHub Release assets and embeds their SHA-256 hashes in the pub.dev package.
The Native Assets build hook chooses the correct target, verifies the download
and caches it by version. JIT/debug commands load the dynamic library directly;
AOT/release commands send the static library to the link hook so unreachable
native symbols can be removed. Temporary GitHub Actions artifacts are retained
for one day and deleted after publication.

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
