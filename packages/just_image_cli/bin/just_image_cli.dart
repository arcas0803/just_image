import 'package:just_image_cli/src/cli_runner.dart';

Future<void> main(List<String> args) async {
  final runner = buildCliRunner();
  await runner.run(args);
}
