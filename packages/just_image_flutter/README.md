# just_image_flutter

Zero-config Flutter plugin for [`just_image`](https://pub.dev/packages/just_image) —
bridges the Rust-powered image processing engine to Flutter apps via
[Native Assets](https://dart.dev/interop/c-interop#native-assets).

**This package contains no widgets or UI code.** It exists solely to declare
`ffiPlugin: true` for all platforms, which tells Flutter's build system to
invoke the `hook/build.dart` in `just_image` and bundle the compiled Rust
library into your app binary.

## Installation

```yaml
dependencies:
  just_image_flutter: ^1.0.0
```

That's it. No platform-specific setup, no CMakeLists.txt, no Podspec, no
Gradle changes.

## Prerequisites

- **Flutter** >= 3.22.0 (Dart SDK >= 3.10.8)
- **Rust toolchain** installed ([rustup.rs](https://rustup.rs/))
- Native Assets experiment flag when building:
  ```bash
  flutter run --enable-experiment=native-assets
  flutter build apk --enable-experiment=native-assets
  ```

### Platform-specific Rust targets

For **Android**:
```bash
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
```

For **iOS**:
```bash
rustup target add aarch64-apple-ios x86_64-apple-ios
```

For **macOS**, **Linux**, and **Windows** the default host target is sufficient.

## Usage

Import the package — the full `just_image` API is re-exported:

```dart
import 'package:just_image_flutter/just_image_flutter.dart';

final result = await ImagePipeline(imageBytes)
    .resize(1920, 1080)
    .sharpen(1.5)
    .toFormat(ImageFormat.avif)
    .quality(85)
    .execute();

File('output.avif').writeAsBytesSync(result.data);
```

## How it works

```
┌──────────────────────────────────────────────┐
│  Your Flutter App                            │
│                                              │
│  ┌────────────────────────────────────────┐  │
│  │ just_image_flutter                     │  │
│  │  ffiPlugin: true (all platforms)       │  │
│  │  export just_image API                 │  │
│  └───────────────┬────────────────────────┘  │
│                  │ depends on                 │
│  ┌───────────────▼────────────────────────┐  │
│  │ just_image (core)                      │  │
│  │  ImagePipeline → NativeBridge (FFI)    │  │
│  │  hook/build.dart (Native Assets)       │  │
│  └───────────────┬────────────────────────┘  │
│                  │ compiles automatically     │
│  ┌───────────────▼────────────────────────┐  │
│  │ Rust native library                    │  │
│  │  image codecs, transforms, SIMD        │  │
│  └────────────────────────────────────────┘  │
└──────────────────────────────────────────────┘
```

1. `ffiPlugin: true` tells Flutter to look for Native Assets hooks in dependencies
2. `hook/build.dart` in `just_image` detects the target OS and architecture
3. Cargo cross-compiles the Rust crate for the target
4. Flutter bundles the `.so` / `.dylib` / `.dll` into the app binary
5. `dart:ffi` `DynamicLibrary.open()` loads it at runtime

## Platform support

| Platform | Architectures | Notes |
|---|---|---|
| Android | arm64, arm, x64 | Requires NDK + Rust targets |
| iOS | arm64, x64 | Simulator via x64 |
| macOS | arm64, x64 | — |
| Linux | x64, arm64 | — |
| Windows | x64, arm64 | MSVC toolchain required |

## License

See [LICENSE](LICENSE).
