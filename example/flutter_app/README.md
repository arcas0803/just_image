# just_image Flutter example

This is an independent Flutter application that consumes `just_image` through
a normal path dependency. It contains no Gradle, CMake, CocoaPods or Xcode
configuration specific to the library.

```bash
flutter pub get
flutter test
flutter run
```

The demo generates an image in memory, executes a real Rust-backed pipeline in
a background isolate, and displays the resulting PNG.
