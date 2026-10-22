import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});
  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final client = Supabase.instance.client;
  List<dynamic> users = [];
  String? error;
  bool busy = true;

  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    if (mounted) setState(() => busy = true);
    try {
      final result = await client.functions.invoke('securechat-admin-users', body: {'action': 'list'});
      if (result.status != 200) throw Exception((result.data as Map?)?['error'] ?? 'Yönetici yetkisi doğrulanamadı.');
      users = (result.data as Map)['users'] as List? ?? [];
      error = null;
    } catch (e) { error = e.toString(); }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _createUser() async {
    final username = TextEditingController();
    final password = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Hesap oluştur'),
      content: Form(key: formKey, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: username, autocorrect: false, decoration: const InputDecoration(labelText: 'Kullanıcı adı'), validator: (v) => RegExp(r'^[a-zA-Z0-9_]{3,32}$').hasMatch((v ?? '').trim()) ? null : '3-32 karakter; harf, rakam veya _ kullan.'),
        TextFormField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Şifre (en az 10 karakter)'), validator: (v) => (v ?? '').length >= 10 ? null : 'Şifre en az 10 karakter olmalı.'),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('İptal')),
        FilledButton(onPressed: () { if (formKey.currentState!.validate()) Navigator.pop(dialogContext, true); }, child: const Text('Oluştur')),
      ],
    ));
    if (result != true) { username.dispose(); password.dispose(); return; }
    try {
      final r = await client.functions.invoke('securechat-admin-users', body: {'action': 'create', 'username': username.text.trim().toLowerCase(), 'password': password.text});
      if (r.status != 200) throw Exception((r.data as Map?)?['error'] ?? 'Hesap oluşturulamadı.');
      _message('Hesap oluşturuldu.');
      await load();
    } catch (e) { _message('Hata: $e'); }
    finally { username.dispose(); password.dispose(); }
  }

  Future<void> _changePassword(Map user) async {
    final password = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: Text('${user['username']} — şifre değiştir'),
      content: Form(key: formKey, child: TextFormField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Yeni şifre (en az 10 karakter)'), validator: (v) => (v ?? '').length >= 10 ? null : 'Şifre en az 10 karakter olmalı.')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('İptal')),
        FilledButton(onPressed: () { if (formKey.currentState!.validate()) Navigator.pop(dialogContext, true); }, child: const Text('Kaydet')),
      ],
    ));
    if (result != true) { password.dispose(); return; }
    try {
      final r = await client.functions.invoke('securechat-admin-users', body: {'action': 'change_password', 'user_id': user['id'], 'password': password.text});
      if (r.status != 200) throw Exception((r.data as Map?)?['error'] ?? 'Şifre değiştirilemedi.');
      _message('Şifre güncellendi.');
    } catch (e) { _message('Hata: $e'); }
    finally { password.dispose(); }
  }

  Future<void> _deleteUser(Map user) async {
    final yes = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Hesap silinsin mi?'),
      content: Text('${user['username']} hesabı ve hesabın kimlik doğrulama kaydı silinecek. Bu işlem geri alınamaz.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Hesabı sil')),
      ],
    ));
    if (yes != true) return;
    try {
      final r = await client.functions.invoke('securechat-admin-users', body: {'action': 'delete', 'user_id': user['id']});
      if (r.status != 200) throw Exception((r.data as Map?)?['error'] ?? 'Hesap silinemedi.');
      _message('Hesap silindi.');
      await load();
    } catch (e) { _message('Hata: $e'); }
  }

  void _message(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Yönetici — Hesaplar'), actions: [
      IconButton(onPressed: _createUser, icon: const Icon(Icons.person_add_alt_1), tooltip: 'Hesap oluştur'),
      IconButton(onPressed: load, icon: const Icon(Icons.refresh), tooltip: 'Yenile'),
    ]),
    body: busy ? const Center(child: CircularProgressIndicator()) : error != null
      ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: load, child: const Text('Tekrar dene')),
        ]))
      : users.isEmpty ? const Center(child: Text('Henüz kullanıcı yok.'))
      : ListView(children: [for (final item in users) Builder(builder: (context) {
          final user = Map<String, dynamic>.from(item as Map);
          return ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(user['username']?.toString() ?? 'Kullanıcı'),
            subtitle: Text(user['id']?.toString() ?? ''),
            trailing: PopupMenuButton<String>(
              tooltip: 'Hesap işlemleri',
              onSelected: (action) {
                if (action == 'password') _changePassword(user);
                if (action == 'delete') _deleteUser(user);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'password', child: Text('Şifre değiştir')),
                PopupMenuItem(value: 'delete', child: Text('Hesabı sil')),
              ],
            ),
          );
        })]),
  );
}
