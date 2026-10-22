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
    try {
      final result = await client.functions.invoke('securechat-admin-users', body: {'action': 'list'});
      if (result.status != 200) throw Exception('Yönetici yetkisi doğrulanamadı.');
      users = (result.data as Map)['users'] as List? ?? [];
      error = null;
    } catch (e) { error = e.toString(); }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Yönetici — Hesaplar'), actions: [
      IconButton(onPressed: () => showDialog<void>(context: context, builder: (context) {
        final username = TextEditingController();
        final password = TextEditingController();
        return AlertDialog(title: const Text('Hesap oluştur'), content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: username, decoration: const InputDecoration(labelText: 'Kullanıcı adı')),
          TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Şifre (en az 10 karakter)')),
        ]), actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
          FilledButton(onPressed: () async {
            try {
              final r = await client.functions.invoke('securechat-admin-users', body: {'action': 'create', 'username': username.text.trim().toLowerCase(), 'password': password.text});
              if (r.status != 200) throw Exception((r.data as Map?)?['error'] ?? 'İşlem başarısız.');
              if (context.mounted) Navigator.pop(context);
              await load();
            } catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
          }, child: const Text('Oluştur')),
        ]);
      }), icon: const Icon(Icons.person_add_alt_1)),
      IconButton(onPressed: load, icon: const Icon(Icons.refresh)),
    ]),
    body: busy ? const Center(child: CircularProgressIndicator()) : error != null
      ? Center(child: Text(error!))
      : ListView(children: [for (final user in users) ListTile(
          leading: const Icon(Icons.person_outline),
          title: Text((user as Map)['username']?.toString() ?? 'Kullanıcı'),
        )]),
  );
}
