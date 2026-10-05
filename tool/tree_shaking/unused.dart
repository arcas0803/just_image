// Copyright (c) 2026 just_image contributors.
// SPDX-License-Identifier: MIT

import 'package:just_image/just_image.dart';

void main() {
  // Referencing a Dart-only type must not retain the native library.
  print(const JpegOutput().format);
}
