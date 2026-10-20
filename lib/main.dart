import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _storage = FlutterSecureStorage();
final _cipher = AesGcm.with256bits();
final _client = Supabase.instance.client;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_ANON_KEY');
  if (url.isNotEmpty && key.isNotEmpty) {
    await Supabase.initialize(url: url, anonKey: key);
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
    home: Supabase.instance.isInitialized ? const AuthGate() : const SetupScreen(),
  );
}

class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: Padding(padding: EdgeInsets.all(28), child: Text(
      'Kurulum tamamlanmadı. GitHub Actions içinde SUPABASE_URL ve SUPABASE_ANON_KEY tanımlanmalı.',
      textAlign: TextAlign.center,
    ))),
  );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
    stream: _client.auth.onAuthStateChange,
    builder: (context, _) => _client.auth.currentSession == null ? const AuthScreen() : const InboxScreen(),
  );
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}
class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _username = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _error;
  Future<void> _submit() async {
    setState(() { _busy = true; _error = null; });
    try {
      if (_register) {
        final username = _username.text.trim().toLowerCase();
        if (!RegExp(r'^[a-z0-9_]{3,32}$').hasMatch(username)) {
          throw const FormatException('Kullanıcı adı 3-32 karakter olmalı (a-z, 0-9, _).');
        }
        final result = await _client.auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          data: {'username': username},
        );
        if (mounted && result.session == null) setState(() => _error = 'E-posta doğrulaması açıksa gelen kutunu kontrol et; profil otomatik oluşturulur.');
      } else {
        await _client.auth.signInWithPassword(email: _email.text.trim(), password: _password.text);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  @override
  void dispose() { _email.dispose(); _password.dispose(); _username.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Icon(Icons.shield_moon_outlined, size: 64, color: Color(0xFFB9A5FF)),
        const SizedBox(height: 16),
        const Text('SecureChat', textAlign: TextAlign.center, style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(_register ? 'Yeni hesap oluştur' : 'Hesabına giriş yap', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)),
        const SizedBox(height: 28),
        if (_register) ...[
          TextField(controller: _username, autocorrect: false, decoration: const InputDecoration(labelText: 'Kullanıcı adı', prefixIcon: Icon(Icons.alternate_email))),
          const SizedBox(height: 12),
        ],
        TextField(controller: _email, keyboardType: TextInputType.emailAddress, autocorrect: false, decoration: const InputDecoration(labelText: 'E-posta', prefixIcon: Icon(Icons.email_outlined))),
        const SizedBox(height: 12),
        TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Şifre', prefixIcon: Icon(Icons.lock_outline))),
        if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: const TextStyle(color: Colors.redAccent))],
        const SizedBox(height: 20),
        FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Bekle...' : (_register ? 'Hesap oluştur' : 'Giriş yap'))),
        TextButton(onPressed: _busy ? null : () => setState(() { _register = !_register; _error = null; }), child: Text(_register ? 'Zaten hesabın var mı? Giriş yap' : 'Hesabın yok mu? Kayıt ol')),
        const SizedBox(height: 12),
        const Text('Mesaj içeriği AES-GCM ile cihazda şifrelenir. Sohbetin iki tarafı da aynı gizli ifadeyi paylaşmalıdır. Bu uygulama henüz bağımsız güvenlik denetiminden geçmemiştir.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 12)),
      ]),
    )))),
  );
}

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});
  @override
  State<InboxScreen> createState() => _InboxScreenState();
}
class _InboxScreenState extends State<InboxScreen> {
  List<Map<String, dynamic>> _chats = [];
  bool _busy = true;
  String? _error;
  final _search = TextEditingController();
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final uid = _client.auth.currentUser!.id;
      final memberships = await _client.from('conversation_members').select('conversation_id').eq('user_id', uid);
      final ids = memberships.map((e) => e['conversation_id'] as String).toList();
      if (ids.isEmpty) { if (mounted) setState(() { _chats = []; _busy = false; _error = null; }); return; }
      final rows = await _client.from('conversations').select('id,ghost_mode,created_at').inFilter('id', ids).order('created_at', ascending: false);
      final memberRows = await _client.from('conversation_members').select('conversation_id,user_id').inFilter('conversation_id', ids);
      final otherIds = memberRows.map((m) => m['user_id'] as String).where((id) => id != uid).toSet().toList();
      final profileRows = otherIds.isEmpty ? <Map<String,dynamic>>[] : List<Map<String,dynamic>>.from(await _client.from('profiles').select('id,username').inFilter('id', otherIds));
      final profiles = {for (final p in profileRows) p['id'] as String: p['username'] as String};
      final membersByChat = <String,List<Map<String,dynamic>>>{};
      for (final member in memberRows) {
        final chatId = member['conversation_id'] as String;
        membersByChat.putIfAbsent(chatId, () => []).add({
          'user_id': member['user_id'],
          'profiles': {'username': profiles[member['user_id']] ?? 'Kullanıcı'},
        });
      }
      final chats = List<Map<String,dynamic>>.from(rows).map((row) {
        final chat = Map<String,dynamic>.from(row);
        chat['conversation_members'] = membersByChat[chat['id']] ?? [];
        return chat;
      }).toList();
      if (mounted) setState(() { _chats = chats; _busy = false; _error = null; });
    } catch (e) { if (mounted) setState(() { _busy = false; _error = e.toString(); }); }
  }
  String _title(Map<String,dynamic> chat) {
    final members = (chat['conversation_members'] as List? ?? []);
    for (final m in members) {
      if (m['user_id'] != _client.auth.currentUser!.id) return (m['profiles']?['username'] ?? 'Sohbet').toString();
    }
    return 'Kendim';
  }
  Future<void> _newChat() async {
    final result = await showDialog<Map<String, dynamic>>(context: context, builder: (context) {
      final controller = TextEditingController();
      var ghost = false;
      return StatefulBuilder(builder: (context, setDialogState) => AlertDialog(title: const Text('Yeni sohbet'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Kullanıcı adı')),
          SwitchListTile(value: ghost, onChanged: (v) => setDialogState(() => ghost = v), title: const Text('Hayalet Mod')),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')), FilledButton(onPressed: () => Navigator.pop(context, {'username': controller.text.trim(), 'ghost': ghost}), child: const Text('Oluştur'))]));
    });
    if (result == null || (result['username'] as String).isEmpty || !mounted) return;
    try {
      final id = await _client.rpc('create_conversation_with_username', params: {'p_username': (result['username'] as String).toLowerCase(), 'p_ghost_mode': result['ghost']});
      if (!mounted) return;
      await _load();
      final chat = _chats.firstWhere((c) => c['id'] == id, orElse: () => {'id': id, 'ghost_mode': result['ghost'], 'conversation_members': []});
      await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(conversation: chat, title: result['username'] as String)));
      _load();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sohbet açılamadı: $e'))); }
  }
  @override
  void dispose() { _search.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('SecureChat', style: TextStyle(fontWeight: FontWeight.w700)), actions: [
      IconButton(tooltip: 'Çıkış', onPressed: () => _client.auth.signOut(), icon: const Icon(Icons.logout)),
    ]),
    body: RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
      TextField(controller: _search, onChanged: (_) => setState(() {}), decoration: InputDecoration(hintText: 'Sohbet ara', prefixIcon: const Icon(Icons.search), filled: true, fillColor: const Color(0xFF151520), border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none))),
      const SizedBox(height: 20),
      if (_busy) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
      if (_error != null) Text('Sohbetler yüklenemedi: $_error', style: const TextStyle(color: Colors.redAccent)),
      if (!_busy && _chats.where((c) => _title(c).toLowerCase().contains(_search.text.toLowerCase())).isEmpty)
        const Padding(padding: EdgeInsets.symmetric(vertical: 42), child: Column(children: [Icon(Icons.forum_outlined, size: 48, color: Color(0xFFB9A5FF)), SizedBox(height: 12), Text('Henüz sohbet yok', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)), SizedBox(height: 6), Text('Yeni sohbet başlatmak için kalem simgesine dokun.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54))])),
      for (final chat in _chats.where((c) => _title(c).toLowerCase().contains(_search.text.toLowerCase())))
        ListTile(leading: CircleAvatar(backgroundColor: const Color(0xFF28223D), child: Text(_title(chat).isNotEmpty ? _title(chat)[0].toUpperCase() : '?')),
          title: Text(_title(chat)), subtitle: Text(chat['ghost_mode'] == true ? 'Hayalet Mod açık' : 'Şifreli mesajlaşma'),
          trailing: const Icon(Icons.chevron_right), onTap: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(conversation: chat, title: _title(chat)))); _load(); }),
    ])),
    floatingActionButton: FloatingActionButton(onPressed: _newChat, child: const Icon(Icons.edit_outlined)),
  );
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.conversation, required this.title});
  final Map<String,dynamic> conversation;
  final String title;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}
