import 'package:args/command_runner.dart';
import 'package:just_image_cli/src/cli_runner.dart';
import 'package:test/test.dart';

void main() {
  late CommandRunner<void> runner;

  setUp(() {
    runner = buildCliRunner();
  });

  group('CLI Runner', () {
    test('has process command', () {
      expect(runner.commands.containsKey('process'), isTrue);
    });

    test('has info command', () {
      expect(runner.commands.containsKey('info'), isTrue);
    });

    test('has filters command', () {
      expect(runner.commands.containsKey('filters'), isTrue);
    });

    test('has blurhash command', () {
      expect(runner.commands.containsKey('blurhash'), isTrue);
    });

    test('help does not throw', () async {
      await expectLater(runner.run(['--help']), completes);
    });
  });

  group('Process command', () {
    test('requires --input and --output', () async {
      expect(() => runner.run(['process']), throwsA(isA<ArgumentError>()));
    });
  });

  group('Info command', () {
    test('requires --input', () async {
      expect(() => runner.run(['info']), throwsA(isA<ArgumentError>()));
    });
  });
}
