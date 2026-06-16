# just_image_flutter_example

Example Flutter app demonstrating `just_image` direct integration.

> This example previously depended on the `just_image_flutter` wrapper, which is
> now discontinued. It uses `package:just_image` directly.

## Run

```bash
flutter run --enable-experiment=native-assets
```

For Android builds, make sure the Android NDK is available and the required
Rust targets are installed:

```bash
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
```
