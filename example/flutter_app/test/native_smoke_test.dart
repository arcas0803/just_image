import 'package:flutter_test/flutter_test.dart';
import 'package:just_image/just_image.dart';
import 'package:just_image_flutter_example/main.dart';

void main() {
  test('independent Flutter app executes the native pipeline', () async {
    final result = await ImagePipeline.bytes(
      createExampleBmp(),
    ).thumbnail(64, 64).encode(OutputFormat.png).run();

    expect(result.width, 64);
    expect(result.height, 36);
    expect(result.data, isNotEmpty);
  });
}
