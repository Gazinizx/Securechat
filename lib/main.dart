import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_users_screen.dart';

const _storage = FlutterSecureStorage();
final _cipher = AesGcm.with256bits();
final _client = Supabase.instance.client;
bool _supabaseReady = false;
bool _supabaseInitializing = false;
String? _supabaseInitError;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(SecureChatApp(
    supabaseUrl: const String.fromEnvironment('SUPABASE_URL'),
    supabaseKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
  ));
}

class SecureChatApp extends StatefulWidget {
  const SecureChatApp({super.key, this.supabaseUrl = '', this.supabaseKey = ''});
  final String supabaseUrl;
  final String supabaseKey;

  @override
  State<SecureChatApp> createState() => _SecureChatAppState();
}

class _SecureChatAppState extends State<SecureChatApp> {
  @override
  void initState() {
    super.initState();
    _initializeBackend();
  }

  Future<void> _initializeBackend() async {
    _supabaseInitializing = true;
    _supabaseInitError = null;
    if (widget.supabaseUrl.trim().isEmpty || widget.supabaseKey.trim().isEmpty) {
      final missing = <String>[
        if (widget.supabaseUrl.trim().isEmpty) 'SUPABASE_URL',
        if (widget.supabaseKey.trim().isEmpty) 'SUPABASE_ANON_KEY',
      ];
      _supabaseInitError = 'Derleme ayarı eksik: ${missing.join(', ')} uygulamaya aktarılmamış.';
      debugPrint('SecureChat backend config error: $_supabaseInitError');
      _supabaseInitializing = false;
      if (mounted) setState(() {});
      return;
    }
    final uri = Uri.tryParse(widget.supabaseUrl.trim());
    if (uri == null || uri.scheme != 'https' || !uri.host.endsWith('.supabase.co')) {
      _supabaseInitError = 'SUPABASE_URL geçersiz görünüyor. Supabase proje URL’si https://...supabase.co biçiminde olmalı.';
      debugPrint('SecureChat backend config error: $_supabaseInitError');
      _supabaseInitializing = false;
      if (mounted) setState(() {});
      return;
    }
    try {
      await Supabase.initialize(url: widget.supabaseUrl.trim(), publishableKey: widget.supabaseKey.trim());
      _supabaseReady = true;
      debugPrint('SecureChat Supabase initialized for host: ${uri.host}');
    } catch (e, stack) {
      // Do not print API keys. The SDK exception is useful for diagnosing URL/key/config failures.
      _supabaseInitError = '${e.runtimeType}: ${e.toString()}';
      debugPrint('Supabase initialization failed for ${uri.host}: $_supabaseInitError');
      debugPrintStack(stackTrace: stack);
    } finally {
      _supabaseInitializing = false;
      if (mounted) setState(() {});
    }
  }

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
    home: _supabaseReady ? const AuthGate() : LaunchScreen(
      initializing: _supabaseInitializing,
      initializationError: _supabaseInitError,
    ),
  );
}

class LaunchScreen extends StatelessWidget {
  const LaunchScreen({super.key, this.initializing = false, this.initializationError});
  final bool initializing;
  final String? initializationError;

  void _openAuth(BuildContext context, {required bool register}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AuthScreen(initialRegister: register),
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 28),
                Container(
                  width: 96, height: 96,
                  decoration: BoxDecoration(
                    color: const Color(0xFF211B35),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: const Color(0xFF55418C)),
                  ),
                  child: const Icon(Icons.shield_moon_rounded, size: 54, color: Color(0xFFB9A5FF)),
                ),
                const SizedBox(height: 28),
                const Text('SecureChat', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
                const SizedBox(height: 10),
                const Text('Özel konuşmaların için daha sakin bir alan.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.white70, height: 1.5)),
                const SizedBox(height: 30),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF14141F),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFF2A2838)),
                  ),
                  child: const Column(children: [
                    _FeatureRow(icon: Icons.lock_outline_rounded, title: 'Şifreli mesajlaşma', subtitle: 'Mesajlar gönderilmeden önce cihazda şifrelenir.'),
                    SizedBox(height: 18),
                    _FeatureRow(icon: Icons.visibility_off_outlined, title: 'Süreli mesajlar', subtitle: 'İstersen mesajların 2 saatten 1 haftaya kadar sonra silinsin.'),
                    SizedBox(height: 18),
                    _FeatureRow(icon: Icons.devices_outlined, title: 'Hesabın, sohbetlerin', subtitle: 'Hesapla giriş yap ve kullanıcı adıyla sohbet başlat.'),
                  ]),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: () => _openAuth(context, register: false),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                  child: const Text('Giriş yap'),
                ),
                const SizedBox(height: 12),
                const SizedBox(height: 22),
                Text(
                  initializing
                    ? 'Güvenli bağlantı başlatılıyor…'
                    : initializationError != null
                      ? 'Sunucu bağlantısı başlatılamadı. Giriş ekranları kullanılabilir; hesap işlemleri için bağlantı ayarı kontrol edilmeli.'
                      : 'Hesap işlemleri için sunucu bağlantısı gerekir. Uygulama ekranları bağlantı olmadan da açılır.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white38, fontSize: 12, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 42, height: 42,
        decoration: BoxDecoration(color: const Color(0xFF29223F), borderRadius: BorderRadius.circular(13)),
        child: Icon(icon, color: const Color(0xFFB9A5FF), size: 22),
      ),
      const SizedBox(width: 13),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(color: Colors.white54, height: 1.4, fontSize: 13)),
      ])),
    ],
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
  const AuthScreen({super.key, this.initialRegister = false});
  final bool initialRegister;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}
