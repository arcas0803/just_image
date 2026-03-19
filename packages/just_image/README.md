# just_image

High-performance image processing engine for Dart, powered by a Rust FFI backend.

**Zero-copy memory** · **SIMD acceleration** · **Professional metadata preservation**

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

- **Dart SDK** >= 3.10.8
- **Rust toolchain** ([rustup.rs](https://rustup.rs/))
- Native Assets experiment: `--enable-experiment=native-assets`

## Installation

```yaml
dependencies:
  just_image: ^1.0.0
```

> For Flutter apps use [`just_image_flutter`](https://pub.dev/packages/just_image_flutter) instead.

## Usage

### Basic pipeline

```dart
import 'package:just_image/just_image.dart';

final result = await ImagePipeline(imageBytes)
    .resize(1920, 1080)
    .sharpen(1.5)
    .brightness(0.1)
    .toFormat(ImageFormat.avif)
    .quality(85)
    .execute();

File('output.avif').writeAsBytesSync(result.data);
```

### Artistic filters

```dart
// Apply a single filter
final result = await ImagePipeline(bytes)
    .filter('cinematic')
    .toFormat(ImageFormat.jpeg)
    .quality(90)
    .execute();

// List all available filters
final engine = JustImageEngine();
print(engine.availableFilters);
// [vintage, sepia, cool, warm, marine, dramatic, lomo, retro,
//  noir, bloom, polaroid, golden_hour, arctic, cinematic, fade]
```

### Thumbnail generation

```dart
final thumb = await ImagePipeline(bytes)
    .thumbnail(200, 200)
    .toFormat(ImageFormat.webp)
    .execute();
// Aspect ratio is preserved — fits inside the 200×200 box
```

### BlurHash

```dart
final engine = JustImageEngine();

// Encode: image → compact hash string
final hash = await engine.blurHashEncode(imageBytes);
print(hash); // e.g. "LEHV6nWB2yk8pyo0adR*.7kCMdnj"

// Decode: hash string → placeholder PNG
final placeholder = await engine.blurHashDecode(
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
    .flip(FlipDirection.horizontal)
    .blur(2.0)
    .contrast(0.2)
    .hsl(hue: 10, saturation: 0.1, lightness: 0.0)
    .watermark(overlayBytes, x: 50, y: 50, opacity: 0.7)
    .toFormat(ImageFormat.webp)
    .execute();
```

### Batch processing

```dart
final engine = JustImageEngine();

final batch = engine.createBatch(concurrency: 4);

final futures = files.map((f) {
  final pipeline = ImagePipeline(f.readAsBytesSync())
      .resize(800, 600)
      .toFormat(ImageFormat.jpeg);
  return batch.enqueue(pipeline, priority: TaskPriority.normal);
});

final results = await Future.wait(futures);
batch.dispose();
```

## API reference

### ImagePipeline

| Category | Methods |
|---|---|
| **Transform** | `resize(w, h)`, `crop(x, y, w, h)`, `rotate(degrees)`, `flip(direction)`, `thumbnail(maxW, maxH)` |
| **Effects** | `blur(sigma)`, `sharpen(amount, [threshold])`, `sobel()`, `brightness(v)`, `contrast(v)`, `hsl(hue, sat, light)` |
| **Filters** | `filter(name)` — 15 built-in artistic filters |
| **Watermark** | `watermark(bytes, x:, y:, opacity:)` |
| **Output** | `toFormat(format)`, `quality(1-100)` |
| **Config** | `autoOrient(bool)`, `preserveMetadata(bool)`, `preserveIcc(bool)` |
| **Execution** | `execute()` (async, recommended), `executeSync()` (for isolates/CLI) |

### JustImageEngine

| Method | Description |
|---|---|
| `load(bytes)` | Create a pipeline from image bytes |
| `createBatch(concurrency:)` | Create a parallel batch queue |
| `availableFilters` | List of 15 built-in filter names |
| `blurHashEncode(bytes, {componentsX, componentsY})` | Encode image to BlurHash string |
| `blurHashDecode(hash, {width, height})` | Decode BlurHash to placeholder image |
| `dispose()` | Release resources |

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
