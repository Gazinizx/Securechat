import 'package:flutter_test/flutter_test.dart';
import 'package:securechat/main.dart';

void main() {
  testWidgets('SecureChat inbox renders', (WidgetTester tester) async {
    await tester.pumpWidget(const SecureChatApp());
    expect(find.text('SecureChat'), findsOneWidget);
    expect(find.text('Henüz sohbet yok'), findsOneWidget);
  });
}
