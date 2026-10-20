import 'package:flutter_test/flutter_test.dart';
import 'package:securechat/main.dart';

void main() {
  testWidgets('SecureChat renders setup guidance without Supabase configuration', (WidgetTester tester) async {
    await tester.pumpWidget(const SecureChatApp());
    expect(find.textContaining('SUPABASE_URL'), findsOneWidget);
  });
}
