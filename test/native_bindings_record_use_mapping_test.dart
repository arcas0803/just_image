// Copyright (c) 2026 just_image contributors.
// SPDX-License-Identifier: MIT

import 'package:just_image/src/native_bindings.record_use_mapping.g.dart';
import 'package:test/test.dart';

void main() {
  test('record-use mapping covers every public FFI entry point', () {
    expect(recordUseMapping, {
      'rust_abi_version': 'rust_abi_version',
      'rust_available_filters': 'rust_available_filters',
      'rust_blurhash_decode': 'rust_blurhash_decode',
      'rust_blurhash_encode': 'rust_blurhash_encode',
      'rust_free_buffer': 'rust_free_buffer',
      'rust_free_error': 'rust_free_error',
      'rust_free_string': 'rust_free_string',
      'rust_image_info': 'rust_image_info',
      'rust_process_core_pipeline': 'rust_process_core_pipeline',
      'rust_process_extended_pipeline': 'rust_process_extended_pipeline',
      'rust_process_pipeline': 'rust_process_pipeline',
      'rust_version': 'rust_version',
    });
  });
}
