import 'package:flutter_test/flutter_test.dart';
import 'package:securechat/main.dart';

void main() {
  testWidgets('launch screen shows SecureChat login and no public registration',
      (WidgetTester tester) async {
    await tester.pumpWidget(const SecureChatApp());

    expect(find.text('SecureChat'), findsOneWidget);
    expect(find.text('Giriş yap'), findsOneWidget);
    expect(find.text('Hesap oluştur'), findsNothing);
    expect(find.text('E-posta'), findsNothing);
    expect(find.text('Şifre'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
