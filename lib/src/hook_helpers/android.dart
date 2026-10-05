// Copyright (c) 2026 just_image contributors.
// SPDX-License-Identifier: MIT

/// Both flags are required for LOAD and GNU_RELRO alignment on older NDKs.
const androidPageSizeLinkerFlags = <String>[
  '-Wl,-z,max-page-size=16384',
  '-Wl,-z,common-page-size=16384',
];

/// Cargo gives encoded flags precedence over RUSTFLAGS. Preserve that behavior
/// and append the required alignment flags so earlier options cannot override
/// the Android page size. Encoded arguments also preserve embedded spaces.
void applyAndroidPageSizeFlags(Map<String, String> environment) {
  final encoded = environment['CARGO_ENCODED_RUSTFLAGS'];
  final flags = encoded != null
      ? encoded.split('\u001f')
      : (environment['RUSTFLAGS'] ?? '').split(RegExp(r'\s+'));
  environment['CARGO_ENCODED_RUSTFLAGS'] = [
    ...flags.where((flag) => flag.isNotEmpty),
    for (final flag in androidPageSizeLinkerFlags) ...['-C', 'link-arg=$flag'],
  ].join('\u001f');
  environment.remove('RUSTFLAGS');
}
