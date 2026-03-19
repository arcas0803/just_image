/// Zero-config Flutter plugin for just_image.
///
/// This package is a pure FFI bridge: it declares `ffiPlugin: true` for
/// every platform so that Flutter's build system invokes the Native Assets
/// hook in the core `just_image` package. The Rust engine is compiled and
/// bundled into the app binary automatically.
///
/// Import this single package to access the full processing API:
///
/// ```dart
/// import 'package:just_image_flutter/just_image_flutter.dart';
///
/// final result = await ImagePipeline(bytes)
///     .resize(800, 600)
///     .toFormat(ImageFormat.webp)
///     .quality(85)
///     .execute();
/// ```
///
/// No additional platform configuration, build scripts, or native code required.
/// Just have the Rust toolchain installed on the development machine.
library;

export 'package:just_image/just_image.dart';
