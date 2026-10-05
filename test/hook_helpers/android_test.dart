import 'package:just_image/src/hook_helpers/android.dart';
import 'package:test/test.dart';

void main() {
  test('preserves user flags and overrides a smaller page size', () {
    final env = {
      'RUSTFLAGS': '-C opt-level=2 -C link-arg=-Wl,-z,max-page-size=4096',
    };
    applyAndroidPageSizeFlags(env);
    final flags = env['CARGO_ENCODED_RUSTFLAGS']!.split('\u001f');
    expect(flags.take(4), [
      '-C',
      'opt-level=2',
      '-C',
      'link-arg=-Wl,-z,max-page-size=4096',
    ]);
    expect(flags.skip(4), [
      '-C',
      'link-arg=-Wl,-z,max-page-size=16384',
      '-C',
      'link-arg=-Wl,-z,common-page-size=16384',
    ]);
    expect(env.containsKey('RUSTFLAGS'), isFalse);
  });
  test('encoded flags take precedence and preserve embedded spaces', () {
    final env = {
      'CARGO_ENCODED_RUSTFLAGS': '-C\u001flink-arg=/a path/file',
      'RUSTFLAGS': '--invalid',
    };
    applyAndroidPageSizeFlags(env);
    expect(env['CARGO_ENCODED_RUSTFLAGS']!.split('\u001f').take(2), [
      '-C',
      'link-arg=/a path/file',
    ]);
    expect(env['CARGO_ENCODED_RUSTFLAGS'], isNot(contains('--invalid')));
  });
}
