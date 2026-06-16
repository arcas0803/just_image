# just_image

High-performance image processing engine for Dart and Flutter, powered by a Rust FFI backend.

**Zero-copy memory** · **SIMD acceleration** · **Professional metadata preservation**

> This single package now powers both Dart CLI/servers **and** Flutter apps. The former
> wrapper packages `just_image_cli` and `just_image_flutter` are discontinued; depend on
> `just_image` directly instead.

## Features

- **Formats**: AVIF, WebP (lossless/lossy), JPEG, PNG, TIFF, BMP
- **Transforms**: Resize (Lanczos3), Crop, Rotate (free-angle), Flip, Thumbnail
- **Effects**: Gaussian Blur, Unsharp Mask, Sobel edges, HSL adjust, Brightness/Contrast
- **15 Artistic Filters**: vintage, sepia, cool, warm, marine, dramatic, lomo, retro, noir, bloom, polaroid, golden_hour, arctic, cinematic, fade
- **BlurHash**: Encode images to compact placeholder strings and decode them back
- **Watermark**: Alpha-composited overlay with position and opacity control
- **Metadata**: EXIF auto-orientation, ICC profile preservation, metadata re-injection
- **Performance**: Rust + rayon parallelism, SIMD (AVX2 / NEON)
- **API**: Fluent chainable pipeline, background Isolates, priority batch queue
- **Native Assets**: Rust compiles automatically via `hook/build.dart` — no manual scripts

> **Note**: HEIC is **not** supported. Supported formats: JPEG, PNG, WebP, AVIF, TIFF, BMP.

## Prerequisites

- **Dart SDK** >= 3.10.8 (Flutter >= 3.22.0)
- **Rust toolchain** ([rustup.rs](https://rustup.rs/))
- Native Assets experiment: `--enable-experiment=native-assets`

## Installation

```yaml
dependencies:
  just_image: ^1.0.3
```

The same dependency works for **Dart CLI/servers**, **Flutter apps**, and any other Dart
runtime that supports Native Assets. The Rust library is compiled automatically by the
`hook/build.dart` hook; no platform-specific setup is required.

## Usage

### Flutter apps

Import `just_image` directly — no wrapper plugin is needed:

```dart
import 'package:just_image/just_image.dart';

final result = await ImagePipeline(imageBytes)
    .resize(800, 600)
    .encode(const WebpOutput(quality: 85))
    .run();
```

Build as usual with Native Assets enabled:

```bash
flutter run --enable-experiment=native-assets
flutter build apk --enable-experiment=native-assets
```

### Dart apps / CLI / servers

```dart
import 'package:just_image/just_image.dart';

final result = await ImagePipeline(imageBytes)
    .resize(1920, 1080)
    .sharpen(1.5)
    .brightness(0.1)
    .encode(const AvifOutput(quality: 85))
    .run();

File('output.avif').writeAsBytesSync(result.data);
```

Run with:

```bash
dart --enable-experiment=native-assets run bin/main.dart
```

### Artistic filters

```dart
// Apply a single filter
final result = await ImagePipeline(bytes)
    .filter(ArtisticFilterName.cinematic)
    .encode(const JpegOutput(quality: 90))
    .run();

// List all available filters
print(ArtisticFilterName.values.map((f) => f.jsonName));
// (vintage, sepia, cool, warm, marine, dramatic, lomo, retro,
//  noir, bloom, polaroid, golden_hour, arctic, cinematic, fade)
```

### Thumbnail generation

```dart
final thumb = await ImagePipeline(bytes)
    .thumbnail(200, 200)
    .encode(const WebpOutput(quality: 85))
    .run();
// Aspect ratio is preserved — fits inside the 200×200 box
```

### BlurHash

```dart
// Encode: image → compact hash string
final hash = await JustImage.blurHashEncode(BytesSource(imageBytes));
print(hash); // e.g. "LEHV6nWB2yk8pyo0adR*.7kCMdnj"

// Decode: hash string → placeholder PNG
final placeholder = await JustImage.blurHashDecode(
  hash,
  width: 32,
  height: 32,
);
File('placeholder.png').writeAsBytesSync(placeholder.data);
```

### Transform & effects

```dart
final result = await ImagePipeline(bytes)
    .crop(100, 100, 800, 600)
    .rotate(90)
    .flipHorizontal()
    .blur(2.0)
    .contrast(0.2)
    .hsl(hue: 10, saturation: 0.1, lightness: 0.0)
    .watermark(BytesSource(overlayBytes), x: 50, y: 50, opacity: 0.7)
    .encode(const WebpOutput(quality: 85))
    .run();
```

### Batch processing

```dart
final pipelines = files.map((f) {
  return ImagePipeline.file(f)
      .resize(800, 600)
      .encode(const JpegOutput());
}).toList();

final results = await JustImage.processBatch(pipelines, concurrency: 4);
```

## API reference

### ImagePipeline

| Category | Methods |
|---|---|
| **Transform** | `resize(w, h)`, `crop(x, y, w, h)`, `rotate(degrees)`, `flipHorizontal()`, `flipVertical()`, `thumbnail(maxW, maxH)` |
| **Effects** | `blur(sigma)`, `sharpen(amount, [threshold])`, `sobel()`, `brightness(v)`, `contrast(v)`, `hsl(hue, sat, light)` |
| **Filters** | `filter(ArtisticFilterName)` — 15 built-in artistic filters |
| **Watermark** | `watermark(source, x:, y:, opacity:)` |
| **Output** | `encode(OutputConfig)` |
| **Config** | `autoOrient(bool)`, `preserveMetadata(bool)`, `preserveIcc(bool)` |
| **Execution** | `run()` (async, recommended), `runSync()` (for isolates/CLI) |

### JustImage

| Method | Description |
|---|---|
| `process(source, {width, height, output})` | One-shot resize + encode |
| `processBatch(pipelines, {concurrency})` | Process pipelines in parallel |
| `blurHashEncode(source, {componentsX, componentsY})` | Encode image to BlurHash string |
| `blurHashDecode(hash, {width, height})` | Decode BlurHash to placeholder image |
| `info(source)` | Read image width/height metadata |

### Exception hierarchy

All exceptions extend `JustImageException`:

| Exception | When |
|---|---|
| `ImageDecodeException` | Invalid or unsupported input |
| `ImageEncodeException` | Encoding to target format failed |
| `PipelineExecutionException` | Transform/effect operation failed |
| `NativeLibraryException` | Rust library could not be loaded |
| `UnsupportedPlatformException` | Running on an unsupported OS |
| `BatchQueueDisposedException` | Operating on a disposed queue |
| `TaskCancelledException` | Queued task was cancelled |
| `EmptyInputException` | Empty input bytes |

## Platform support

| Platform | Architecture |
|---|---|
| macOS | arm64, x64 |
| Linux | x64, arm64 |
| Windows | x64, arm64 |
| Android | arm64, arm, x64 |
| iOS | arm64, x64 |

## How Native Assets work

The `hook/build.dart` file is invoked automatically by the Dart/Flutter build system.
It runs `cargo build --release` targeting the correct platform/architecture and
registers the compiled dynamic library as a code asset. No manual build step required.

```bash
# Run with Native Assets enabled
dart --enable-experiment=native-assets run bin/main.dart
```

## License

See [LICENSE](LICENSE).
