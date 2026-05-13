## 1.0.2

- Updated dependency to `just_image ^1.0.2`.
- Android: zero-config NDK detection and Rust target auto-install — no setup required by the developer to build for Android.

## 1.0.1

- Re-exports new `just_image` 1.0.1 features: artistic filters, thumbnails, and BlurHash.

## 1.0.0

- Initial release.
- Zero-config Flutter plugin bridge for `just_image`.
- Declares `ffiPlugin: true` for Android, iOS, macOS, Linux, and Windows.
- Re-exports the full `just_image` API (pipeline, batch queue, engine, exceptions).
- Rust native library compiled and bundled automatically via Native Assets.
