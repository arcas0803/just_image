import 'package:flutter_test/flutter_test.dart';
import 'package:just_image_flutter_example/main.dart';

void main() {
  testWidgets('App renders smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const JustImageExampleApp());
    expect(find.text('just_image Demo'), findsOneWidget);
  });
}
