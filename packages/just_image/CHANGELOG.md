## 1.0.4

- Migrated Native Assets build hook to `package:hooks` + `package:code_assets`.
- Fixed iOS simulator compilation: correct `aarch64-apple-ios-sim` / `x86_64-apple-ios-sim` target triple selection.
- iOS architecture now respects `targetArchitecture` instead of defaulting to `arm64`.
- Linker wrapper now uses the compiler driver (`clang`) so Apple SDK flags are parsed correctly.

## 1.0.3

- Core package is now the single entry point for both Dart and Flutter apps.
- Documented direct Flutter usage; no wrapper plugin is required anymore.
- `just_image_cli` and `just_image_flutter` are discontinued — depend on `just_image` directly.

## 1.0.2

- Android: auto-install missing Rust targets via `rustup target add` during build.
- Android: auto-detect Android NDK location from `ANDROID_NDK_HOME`, `ANDROID_NDK_ROOT`, `ANDROID_HOME/ndk/`, or platform defaults — no manual configuration required.
- Android: configure Cargo linkers for `aarch64-linux-android`, `armv7-linux-androideabi`, and `x86_64-linux-android` automatically.
- Android: API level is configurable via `ANDROID_MIN_SDK_VERSION` env var (default: `21`).
- Android: fallback from `darwin-arm64` to `darwin-x86_64` prebuilt toolchain for NDK < 23 on Apple Silicon.

## 1.0.1

- 15 artistic filters: vintage, sepia, cool, warm, marine, dramatic, lomo, retro, noir, bloom, polaroid, golden_hour, arctic, cinematic, fade.
- Thumbnail generation preserving aspect ratio.
- BlurHash encode and decode support.
- `ImagePipeline.filter()` and `ImagePipeline.thumbnail()` chainable methods.
- `JustImageEngine.blurHashEncode()`, `blurHashDecode()`, and `availableFilters`.

## 1.0.0

- Initial release as standalone package in monorepo.
- High-performance Rust FFI engine with Native Assets build hook.
- Fluent pipeline API for transforms, effects, and format conversions.
- Batch processing queue with priority support.
- Custom exception hierarchy.
