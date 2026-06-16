/// Zero-config Flutter plugin for just_image.
///
/// **DISCONTINUED**: This package is no longer maintained. The `just_image`
/// core package now works directly in Flutter apps via Native Assets. Depend on
/// `package:just_image` and import `package:just_image/just_image.dart` instead.
///
/// This package was a pure FFI bridge: it declared `ffiPlugin: true` for every
/// platform so that Flutter's build system invoked the Native Assets hook in
/// the core `just_image` package. That behavior is now built into `just_image`
/// itself.
library;

@Deprecated(
  'Use package:just_image directly. just_image_flutter is discontinued.',
)
export 'package:just_image/just_image.dart';
