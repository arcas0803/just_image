# just_image

High-performance image processing engine for Dart, powered by a Rust FFI backend.

**Zero-copy memory** | **SIMD acceleration** | **Professional metadata preservation**

## Packages

This is a **Melos monorepo** containing three independent packages:

| Package | Description | pub.dev |
|---|---|---|
| [`just_image`](packages/just_image/) | Core engine — Dart API + Rust FFI via Native Assets | [![pub](https://img.shields.io/pub/v/just_image.svg)](https://pub.dev/packages/just_image) |
| [`just_image_cli`](packages/just_image_cli/) | CLI tool — process images from the terminal | [![pub](https://img.shields.io/pub/v/just_image_cli.svg)](https://pub.dev/packages/just_image_cli) |
| [`just_image_flutter`](packages/just_image_flutter/) | Flutter bridge — zero-config plugin for all platforms | [![pub](https://img.shields.io/pub/v/just_image_flutter.svg)](https://pub.dev/packages/just_image_flutter) |

## Features

- **Formats**: AVIF, WebP (lossless/lossy), JPEG, PNG, TIFF, BMP
- **Transforms**: Resize (Lanczos3), Crop, Rotate (free angle + anti-aliasing), Flip
- **Effects**: Gaussian Blur, Unsharp Mask, Sobel edges, HSL adjust, Brightness/Contrast
- **Watermark**: Alpha-composited overlay with position and opacity control
- **Metadata**: EXIF auto-orientation, ICC profile preservation, metadata re-injection
- **Performance**: Rust + rayon parallelism, SIMD (AVX2/NEON)
- **API**: Fluent chainable pipeline, background Isolates, priority batch queue
- **Native Assets**: Rust compiles automatically via `hook/build.dart` — no manual build scripts
- **Pure Dart core**: No Flutter dependency — works in CLI, servers, and any Dart runtime

> **Note**: HEIC format is **not** currently supported. Supported formats are: JPEG, PNG, WebP, AVIF, TIFF, BMP.

## Quick Start

### For Dart projects

```yaml
dependencies:
  just_image: ^1.0.0
```

### For Flutter projects

```yaml
dependencies:
  just_image_flutter: ^1.0.0
```

### CLI

```bash
dart pub global activate just_image_cli
just_image_cli process -i photo.jpg -o result.webp --resize 1920x1080 --format webp --quality 85
just_image_cli info -i photo.jpg
```

## Usage

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

## Prerequisites

- **Dart SDK** >= 3.10.8
- **Rust toolchain** (installed via [rustup](https://rustup.rs/))
- Native Assets experiment enabled: `--enable-experiment=native-assets`

The Rust library is compiled **automatically** by the `hook/build.dart` Native Assets hook when you run `dart run` or `flutter build`. No manual build scripts required.

### Manual Rust build (development)

```bash
cd packages/just_image/src/native
cargo build --release
```

## Development

### Setup

```bash
# Install Melos
dart pub global activate melos

# Bootstrap workspace
melos bootstrap

# Or with dart workspace protocol
dart pub get
```

### Common commands

```bash
# Analyze all packages
melos run analyze

# Run all tests
melos run test

# Build Rust library
melos run build:rust

# Format check
melos run format
```

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Dart (API Layer)                                   │
│  ┌──────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │  Engine   │→ │  Pipeline    │→ │  BatchQueue  │  │
│  └──────────┘  └──────────────┘  └──────────────┘  │
│        │              │                  │           │
│        ▼              ▼                  ▼           │
│  ┌─────────────────────────────────────────────┐    │
│  │  NativeBridge (dart:ffi manual bindings)    │    │
│  │  Isolate.run → calloc → FFI → free          │    │
│  └─────────────────────────────────────────────┘    │
│        │                                            │
│        ▼                                            │
│  ┌─────────────────────────────────────────────┐    │
│  │  hook/build.dart (Native Assets)            │    │
│  │  Auto-compiles Rust on dart run / flutter   │    │
│  └─────────────────────────────────────────────┘    │
├─────────────────────────────────────────────────────┤
│  Rust (Native Core)                                 │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────┐  │
│  │ api.rs   │→ │pipeline  │→ │ transforms.rs    │  │
│  │ (C FFI)  │  │ (config) │  │ effects.rs       │  │
│  └──────────┘  └──────────┘  │ metadata.rs      │  │
│                              │ color.rs (ICC)    │  │
│                              │ formats.rs        │  │
│                              │ watermark.rs      │  │
│                              └──────────────────┘  │
│  rayon (thread pool) + SIMD (AVX2/NEON)            │
└─────────────────────────────────────────────────────┘
```

## Publishing

Each package is published independently to pub.dev:

```bash
cd packages/just_image && dart pub publish
cd packages/just_image_cli && dart pub publish
# just_image_flutter requires Flutter SDK to publish
```

Or tag a release to trigger the CI publish workflow:
```bash
git tag v1.0.0
git push origin v1.0.0
```

## License

MIT
