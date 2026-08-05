## 2.0.0

### Breaking changes

- **Native Assets ABI**: FFI bindings are generated from a versioned C header and resolved using `@Native`; runtime loading no longer depends on the working directory.
- **`OutputFormat` enum**: New `OutputFormat` enum (`jpeg`, `png`, `webp`, `tiff`, `bmp`) replaces the need for `OutputConfig` subclasses in most cases. Use `pipeline.encode(OutputFormat.webp, quality: 85)`.
- **AVIF removed**: AVIF input and output are not supported in 2.0.0. `OutputFormat.avif`, `ImageFormat.avif` and `AvifOutput` have been removed together with the native codec dependencies.
- **`ImageResult.format`**: Changed from `String` to the new `ImageFormat` enum.
- **Removed `ImagePipeline.runSync()`**: Use `run()` exclusively — it already runs in a background `Isolate`.
- **`JustImage.processBatch`** now returns `BatchResult` instead of `List<ImageResult>`. `BatchResult` captures both successes and failures, allowing partial success handling.
- **Removed private pipeline subclasses** (`_BytesImagePipeline`, `_FileImagePipeline`, `_XFileImagePipeline`). Use named constructors `ImagePipeline.bytes()`, `.file()`, `.xfile()` directly.
- Requires Dart 3.10.8 and Flutter 3.38 or newer.
- Bumped package version to 2.0.0.

### New features

- **Zero-configuration native delivery**: released packages always download the correct SHA-256-verified binary, regardless of whether Cargo is installed.
- **Versioned binary cache** with atomic downloads, timeouts and retries.
- **Independent examples** for Dart CLI and Flutter desktop/mobile projects.
- **Debug build profile**: Set `debug_build: true` in `hooks.user_defines` for faster dev builds (uses `cargo build --profile dev` instead of `--release`).
- **`BatchResult`**: New result type for batch processing with `successCount`, `failureCount`, `allSucceeded`, and `successful` getters.
- **`OutputConfig.from(OutputFormat, quality?)`**: Factory to create `OutputConfig` from enum.
- **Generated `@Native` bindings** with an explicit ABI version check.

### Bug fixes

- **iOS device linking**: Fixed `___chkstk_darwin` symbol not found by ensuring deployment target is respected.
- **ICC profile injection**: `preserve_icc` now works independently of `preserve_metadata` for JPEG output.
- **PNG signature check**: Full 8-byte PNG magic number check instead of partial 4-byte.
- **WebP encoding**: Added empty-output check to detect silent encoding failures.
- **`processBatch` error handling**: Individual pipeline failures no longer abort the entire batch.
- **Public argument validation**: dimensions, quality, effects, BlurHash and concurrency fail before crossing FFI.
- **Panic containment**: Rust panics are converted to native errors instead of unwinding through `extern "C"`.
- **`_Semaphore`**: Prevented count from going negative on excess `release()` calls.
- **`utf8.decode`**: Replaced `String.fromCharCodes` with `utf8.decode` for BlurHash and image info JSON parsing.
- **Sobel edge detection**: Uses a flat source buffer and safely handles images smaller than its 3×3 kernel.
- **`CARGO_TARGET_DIR`**: Build hook now respects `CARGO_TARGET_DIR` environment variable.
- **Android NDK**: Only configures the current target's toolchain instead of all targets.
- **`rust_free_result`**: Marked `#[allow(dead_code)]`.
- **xcrun errors**: `xcrun` failures now log stderr instead of silently swallowing.

### Testing and CI

- Added real Dart-to-Rust integration tests for every output format, transforms, watermark, BlurHash and partial batch failures.
- Added Rust unit tests for formats and native validation.
- Added a 12-target native release workflow with one-day temporary artifact retention and automatic cleanup for GitHub Free.
- Creating a version tag now builds and publishes every native binary, generates and validates SHA-256 hashes, tests the zero-configuration package and publishes to pub.dev without a manual preparation step.

## 1.0.8

- Fixed Android cross-compilation on macOS: use the versioned NDK clang script (e.g. `aarch64-linux-android29-clang`) as the Cargo linker instead of the generic `clang` binary. The versioned script has the correct `--target` baked in and routes to the NDK's own `ld.lld`, avoiding both the `ld64.lld` (Mach-O) and the untargeted-clang macOS-flags issues that caused linker failures in v1.0.7.

## 1.0.7

- Fixed Android cross-compilation on macOS: NDK `clang` now uses `lld` (ELF linker) instead of `ld64.lld` (Mach-O linker) via a wrapper script that passes `-fuse-ld=lld`. This resolves linker errors (`unknown argument '--version-script'`, `--as-needed`, `-Bstatic`, etc.) when building for `aarch64-linux-android` and other Android targets.
- Removed unused `logging` dependency from `pubspec.yaml`.

## 1.0.6

- Flattened repository: removed the Dart workspace and moved the package to the repository root.
- Fixed Android build on macOS: use lowercase target names for `cc` crate environment variables (`CC_aarch64_linux_android`, etc.).
- Prefer the `CCompilerConfig` provided by Native Assets for Android; fall back to manual NDK detection only when absent.

## 1.0.5

- Fixed Android NDK compiler detection: fall back from the requested API level to the unversioned `*-clang` symlink, then to the highest available API-level compiler.
- Removed discontinued `just_image_cli` and `just_image_flutter` packages from the repository.

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
