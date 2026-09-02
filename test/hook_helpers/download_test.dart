// Copyright (c) 2026 just_image contributors.
// SPDX-License-Identifier: MIT

import 'package:just_image/src/hook_helpers/download.dart';
import 'package:test/test.dart';

void main() {
  group('binaryFileName', () {
    test('selects dynamic artifacts for JIT and debug commands', () {
      expect(
        binaryFileName('macos', 'arm64'),
        'libjust_image_native-macos-arm64.dylib',
      );
      expect(
        binaryFileName('linux', 'x64'),
        'libjust_image_native-linux-x64.so',
      );
      expect(
        binaryFileName('windows', 'x64'),
        'just_image_native-windows-x64.dll',
      );
      expect(
        binaryFileName('android', 'arm'),
        'libjust_image_native-android-arm.so',
      );
    });

    test('selects static artifacts for AOT link hooks', () {
      expect(
        binaryFileName('macos', 'arm64', staticLinking: true),
        'libjust_image_native-macos-arm64.a',
      );
      expect(
        binaryFileName('linux', 'x64', staticLinking: true),
        'libjust_image_native-linux-x64.a',
      );
      expect(
        binaryFileName('windows', 'x64', staticLinking: true),
        'just_image_native-windows-x64.lib',
      );
      expect(
        binaryFileName('android', 'arm', staticLinking: true),
        'libjust_image_native-android-arm.a',
      );
    });

    test('keeps iOS device and simulator artifacts separate', () {
      expect(
        binaryFileName('ios', 'arm64', staticLinking: true),
        'libjust_image_native-ios-arm64.a',
      );
      expect(
        binaryFileName(
          'ios',
          'arm64',
          variant: 'simulator',
          staticLinking: true,
        ),
        'libjust_image_native-ios-simulator-arm64.a',
      );
    });
  });
}