class _AuthScreenState extends State<AuthScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();

  }

  Future<void> _submit() async {
    if (!_supabaseReady) {
      setState(() => _error = _supabaseInitError ?? 'Supabase bağlantısı henüz yapılandırılmamış.');
      return;
    }
    final username = _username.text.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9_]{3,32}$').hasMatch(username)) {
      setState(() => _error = 'Kullanıcı adı 3-32 karakter olmalı (a-z, 0-9, _).');
      return;
    }
    if (_password.text.length < 6) {
      setState(() => _error = 'Şifre en az 6 karakter olmalı.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      // Supabase Auth requires an email/phone identifier; users see and enter only usernames.
      await _client.auth.signInWithPassword(
        email: '$username@securechat.invalid',
        password: _password.text,
      );
    } catch (e) {
      // Show the actual Supabase/Auth failure instead of masking configuration and network errors.
      debugPrint('SecureChat sign-in failed: ${e.runtimeType}: $e');
      if (mounted) setState(() => _error = 'Giriş başarısız: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  @override
  void dispose() { _password.dispose(); _username.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Icon(Icons.shield_moon_outlined, size: 64, color: Color(0xFFB9A5FF)),
        const SizedBox(height: 16),
        const Text('SecureChat', textAlign: TextAlign.center, style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Yalnızca yönetici tarafından oluşturulan hesaplarla giriş yap.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
        const SizedBox(height: 28),
        TextField(controller: _username, autocorrect: false, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Kullanıcı adı', prefixIcon: Icon(Icons.person_outline))),
        const SizedBox(height: 12),
        TextField(controller: _password, obscureText: true, onSubmitted: (_) => _busy ? null : _submit(), decoration: const InputDecoration(labelText: 'Şifre', prefixIcon: Icon(Icons.lock_outline))),
        if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: const TextStyle(color: Colors.redAccent))],
        const SizedBox(height: 20),
        FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Bekle...' : 'Giriş yap')),
        const SizedBox(height: 12),
        const Text('Mesajlar cihazda AES-GCM ile şifrelenir. Bu uygulama bağımsız güvenlik denetiminden geçmemiştir.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 12)),
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
  String _clockLabel(dynamic value) {
    try {
      final date = DateTime.parse(value.toString()).toLocal();
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (_) { return ''; }
  }
  List<Map<String, dynamic>> _chats = [];
  bool _busy = true;
  String? _error;
  List<Map<String,dynamic>> _accounts = [];
  RealtimeChannel? _inboxChannel;
  @override
  void initState() {
    super.initState();
    _publishIdentityKey();
    _load();
    _checkAdmin();
    _inboxChannel = _client.channel('securechat-inbox-${_client.auth.currentUser!.id}')
      ..onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'encrypted_messages', callback: (_) => _load())
      ..subscribe();
  }
  Future<void> _publishIdentityKey() async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return;
      // Identity keys must be isolated per Supabase account on shared devices.
      final privateStorageKey = 'securechat_identity_private_v1_$uid';
      final publicStorageKey = 'securechat_identity_public_v1_$uid';
      var privateValue = await _storage.read(key: privateStorageKey);
      var publicValue = await _storage.read(key: publicStorageKey);
      if (privateValue == null || publicValue == null) {
        final pair = await X25519().newKeyPair();
        final privateBytes = await pair.extractPrivateKeyBytes();
        final publicKey = await pair.extractPublicKey();
        privateValue = base64Encode(privateBytes);
        publicValue = base64Encode(publicKey.bytes);
        await _storage.write(key: privateStorageKey, value: privateValue);
        await _storage.write(key: publicStorageKey, value: publicValue);
      }
      await _client.from('user_encryption_keys').upsert({
        'user_id': uid,
        'public_key': publicValue,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id');
    } catch (e) {
      if (mounted) setState(() => _error = 'Şifreleme anahtarı hazırlanamadı: $e');
    }
  }

  Future<void> _load() async {
    try {
      final uid = _client.auth.currentUser!.id;
      _accounts = List<Map<String,dynamic>>.from(await _client.from('profiles').select('id,username').neq('id', uid).order('username'));
      final memberships = await _client.from('conversation_members').select('conversation_id').eq('user_id', uid);
      final ids = memberships.map((e) => e['conversation_id'] as String).toList();
      if (ids.isEmpty) { if (mounted) setState(() { _chats = []; _busy = false; _error = null; }); return; }
      final rows = await _client.from('conversations').select('id,message_expiry_seconds,created_at').inFilter('id', ids).order('created_at', ascending: false);
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
        chat['last_message_at'] = null;
        chat['last_message_sender'] = null;
        return chat;
      }).toList();
      // Load a bounded recent window so the inbox can show a useful latest-message preview.
      final recentMessages = List<Map<String,dynamic>>.from(await _client
        .from('encrypted_messages').select('conversation_id,sender_id,created_at')
        .inFilter('conversation_id', ids).order('created_at', ascending: false).limit(500));
      final latestByChat = <String, Map<String,dynamic>>{};
      for (final message in recentMessages) {
        latestByChat.putIfAbsent(message['conversation_id'] as String, () => message);
      }
      for (final chat in chats) {
        final latest = latestByChat[chat['id'] as String];
        if (latest != null) {
          chat['last_message_at'] = latest['created_at'];
          chat['last_message_sender'] = latest['sender_id'];
        }
      }
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
      return AlertDialog(title: const Text('Yeni sohbet'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Kullanıcı adı')),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')), FilledButton(onPressed: () => Navigator.pop(context, {'username': controller.text.trim()}), child: const Text('Oluştur'))]);
    });
    if (result == null || (result['username'] as String).isEmpty || !mounted) return;
    try {
      final id = await _client.rpc('create_conversation_with_username', params: {'p_username': (result['username'] as String).toLowerCase()});
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      final chat = _chats.firstWhere((c) => c['id'] == id, orElse: () => {'id': id, 'message_expiry_seconds': 0, 'conversation_members': []});
      await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(conversation: chat, title: result['username'] as String)));
      _load();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sohbet açılamadı: $e'))); }
  }
  bool _isAdmin = false;
  Future<void> _checkAdmin() async {
    try {
      final result = await _client.functions.invoke('securechat-admin-users', body: {'action': 'list'});
      if (mounted) setState(() => _isAdmin = result.status == 200);
    } catch (_) { if (mounted) setState(() => _isAdmin = false); }
  }
  @override
  void dispose() {
    if (_inboxChannel != null) _client.removeChannel(_inboxChannel!);
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('SecureChat', style: TextStyle(fontWeight: FontWeight.w700)), actions: [
      if (_isAdmin) IconButton(tooltip: 'Yönetici', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminUsersScreen())), icon: const Icon(Icons.admin_panel_settings_outlined)),
      IconButton(tooltip: 'Yenile', onPressed: _load, icon: const Icon(Icons.refresh)),
      IconButton(tooltip: 'Çıkış', onPressed: () => _client.auth.signOut(), icon: const Icon(Icons.logout)),
    ]),
    body: RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Hesaplar', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      const Text('Bir kullanıcıya dokunarak sohbeti aç.', style: TextStyle(color: Colors.white54)),
      const SizedBox(height: 14),
      if (_busy) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
      if (_error != null) Text('Veriler yüklenemedi: $_error', style: const TextStyle(color: Colors.redAccent)),
      if (!_busy && _accounts.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 30), child: Text('Şu anda başka kullanıcı hesabı yok.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54))),
      for (final account in _accounts)
        ListTile(
          leading: CircleAvatar(backgroundColor: const Color(0xFF28223D), child: Text((account['username'] as String? ?? '?').isNotEmpty ? (account['username'] as String)[0].toUpperCase() : '?')),
          title: Text(account['username'] as String? ?? 'Kullanıcı'),
          trailing: const Icon(Icons.chat_bubble_outline),
          onTap: () async {
            try {
              final id = await _client.rpc('create_conversation_with_username', params: {'p_username': account['username']});
              await _load();
              if (!mounted) return;
              final chat = _chats.firstWhere((c) => c['id'] == id, orElse: () => {'id': id, 'message_expiry_seconds': 0, 'conversation_members': []});
              await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(conversation: chat, title: account['username'] as String)));
              _load();
            } catch (e) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sohbet açılamadı: $e')));
            }
          },
        ),
      const Divider(height: 28),
      const Text('Son sohbetler', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      for (final chat in _chats)
        ListTile(
          leading: CircleAvatar(child: Text(_title(chat).isNotEmpty ? _title(chat)[0].toUpperCase() : '?')),
          title: Text(_title(chat)),
          subtitle: Text((chat['message_expiry_seconds'] as int? ?? 0) > 0 ? 'Süreli mesajlar açık' : 'Şifreli sohbet'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(conversation: chat, title: _title(chat)))); _load(); },
        ),
    ])),
  );
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.conversation, required this.title});
  final Map<String,dynamic> conversation;
  final String title;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}
