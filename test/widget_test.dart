import 'package:flutter_test/flutter_test.dart';
import 'package:securechat/main.dart';

void main() {
  testWidgets('launch screen is visible when Supabase is not configured', (WidgetTester tester) async {
    await tester.pumpWidget(const SecureChatApp());

    expect(find.text('SecureChat'), findsOneWidget);
    expect(find.text('Giriş yap'), findsOneWidget);
    expect(find.text('Hesap oluştur'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('registration form opens from launch screen', (WidgetTester tester) async {
    await tester.pumpWidget(const SecureChatApp());
    final registerButton = find.text('Hesap oluştur');
    await tester.ensureVisible(registerButton);
    await tester.pumpAndSettle();
    await tester.tap(registerButton);
    await tester.pumpAndSettle();

    expect(find.text('Yeni hesap oluştur'), findsOneWidget);
    expect(find.text('Kullanıcı adı'), findsOneWidget);
    expect(find.text('E-posta'), findsOneWidget);
    expect(find.text('Şifre'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