class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _secret = TextEditingController();
  final _scroll = ScrollController();
  final List<Map<String,dynamic>> _messages = [];
  RealtimeChannel? _channel;
  SecretKey? _key;
  bool _keyReady = false;
  bool _loading = true;
  bool _sending = false;
  String? _error;
  String get _id => widget.conversation['id'].toString();
  String get _keyName => 'securechat_key_$_id';
  @override
  void initState() { super.initState(); _init(); }
  Future<SecretKey> _derive(String phrase) => Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
    secretKey: SecretKey(utf8.encode(phrase)), nonce: utf8.encode(_id), info: utf8.encode('SecureChat-v1'),
  );
  Future<void> _init() async {
    try {
      final saved = await _storage.read(key: _keyName);
      if (saved != null && saved.isNotEmpty) { _key = await _derive(saved); _keyReady = true; }
      await _loadMessages();
      _channel = _client.channel('chat-$_id')
        ..onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'encrypted_messages', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'conversation_id', value: _id), callback: (_) => _loadMessages())
        ..subscribe();
    } catch (e) { _error = e.toString(); }
    if (mounted) setState(() { _loading = false; });
  }
  Future<void> _setSecret() async {
    final phrase = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('Sohbet gizli ifadesi'),
      content: TextField(controller: _secret, obscureText: true, decoration: const InputDecoration(labelText: 'İkinizin de bildiği uzun ifade')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')), FilledButton(onPressed: () => Navigator.pop(context, _secret.text), child: const Text('Kaydet'))],
    ));
    if (phrase == null || phrase.trim().length < 12) {
      if (phrase != null && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('En az 12 karakterlik bir ifade kullan.')));
      return;
    }
    await _storage.write(key: _keyName, value: phrase);
    _key = await _derive(phrase);
    if (mounted) setState(() { _keyReady = true; _error = null; });
    await _loadMessages();
  }
  Future<String> _encrypt(String text) async {
    final box = await _cipher.encrypt(utf8.encode(text), secretKey: _key!);
    return jsonEncode({'nonce': base64Encode(box.nonce), 'ciphertext': base64Encode(box.cipherText), 'mac': base64Encode(box.mac.bytes)});
  }
  Future<String> _decrypt(String encoded) async {
    try {
      final obj = jsonDecode(encoded) as Map<String,dynamic>;
      final box = SecretBox(base64Decode(obj['ciphertext'] as String), nonce: base64Decode(obj['nonce'] as String), mac: Mac(base64Decode(obj['mac'] as String)));
      return utf8.decode(await _cipher.decrypt(box, secretKey: _key!));
    } catch (_) { return 'Bu mesaj çözülemedi. Gizli ifadeyi kontrol et.'; }
  }
  Future<void> _loadMessages() async {
    try {
      final rows = await _client.from('encrypted_messages').select().eq('conversation_id', _id).order('created_at');
      final decoded = <Map<String,dynamic>>[];
      for (final row in rows) {
        final item = Map<String,dynamic>.from(row);
        if (_key != null) item['display_text'] = await _decrypt(item['ciphertext'] as String);
        decoded.add(item);
      }
      if (mounted) setState(() { _messages..clear()..addAll(decoded); _error = null; });
      await _client.rpc('mark_conversation_read', params: {'p_conversation_id': _id});
    } catch (e) { if (mounted) setState(() => _error = e.toString()); }
  }
  Future<void> _send() async {
    if (!_keyReady || _key == null) { await _setSecret(); if (!_keyReady) return; }
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final encrypted = await _encrypt(text);
      final obj = jsonDecode(encrypted) as Map<String,dynamic>;
      await _client.from('encrypted_messages').insert({
        'conversation_id': _id, 'sender_id': _client.auth.currentUser!.id,
        'ciphertext': encrypted, 'nonce': obj['nonce'], 'key_version': 1,
        'delete_after_read': widget.conversation['ghost_mode'] == true,
      });
      _input.clear();
      await _loadMessages();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Mesaj gönderilemedi: $e'))); }
    finally { if (mounted) setState(() => _sending = false); }
  }
  Future<void> _leave() async {
    if (widget.conversation['ghost_mode'] == true) {
      try { await _client.rpc('cleanup_ghost_messages', params: {'p_conversation_id': _id}); } catch (_) {}
    }
    if (mounted) Navigator.pop(context);
  }
  @override
  void dispose() {
    _input.dispose(); _secret.dispose(); _scroll.dispose();
    if (_channel != null) _client.removeChannel(_channel!);
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(widget.title), leading: IconButton(onPressed: _leave, icon: const Icon(Icons.arrow_back)), actions: [
        IconButton(tooltip: 'Gizli ifadeyi ayarla', onPressed: _setSecret, icon: const Icon(Icons.key_outlined)),
      ]),
      body: Column(children: [
        if (!_keyReady) MaterialBanner(content: const Text('Mesajları okuyup göndermek için iki tarafta da aynı gizli ifadeyi ayarla.'), actions: [TextButton(onPressed: _setSecret, child: const Text('İfade ayarla'))]),
        if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
        Expanded(child: _loading ? const Center(child: CircularProgressIndicator()) : ListView.builder(
          controller: _scroll, padding: const EdgeInsets.all(12), itemCount: _messages.length,
          itemBuilder: (context, i) {
            final m = _messages[i];
            final mine = m['sender_id'] == _client.auth.currentUser!.id;
            final text = _keyReady ? (m['display_text'] ?? 'Şifreli mesaj') : 'Şifreli mesaj';
            return Align(alignment: mine ? Alignment.centerRight : Alignment.centerLeft, child: Container(
              constraints: const BoxConstraints(maxWidth: 310), margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: mine ? const Color(0xFF55418C) : const Color(0xFF20202D), borderRadius: BorderRadius.circular(16)),
              child: Text(text.toString()),
            ));
          },
        )),
        SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 12), child: Row(children: [
          Expanded(child: TextField(controller: _input, minLines: 1, maxLines: 5, textInputAction: TextInputAction.newline, decoration: InputDecoration(hintText: 'Şifreli mesaj yaz...', filled: true, fillColor: const Color(0xFF151520), border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none)))),
          const SizedBox(width: 8),
          IconButton.filled(onPressed: _sending ? null : _send, icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send)),
        ]))),
      ]),
    );
}
