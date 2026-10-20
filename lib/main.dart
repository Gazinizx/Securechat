import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  if (url.isNotEmpty && anonKey.isNotEmpty) {
    await Supabase.initialize(url: url, anonKey: anonKey);
  }
  runApp(const SecureChatApp());
}

class SecureChatApp extends StatelessWidget {
  const SecureChatApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SecureChat',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF09090F),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF9A7BFF), brightness: Brightness.dark),
      useMaterial3: true,
    ),
    home: const InboxScreen(),
  );
}

class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('SecureChat', style: TextStyle(fontWeight: FontWeight.w700)),
      actions: [
        IconButton(tooltip: 'Hayalet Mod', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GhostModeScreen())), icon: const Icon(Icons.visibility_off_outlined)),
        IconButton(tooltip: 'Ayarlar', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())), icon: const Icon(Icons.settings_outlined)),
      ]),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      TextField(decoration: InputDecoration(hintText: 'Kişi veya sohbet ara', prefixIcon: const Icon(Icons.search), filled: true, fillColor: const Color(0xFF151520), border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none))),
      const SizedBox(height: 24),
      const Text('MESAJLAR', style: TextStyle(letterSpacing: 1.5, color: Colors.white54, fontSize: 12)),
      const SizedBox(height: 10),
      const _EmptyState(),
      const SizedBox(height: 20),
      const Text('Gizlilik odaklı mesajlaşma', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      const Text('Bu sürüm arayüz ve proje altyapısı başlangıcıdır; üretim mesajlaşması ve şifreleme henüz bağlı değildir.', style: TextStyle(color: Colors.white60, height: 1.5)),
    ]),
    floatingActionButton: FloatingActionButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewChatScreen())), child: const Icon(Icons.edit_outlined)),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 18),
    decoration: BoxDecoration(color: const Color(0xFF151520), borderRadius: BorderRadius.circular(24)),
    child: const Column(children: [Icon(Icons.forum_outlined, size: 42, color: Color(0xFFB9A5FF)), SizedBox(height: 12), Text('Henüz sohbet yok', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)), SizedBox(height: 5), Text('Yeni bir sohbet başlattığında burada görünecek.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54))]),
  );
}

class NewChatScreen extends StatelessWidget {
  const NewChatScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Yeni sohbet')), body: const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Kişi arama ve mesaj gönderimi, kimlik doğrulama ve güvenli mesaj altyapısı tamamlandığında etkinleştirilecek.', textAlign: TextAlign.center))));
}

class GhostModeScreen extends StatefulWidget {
  const GhostModeScreen({super.key});
  @override
  State<GhostModeScreen> createState() => _GhostModeScreenState();
}
class _GhostModeScreenState extends State<GhostModeScreen> {
  bool enabled = false;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Hayalet Mod')), body: ListView(padding: const EdgeInsets.all(20), children: [
    const Icon(Icons.visibility_off_outlined, size: 54, color: Color(0xFFB9A5FF)),
    const SizedBox(height: 16),
    SwitchListTile(value: enabled, onChanged: (v) => setState(() => enabled = v), title: const Text('Hayalet Mod'), subtitle: const Text('Arayüz prototipi: gerçek mesaj silme ve iki cihaz senkronizasyonu henüz bağlı değil.')),
    const Divider(height: 32),
    const Text('Kural: Okunmamış mesajlar korunur. Okunan mesajlar sohbetten çıkıldığında doğrulanmış iki cihazlı silme protokolüyle temizlenmelidir.', style: TextStyle(color: Colors.white70, height: 1.5)),
  ]));
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Ayarlar')), body: const ListView(children: [
    ListTile(leading: Icon(Icons.lock_outline), title: Text('Güvenlik'), subtitle: Text('Anahtar doğrulama ve cihaz güvenliği')),
    ListTile(leading: Icon(Icons.notifications_none), title: Text('Bildirimler'), subtitle: Text('Mesaj önizlemelerini gizle')),
    ListTile(leading: Icon(Icons.privacy_tip_outlined), title: Text('Gizlilik'), subtitle: Text('Hayalet Mod ve yerel veri temizliği')),
  ]));
}
