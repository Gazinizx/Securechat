import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/profile_service.dart';
import 'chat_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _username = TextEditingController();
  final _search = TextEditingController();
  String? _notice;
  bool _busy = false;

  Future<void> _save() async {
    setState(() { _busy = true; _notice = null; });
    try {
      await ProfileService.saveUsername(_username.text);
      setState(() => _notice = 'Kullanıcı adın kaydedildi.');
    } catch (e) { setState(() => _notice = e.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _find() async {
    setState(() { _busy = true; _notice = null; });
    try {
      final found = await ProfileService.findByUsername(_search.text);
      if (!mounted) return;
      if (found == null) { setState(() => _notice = 'Kullanıcı bulunamadı.'); return; }
      final uid = found['uid'] as String;
      if (uid == FirebaseAuth.instance.currentUser?.uid) {
        setState(() => _notice = 'Kendi kullanıcı adını aradın.');
        return;
      }
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatScreen(peerUid: uid, peerUsername: found['username'] as String),
      ));
    } catch (e) { setState(() => _notice = e.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  void dispose() { _username.dispose(); _search.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('SecureChat'), actions: [
      IconButton(tooltip: 'Çıkış yap', onPressed: () => FirebaseAuth.instance.signOut(), icon: const Icon(Icons.logout)),
    ]),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      const Text('Kişiler', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('Kullanıcı adıyla kişi bul ve sohbet başlat.'),
      const SizedBox(height: 14),
      TextField(controller: _search, decoration: InputDecoration(labelText: 'Kullanıcı adı', prefixIcon: const Icon(Icons.search), suffixIcon: IconButton(onPressed: _busy ? null : _find, icon: const Icon(Icons.arrow_forward)), border: const OutlineInputBorder()), onSubmitted: (_) => _find()),
      const SizedBox(height: 28),
      const Divider(),
      const Text('Kullanıcı adım', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),
      TextField(controller: _username, autocorrect: false, decoration: const InputDecoration(hintText: 'ör. gazi_07', border: OutlineInputBorder())),
      const SizedBox(height: 10),
      FilledButton(onPressed: _busy ? null : _save, child: const Text('Kullanıcı adını kaydet')),
      if (_notice != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_notice!)),
      const SizedBox(height: 24),
      const Card(child: Padding(padding: EdgeInsets.all(16), child: Row(children: [
        Icon(Icons.lock_outline, color: Color(0xFF69E6B1), size: 30),
        SizedBox(width: 12),
        Expanded(child: Text('Mesaj şifreleme altyapısı ekleniyor. Üretim sürümünden önce anahtar doğrulama ve bağımsız güvenlik denetimi gerekir.')),
      ]))),
    ]),
  );
}