class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  String _clockLabel(dynamic value) {
    try {
      final date = DateTime.parse(value.toString()).toLocal();
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (_) { return ''; }
  }
  final _input = TextEditingController();
  final _picker = ImagePicker();
  bool _mediaBusy = false;
  final _scroll = ScrollController();
  final List<Map<String,dynamic>> _messages = [];
  final Map<String, Future<Uint8List?>> _mediaPreviewCache = {};
  RealtimeChannel? _channel;
  RealtimeChannel? _callChannel;
  RTCPeerConnection? _peer;
  MediaStream? _localStream;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  final List<RTCIceCandidate> _pendingIce = [];
  bool _callBusy = false;
  bool _videoCall = false;
  String? _callStatus;
  bool _renderersReady = false;
  bool _microphoneMuted = false;
  bool _speakerOn = false;
  bool _cameraEnabled = true;
  SecretKey? _key;
  bool _keyReady = false;
  bool _loading = true;
  bool _sending = false;
  int _expirySeconds = 0;
  String? _error;
  String get _id => widget.conversation['id'].toString();
  String get _privateKeyName => 'securechat_identity_private_v1_${_client.auth.currentUser!.id}';
  String get _publicKeyName => 'securechat_identity_public_v1_${_client.auth.currentUser!.id}';
  @override
  void initState() { WidgetsBinding.instance.addObserver(this); super.initState(); _expirySeconds = (widget.conversation['message_expiry_seconds'] as int?) ?? 0; _init(); }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Never stop or recreate the WebRTC stream when the screen locks. Android still
    // needs the declared microphone foreground service to keep capture alive.
    if (state == AppLifecycleState.resumed && _peer != null && _localStream != null) {
      for (final track in _localStream!.getAudioTracks()) { track.enabled = !_microphoneMuted; }
      if (mounted) setState(() {});
    }
  }
  Future<void> _setExpiry(int seconds) async {
    try {
      await _client.from('conversations').update({'message_expiry_seconds': seconds}).eq('id', _id);
      if (!mounted) return;
      setState(() {
        _expirySeconds = seconds;
        widget.conversation['message_expiry_seconds'] = seconds;
      });
      final label = seconds == 0 ? 'Süreli mesajlar kapatıldı' : 'Süreli mesajlar açıldı';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(label)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Süreli mesaj ayarı değiştirilemedi: $e')));
    }
  }

  Future<void> _prepareCall({required bool video}) async {
    if (_callBusy) return;
    setState(() { _callBusy = true; _videoCall = video; _callStatus = null; });
    try {
      // Initialize renderers before building RTCVideoView widgets; otherwise the first
      // video-call frame can reference a renderer without a texture.
      if (!_renderersReady) {
        await _localRenderer.initialize();
        try {
          await _remoteRenderer.initialize();
          _renderersReady = true;
        } catch (_) {
          await _localRenderer.dispose();
          rethrow;
        }
      }
      _localStream = await navigator.mediaDevices.getUserMedia({'audio':true,'video':video ? {'facingMode':'user'} : false});
      _microphoneMuted = false;
      _cameraEnabled = video;
      _speakerOn = video;
      await Helper.setSpeakerphoneOn(_speakerOn);
      _localRenderer.srcObject = _localStream;
      _peer = await createPeerConnection({'iceServers':[{'urls':'stun:stun.l.google.com:19302'}]});
      for (final track in _localStream!.getTracks()) { await _peer!.addTrack(track, _localStream!); }
      _peer!.onTrack = (event) { if (event.streams.isNotEmpty) { _remoteRenderer.srcObject = event.streams.first; if (mounted) setState(() => _callStatus = 'Bağlandı'); } };
      _peer!.onIceCandidate = (candidate) { if (candidate.candidate != null) { _sendSignal('ice', {'candidate':candidate.candidate,'sdpMid':candidate.sdpMid,'sdpMLineIndex':candidate.sdpMLineIndex}); } };
      if (mounted) setState(() { _callBusy = false; _callStatus = 'Bağlantı kuruluyor…'; });
    } catch (e) { await _endCall(sendSignal:false); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Arama başlatılamadı: $e'))); }
  }

  String? _otherMemberId() {
    final members = (widget.conversation['conversation_members'] as List? ?? []);
    for (final member in members) { if (member['user_id'] != _client.auth.currentUser!.id) return member['user_id'] as String?; }
    return null;
  }

  Future<void> _sendSignal(String type, Map<String,dynamic> data) async {
    final receiver = _otherMemberId();
    if (receiver == null) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Sohbet üyesi bilgisi eksik; sohbet listesinden yeniden aç.'))); return; }
    await _client.from('call_signals').insert({'conversation_id':_id,'sender_id':_client.auth.currentUser!.id,'receiver_id':receiver,'signal_type':type,'payload':data});
  }

  Future<void> _startCall({required bool video}) async {
    if (_otherMemberId() == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Sohbet üyesi bulunamadı. Sohbeti listeden yeniden aç.'))); return; }
    await _prepareCall(video:video);
    if (_peer == null) return;
    try {
      final offer = await _peer!.createOffer({'offerToReceiveAudio':true,'offerToReceiveVideo':video});
      await _peer!.setLocalDescription(offer);
      await _sendSignal('offer', {'sdp':offer.sdp,'type':offer.type,'video':video});
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Arama teklifi gönderilemedi: $e'))); await _endCall(sendSignal:false); }
  }

  Future<void> _handleCallSignal(Map<String,dynamic> row) async {
    if (row['receiver_id'] != _client.auth.currentUser!.id || row['sender_id'] == _client.auth.currentUser!.id) return;
    final type = row['signal_type'] as String? ?? '';
    final payload = Map<String,dynamic>.from(row['payload'] as Map? ?? {});
    try {
      if (type == 'offer') {
        if (_peer != null) return;
        final accept = await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:Text(payload['video'] == true ? 'Görüntülü arama' : 'Sesli arama'),content:const Text('Sohbet arkadaşın seni arıyor.'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Reddet')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Yanıtla'))]));
        if (accept != true || !mounted) { await _sendSignal('reject',{}); return; }
        await _prepareCall(video:payload['video'] == true);
        if (_peer == null) return;
        await _peer!.setRemoteDescription(RTCSessionDescription(payload['sdp'] as String?,payload['type'] as String? ?? 'offer'));
        for (final candidate in _pendingIce) { await _peer!.addCandidate(candidate); } _pendingIce.clear();
        final answer = await _peer!.createAnswer(); await _peer!.setLocalDescription(answer);
        await _sendSignal('answer', {'sdp':answer.sdp,'type':answer.type});
      } else if (type == 'answer' && _peer != null) {
        await _peer!.setRemoteDescription(RTCSessionDescription(payload['sdp'] as String?,payload['type'] as String? ?? 'answer'));
        for (final candidate in _pendingIce) { await _peer!.addCandidate(candidate); } _pendingIce.clear();
      } else if (type == 'ice') {
        final candidate = RTCIceCandidate(payload['candidate'] as String?,payload['sdpMid'] as String?,payload['sdpMLineIndex'] as int?);
        if (_peer != null && await _peer!.getRemoteDescription() != null) { await _peer!.addCandidate(candidate); } else { _pendingIce.add(candidate); }
      } else if (type == 'end' || type == 'reject') { await _endCall(sendSignal:false); }
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Arama sinyali işlenemedi: $e'))); }
  }

  Future<void> _endCall({bool sendSignal = true}) async {
    if (sendSignal && _peer != null) { try { await _sendSignal('end',{}); } catch (_) {} }
    try { await _peer?.close(); } catch (_) {} _peer = null;
    try { for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) { track.stop(); } await _localStream?.dispose(); } catch (_) {}
    _localStream = null;
    if (_renderersReady) {
      _localRenderer.srcObject = null;
      _remoteRenderer.srcObject = null;
    }
    _pendingIce.clear();
    _microphoneMuted = false;
    _speakerOn = false;
    _cameraEnabled = true;
    try { await Helper.setSpeakerphoneOn(false); } catch (_) {}
    if (mounted) setState(() { _callBusy = false; _callStatus = null; });
  }

  Future<void> _init() async {
    try {
      await _ensureConversationKey();
      await _loadMessages();
      _callChannel = _client.channel('call-signals-$_id')..onPostgresChanges(event:PostgresChangeEvent.insert,schema:'public',table:'call_signals',filter:PostgresChangeFilter(type:PostgresChangeFilterType.eq,column:'conversation_id',value:_id),callback:(payload) => _handleCallSignal(Map<String,dynamic>.from(payload.newRecord)))..subscribe();
      _channel = _client.channel('chat-$_id')
        ..onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'encrypted_messages', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'conversation_id', value: _id), callback: (_) => _loadMessages())
        ..subscribe();
    } catch (e) { _error = e.toString(); }
    if (mounted) setState(() { _loading = false; });
  }
  Future<SimpleKeyPairData> _loadOrCreateIdentity() async {
    final savedPrivate = await _storage.read(key: _privateKeyName);
    final savedPublic = await _storage.read(key: _publicKeyName);
    if (savedPrivate != null && savedPublic != null) {
      return SimpleKeyPairData(
        base64Decode(savedPrivate),
        publicKey: SimplePublicKey(base64Decode(savedPublic), type: KeyPairType.x25519),
        type: KeyPairType.x25519,
      );
    }
    final pair = await X25519().newKeyPair();
    final privateBytes = await pair.extractPrivateKeyBytes();
    final publicKey = await pair.extractPublicKey();
    await _storage.write(key: _privateKeyName, value: base64Encode(privateBytes));
    await _storage.write(key: _publicKeyName, value: base64Encode(publicKey.bytes));
    return SimpleKeyPairData(
      privateBytes,
      publicKey: SimplePublicKey(publicKey.bytes, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
  }

  Future<void> _ensureConversationKey() async {
    final userId = _client.auth.currentUser?.id;
    final peerId = _otherMemberId();
    if (userId == null || peerId == null) {
      if (mounted) setState(() { _keyReady = false; _error = 'Sohbet üyesi bilgisi eksik. Sohbet listesinden yeniden aç.'; });
      return;
    }
    try {
      final identity = await _loadOrCreateIdentity();
      final ownPublic = base64Encode(identity.publicKey.bytes);
      await _client.from('user_encryption_keys').upsert({
        'user_id': userId,
        'public_key': ownPublic,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id');

      // The peer's inbox publishes its key asynchronously; retry to avoid a race.
      Map<String, dynamic>? peerRow;
      for (var attempt = 0; attempt < 15; attempt++) {
        peerRow = await _client.from('user_encryption_keys')
            .select('public_key').eq('user_id', peerId).maybeSingle();
        if (peerRow != null && (peerRow['public_key'] as String? ?? '').isNotEmpty) break;
        if (attempt < 14) {
          if (mounted) setState(() {
            _keyReady = false;
            _error = 'Karşı tarafın şifreleme anahtarı bekleniyor… (${attempt + 1}/15)';
          });
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }
      if (peerRow == null || (peerRow['public_key'] as String? ?? '').isEmpty) {
        if (mounted) setState(() {
          _keyReady = false;
          _error = 'Karşı tarafın şifreleme anahtarı sunucuda görünmüyor. Karşı taraf uygulamayı açıp sohbet listesine girdikten sonra “Yeniden dene”ye bas.';
        });
        return;
      }
      final remotePublic = SimplePublicKey(base64Decode(peerRow['public_key'] as String), type: KeyPairType.x25519);
      final shared = await X25519().sharedSecretKey(keyPair: identity, remotePublicKey: remotePublic);
      final derivedKey = await Hkdf(
        hmac: Hmac.sha256(),
        outputLength: 32,
      ).deriveKey(
        secretKey: shared,
        nonce: utf8.encode(_id),
        info: utf8.encode('SecureChat-E2EE-v1'),
      );
      if (mounted) setState(() { _key = derivedKey; _keyReady = true; _error = null; });
    } catch (e) {
      if (mounted) setState(() {
        _keyReady = false;
        _error = 'Şifreleme anahtarı alınamadı: $e';
      });
    }
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
    } catch (_) { return 'Bu mesaj çözülemedi. Şifreleme anahtarları uyumlu değil.'; }
  }
  bool _loadingMessages = false;
  bool _reloadMessagesQueued = false;

  Future<void> _loadMessages() async {
    if (_loadingMessages) {
      _reloadMessagesQueued = true;
      return;
    }
    // Preserve the reader's position when they scroll up, but follow new
    // messages when already at the bottom (and on the first load).
    final wasInitialLoad = _loading;
    final shouldFollowLatest = !_scroll.hasClients ||
        (_scroll.position.maxScrollExtent - _scroll.position.pixels < 160);
    _loadingMessages = true;
    try {
      do {
        _reloadMessagesQueued = false;
        final rows = await _client
            .from('encrypted_messages')
            .select()
            .eq('conversation_id', _id)
            // created_at is the authoritative server timestamp. id gives a
            // deterministic order if multiple rows share the same timestamp.
            .order('created_at', ascending: true)
            .order('id', ascending: true);
        final now = DateTime.now().toUtc();
        final visibleRows = <Map<String, dynamic>>[];
        for (final row in rows) {
          final expiresAt = row['expires_at'];
          if (expiresAt != null &&
              !DateTime.parse(expiresAt.toString()).toUtc().isAfter(now)) {
            continue;
          }
          visibleRows.add(Map<String, dynamic>.from(row));
        }

        // Decrypt concurrently to avoid serial crypto work delaying the chat.
        final decoded = await Future.wait(visibleRows.map((item) async {
          if (_key != null) {
            item['display_text'] = await _decrypt(item['ciphertext'] as String);
          }
          return item;
        }));

        if (mounted) {
          setState(() {
            _messages
              ..clear()
              ..addAll(decoded);
            _error = null;
          });
          if (wasInitialLoad || shouldFollowLatest) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _scroll.hasClients) {
                _scroll.jumpTo(_scroll.position.maxScrollExtent);
              }
            });
          }
        }
        await _client.rpc('mark_conversation_delivered',
            params: {'p_conversation_id': _id});
        await _client.rpc('mark_conversation_read',
            params: {'p_conversation_id': _id});
      } while (_reloadMessagesQueued && mounted);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      _loadingMessages = false;
    }
  }
  Future<void> _pickAndSendMedia({required bool video}) async {
    if (_mediaBusy || _sending) return;
    if (!_keyReady || _key == null) { await _ensureConversationKey(); if (!_keyReady || _key == null) return; }
    try {
      final XFile? file = video ? await _picker.pickVideo(source: ImageSource.gallery) : await _picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) throw Exception('Dosya boş.');
      if (bytes.length > 40 * 1024 * 1024) throw Exception('Dosya en fazla 40 MB olabilir.');
      setState(() => _mediaBusy = true);
      final mediaBox = await _cipher.encrypt(bytes, secretKey: _key!);
      final extension = file.name.contains('.') ? file.name.split('.').last.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '') : (video ? 'mp4' : 'jpg');
      final mediaPath = '$_id/${_client.auth.currentUser!.id}/${DateTime.now().microsecondsSinceEpoch}.$extension.enc';
      await _client.storage.from('securechat-media').uploadBinary(mediaPath, Uint8List.fromList(mediaBox.cipherText), fileOptions: const FileOptions(contentType:'application/octet-stream',upsert:false));
      final payload = jsonEncode({'kind':'media','media_type': video ? 'video' : 'image','name':file.name,'path':mediaPath,'nonce':base64Encode(mediaBox.nonce),'mac':base64Encode(mediaBox.mac.bytes)});
      final encrypted = await _encrypt(payload);
      final envelope = jsonDecode(encrypted) as Map<String,dynamic>;
      await _client.from('encrypted_messages').insert({'conversation_id':_id,'sender_id':_client.auth.currentUser!.id,'ciphertext':encrypted,'nonce':envelope['nonce'],'key_version':1,'media_path':mediaPath});
      await _loadMessages();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Medya gönderilemedi: $e'))); }
    finally { if (mounted) setState(() => _mediaBusy = false); }
  }

  Future<Uint8List?> _loadMediaPreview(Map<String, dynamic> media) async {
    try {
      final encryptedBytes = await _client.storage.from('securechat-media').download(media['path'] as String);
      final clear = await _cipher.decrypt(
        SecretBox(encryptedBytes,
          nonce: base64Decode(media['nonce'] as String),
          mac: Mac(base64Decode(media['mac'] as String))),
        secretKey: _key!,
      );
      return Uint8List.fromList(clear);
    } catch (_) {
      return null;
    }
  }

  Future<void> _showMedia(Map<String,dynamic> media) async {
    try {
      final encryptedBytes = await _client.storage.from('securechat-media').download(media['path'] as String);
      final clear = await _cipher.decrypt(SecretBox(encryptedBytes, nonce:base64Decode(media['nonce'] as String), mac:Mac(base64Decode(media['mac'] as String))), secretKey:_key!);
      if (!mounted) return;
      if (media['media_type'] == 'image') {
        await showDialog<void>(context:context,builder:(ctx)=>Dialog(child:InteractiveViewer(child:Image.memory(Uint8List.fromList(clear),fit:BoxFit.contain))));
      } else {
        final dir = await getTemporaryDirectory();
        final safeName = (media['name'] as String? ?? 'securechat-video.mp4').replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
        final localFile = await File('${dir.path}/$safeName').writeAsBytes(clear, flush:true);
        final controller = VideoPlayerController.file(localFile);
        await controller.initialize();
        if (!mounted) { await controller.dispose(); return; }
        await showDialog<void>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setDialogState)=>Dialog(child:AspectRatio(aspectRatio:controller.value.aspectRatio,child:Stack(alignment:Alignment.center,children:[
          VideoPlayer(controller),
          IconButton.filled(onPressed:() async { if (controller.value.isPlaying) { await controller.pause(); } else { await controller.play(); } setDialogState((){}); },icon:Icon(controller.value.isPlaying ? Icons.pause : Icons.play_arrow)),
        ])))));
        await controller.dispose();
        if (await localFile.exists()) await localFile.delete();
      }
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Medya açılamadı: $e'))); }
  }

  Future<void> _send() async {
    if (!_keyReady || _key == null) { await _ensureConversationKey(); if (!_keyReady) return; }
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final encrypted = await _encrypt(text);
      final obj = jsonDecode(encrypted) as Map<String,dynamic>;
      await _client.from('encrypted_messages').insert({
        'conversation_id': _id, 'sender_id': _client.auth.currentUser!.id,
        'ciphertext': encrypted, 'nonce': obj['nonce'], 'key_version': 1,
      });
      _input.clear();
      await _loadMessages();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Mesaj gönderilemedi: $e'))); }
    finally { if (mounted) setState(() => _sending = false); }
  }
  Future<void> _toggleMicrophone() async {
    final next = !_microphoneMuted;
    for (final track in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) { track.enabled = !next; }
    if (mounted) setState(() => _microphoneMuted = next);
  }

  Future<void> _toggleSpeaker() async {
    final next = !_speakerOn;
    try { await Helper.setSpeakerphoneOn(next); if (mounted) setState(() => _speakerOn = next); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ses çıkışı değiştirilemedi: $e'))); }
  }

  Future<void> _toggleCamera() async {
    final next = !_cameraEnabled;
    for (final track in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) { track.enabled = next; }
    if (mounted) setState(() => _cameraEnabled = next);
  }

  Widget _buildCallScreen() {
    final connected = (_callStatus ?? '').toLowerCase().contains('bağlandı');
    return Material(
      color: const Color(0xFF10131B),
      child: SafeArea(child: Stack(children: [
        if (_videoCall && _remoteRenderer.srcObject != null)
          Positioned.fill(child: RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover))
        else
          Positioned.fill(child: DecoratedBox(
            decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF20263A), Color(0xFF090B11)])),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              CircleAvatar(radius: 58, backgroundColor: const Color(0xFF3A435D), child: Text(widget.title.isNotEmpty ? widget.title.substring(0, 1).toUpperCase() : '?', style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w600))),
              const SizedBox(height: 24),
              Text(widget.title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Text(_callStatus ?? 'Arama', style: const TextStyle(fontSize: 15, color: Colors.white70)),
            ]),
          )),
        if (_videoCall && _renderersReady)
          Positioned(right: 16, top: 18, width: 112, height: 164, child: ClipRRect(borderRadius: BorderRadius.circular(18), child: RTCVideoView(_localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover))),
        if (_videoCall && _remoteRenderer.srcObject != null)
          Positioned(left: 20, top: 24, child: DecoratedBox(decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(16)), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w600)), Text(_callStatus ?? 'Bağlanıyor…', style: const TextStyle(fontSize: 12, color: Colors.white70))])))),
        Positioned(left: 0, right: 0, bottom: 24, child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!connected) Padding(padding: const EdgeInsets.only(bottom: 24), child: Text(_callStatus ?? 'Bağlantı kuruluyor…', style: const TextStyle(color: Colors.white70))),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _callControl(icon: _microphoneMuted ? Icons.mic_off_rounded : Icons.mic_rounded, label: _microphoneMuted ? 'Mikrofon kapalı' : 'Mikrofon', active: _microphoneMuted, onTap: _toggleMicrophone),
            _callControl(icon: _speakerOn ? Icons.volume_up_rounded : Icons.hearing_rounded, label: _speakerOn ? 'Hoparlör' : 'Telefon', active: _speakerOn, onTap: _toggleSpeaker),
            if (_videoCall) _callControl(icon: _cameraEnabled ? Icons.videocam_rounded : Icons.videocam_off_rounded, label: 'Kamera', active: !_cameraEnabled, onTap: _toggleCamera),
            _callControl(icon: Icons.call_end_rounded, label: 'Bitir', danger: true, onTap: () => _endCall()),
          ]),
        ])),
      ])),
    );
  }

  Widget _callControl({required IconData icon, required String label, required VoidCallback onTap, bool active = false, bool danger = false}) => Column(mainAxisSize: MainAxisSize.min, children: [
    Material(color: danger ? const Color(0xFFE53935) : active ? Colors.white : const Color(0xFF343A49), shape: const CircleBorder(), child: InkWell(onTap: onTap, customBorder: const CircleBorder(), child: SizedBox(width: 62, height: 62, child: Icon(icon, color: danger ? Colors.white : active ? const Color(0xFF151821) : Colors.white, size: 27)))),
    const SizedBox(height: 8), Text(label, style: const TextStyle(fontSize: 11, color: Colors.white)),
  ]);

  Future<void> _leave() async {
    await _endCall();
    
    if (mounted) Navigator.pop(context);
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _input.dispose(); _scroll.dispose();
    if (_channel != null) _client.removeChannel(_channel!);
    if (_callChannel != null) _client.removeChannel(_callChannel!);
    if (_renderersReady) { _localRenderer.dispose(); _remoteRenderer.dispose(); }
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(widget.title), leading: IconButton(onPressed: _leave, icon: const Icon(Icons.arrow_back)), actions: [
        PopupMenuButton<int>(tooltip: 'Süreli mesajlar', initialValue: _expirySeconds, onSelected: _setExpiry, icon: Icon(Icons.timer_outlined, color: _expirySeconds > 0 ? const Color(0xFFB9A5FF) : null), itemBuilder: (_) => const [PopupMenuItem(value: 0, child: Text('Kapalı')), PopupMenuItem(value: 7200, child: Text('2 saat')), PopupMenuItem(value: 21600, child: Text('6 saat')), PopupMenuItem(value: 43200, child: Text('12 saat')), PopupMenuItem(value: 86400, child: Text('24 saat')), PopupMenuItem(value: 604800, child: Text('1 hafta'))]),
        IconButton(tooltip:'Sesli ara',onPressed:_callBusy || _callStatus != null ? null : () => _startCall(video:false),icon:const Icon(Icons.call_outlined)),
        IconButton(tooltip:'Görüntülü ara',onPressed:_callBusy || _callStatus != null ? null : () => _startCall(video:true),icon:const Icon(Icons.videocam_outlined)),
      ]),
      body: Stack(children: [
        Column(children: [
        if (_error != null) Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Text(_error!, style: const TextStyle(color: Colors.redAccent), textAlign: TextAlign.center),
              if (!_keyReady) TextButton.icon(
                onPressed: _sending ? null : _ensureConversationKey,
                icon: const Icon(Icons.refresh),
                label: const Text('Yeniden dene'),
              ),
            ],
          ),
        ),
        Expanded(child: _loading ? const Center(child: CircularProgressIndicator()) : ListView.builder(
          controller: _scroll, padding: const EdgeInsets.all(12), itemCount: _messages.length,
          itemBuilder: (context, i) {
            final m = _messages[i];
            final mine = m['sender_id'] == _client.auth.currentUser!.id;
            final text = _keyReady ? (m['display_text'] ?? 'Şifreli mesaj') : 'Şifreli mesaj';
            Map<String,dynamic>? media;
            if (_keyReady && text is String) { try { final p = jsonDecode(text); if (p is Map<String,dynamic> && p['kind'] == 'media') media = p; } catch (_) {} }
            return Align(alignment: mine ? Alignment.centerRight : Alignment.centerLeft, child: Container(
              constraints: const BoxConstraints(maxWidth: 310), margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: mine ? const Color(0xFF55418C) : const Color(0xFF20202D), borderRadius: BorderRadius.circular(16)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                if (media != null) ...[
                  InkWell(
                    onTap: () => _showMedia(media!),
                    borderRadius: BorderRadius.circular(12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 230,
                        child: media['media_type'] == 'image'
                          ? FutureBuilder<Uint8List?>(
                              future: _mediaPreviewCache.putIfAbsent(
                                media['path'] as String,
                                () => _loadMediaPreview(media!),
                              ),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState != ConnectionState.done) {
                                  return const SizedBox(height: 150, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
                                }
                                if (snapshot.data == null) {
                                  return const SizedBox(height: 110, child: Center(child: Icon(Icons.broken_image_outlined, size: 32)));
                                }
                                return Image.memory(snapshot.data!, width: 230, height: 210, fit: BoxFit.cover);
                              },
                            )
                          : Container(
                              height: 130,
                              color: Colors.black26,
                              child: const Center(child: Icon(Icons.play_circle_fill, size: 54)),
                            ),
                      ),
                    ),
                  ),
                  if (media['media_type'] == 'video')
                    const Align(alignment: Alignment.centerLeft, child: Text('Video', style: TextStyle(fontSize: 12))),
                ] else Align(alignment: Alignment.centerLeft, child: Text(text.toString())),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_clockLabel(m['created_at']), style: const TextStyle(fontSize: 10, color: Colors.white60)),
                    if (mine) ...[
                      const SizedBox(width: 4),
                      Icon(
                        m['read_at'] != null ? Icons.done_all : (m['delivered_at'] != null ? Icons.done_all : Icons.done),
                        size: 15,
                        color: m['read_at'] != null ? const Color(0xFF53BDEB) : Colors.white60,
                      ),
                    ],
                  ],
                ),
              ]),
            ));
          },
        )),
        SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(6, 8, 6, 12), child: Row(children: [
          IconButton(onPressed: _mediaBusy || _sending ? null : () => _pickAndSendMedia(video:false), tooltip:'Fotoğraf', icon:const Icon(Icons.image_outlined)),
          IconButton(onPressed: _mediaBusy || _sending ? null : () => _pickAndSendMedia(video:true), tooltip:'Video', icon:const Icon(Icons.video_library_outlined)),
          Expanded(child: TextField(controller: _input, minLines: 1, maxLines: 5, textInputAction: TextInputAction.newline, decoration: InputDecoration(hintText: 'Şifreli mesaj yaz...', filled: true, fillColor: const Color(0xFF151520), border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none)))),
          const SizedBox(width: 4),
          IconButton.filled(onPressed: _sending || _mediaBusy ? null : _send, icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send)),
        ]))),
        ]),
        if (_callStatus != null) Positioned.fill(child: _buildCallScreen()),
      ]),
    );
}
