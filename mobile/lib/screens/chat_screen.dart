import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../services/crypto_service.dart';
import '../services/attachment_service.dart';
import '../widgets/attachment_message.dart';
import 'call_screen.dart';
import '../services/firebase_bootstrap.dart';

class ChatScreen extends StatefulWidget {
  final String peerUid;
  final String peerUsername;
  const ChatScreen({super.key, required this.peerUid, required this.peerUsername});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _text = TextEditingController();
  final _secret = TextEditingController();
  final _uuid = const Uuid();
  bool _ghost = false;
  bool _revealed = false;
  bool _busy = false;
  String? _error;
  String get _uid => FirebaseAuth.instance.currentUser!.uid;
  String get _conversationId => ([_uid, widget.peerUid]..sort()).join('_');
  DocumentReference<Map<String, dynamic>> get _conversation =>
      FirebaseBootstrap.db.collection('conversations').doc(_conversationId);
  CollectionReference<Map<String, dynamic>> get _messages => _conversation.collection('messages');

  @override
  void initState() {
    super.initState();
    _ensureConversation();
  }

  Future<void> _ensureConversation() async {
    try {
      final snap = await _conversation.get();
      if (!snap.exists) {
        await _conversation.set({
          'members': ([_uid, widget.peerUid]..sort()),
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Sohbet açılamadı: $e');
    }
  }

  Future<void> _startCall({required bool audioOnly}) async {
    final callId = _uuid.v4();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CallScreen(callId: callId, peerUid: widget.peerUid, isCaller: true, audioOnly: audioOnly),
    ));
  }

  Future<void> _pickAttachment() async {
    if (_secret.text.trim().length < 16) {
      setState(() => _error = 'Önce en az 16 karakterlik ortak sohbet anahtarını gir.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await AttachmentService.pickAndSend(
        conversationId: _conversationId,
        senderUid: _uid,
        sharedSecret: _secret.text,
        ghost: _ghost,
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    if (_text.text.trim().isEmpty) return;
    if (_secret.text.trim().length < 16) {
      setState(() => _error = 'En az 16 karakterlik ortak gizli anahtar girin. Anahtarı başka bir güvenli kanaldan paylaşın.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await _ensureConversation();
      final encrypted = await CryptoService.encryptText(
        plaintext: _text.text.trim(),
        sharedSecret: _secret.text,
        conversationId: _conversationId,
      );
      await _messages.add({
        ...encrypted,
        'senderUid': _uid,
        'createdAt': FieldValue.serverTimestamp(),
        'ghost': _ghost,
        'readBy': [_uid],
        'kind': 'text',
        'clientId': _uuid.v4(),
      });
      _text.clear();
    } catch (e) { if (mounted) setState(() => _error = e.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _markRead(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data();
    if (data == null || data['senderUid'] == _uid) return;
    final readBy = List<String>.from(data['readBy'] ?? const <String>[]);
    if (!readBy.contains(_uid)) {
      // Keep the message until the reader exits this conversation.
      await doc.reference.update({'readBy': FieldValue.arrayUnion([_uid])});
    }
  }

  Future<void> _deleteReadGhostMessages() async {
    try {
      final conversation = await _conversation.get();
      final members = List<String>.from(conversation.data()?['members'] ?? const <String>[]);
      if (members.isEmpty) return;
      final snap = await _messages.where('ghost', isEqualTo: true).get();
      final batch = FirebaseBootstrap.db.batch();
      var count = 0;
      for (final doc in snap.docs) {
        final readBy = List<String>.from(doc.data()['readBy'] ?? const <String>[]);
        if (members.every(readBy.contains)) {
          final storagePath = doc.data()['storagePath'];
          if (storagePath is String && storagePath.isNotEmpty) {
            try { await FirebaseBootstrap.storage.ref(storagePath).delete(); } catch (_) {}
          }
          batch.delete(doc.reference);
          count++;
          if (count == 400) break; // Firestore batch operation safety margin.
        }
      }
      if (count > 0) await batch.commit();
    } catch (_) {
      // Best effort only; Firestore rules/server cleanup must also be configured.
    }
  }

  Future<String> _decrypt(Map<String, dynamic> data) async {
    if (_secret.text.trim().length < 16) return 'Mesajı açmak için ortak gizli anahtarı gir.';
    try {
      return await CryptoService.decryptText(payload: data, sharedSecret: _secret.text, conversationId: _conversationId);
    } catch (_) { return 'Şifre çözülemedi: anahtar yanlış olabilir.'; }
  }

  @override
  void dispose() {
    _deleteReadGhostMessages();
    _text.dispose();
    _secret.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('@${widget.peerUsername}'), actions: [
      IconButton(tooltip: 'Sesli arama', onPressed: () => _startCall(audioOnly: true), icon: const Icon(Icons.call)),
      IconButton(tooltip: 'Görüntülü arama', onPressed: () => _startCall(audioOnly: false), icon: const Icon(Icons.videocam)),
    ]),
    body: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 0), child: TextField(
        controller: _secret, obscureText: !_revealed,
        decoration: InputDecoration(labelText: 'Ortak sohbet anahtarı (min. 16 karakter)', border: const OutlineInputBorder(), suffixIcon: IconButton(onPressed: () => setState(() => _revealed = !_revealed), icon: Icon(_revealed ? Icons.visibility_off : Icons.visibility))),
      )),
      SwitchListTile(
        title: const Text('Hayalet mod'),
        subtitle: const Text('Okuduktan sonra bu sohbetten çıkınca silme denemesi. Ekran görüntüsü engellenmez.'),
        value: _ghost, onChanged: (v) => setState(() => _ghost = v),
      ),
      if (_error != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
      Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _messages.orderBy('createdAt').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('Mesajlar yüklenemedi. Firestore kurallarını kontrol et.'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) return const Center(child: Text('İlk mesajı gönder.'));
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final doc = docs[i]; final data = doc.data();
              if (data['senderUid'] != _uid && data['ghost'] == true && !(List<String>.from(data['readBy'] ?? const <String>[]).contains(_uid))) {
                WidgetsBinding.instance.addPostFrameCallback((_) => _markRead(doc));
              }
              final mine = data['senderUid'] == _uid;
              return Align(alignment: mine ? Alignment.centerRight : Alignment.centerLeft, child: Container(
                constraints: const BoxConstraints(maxWidth: 320),
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: mine ? const Color(0xFF174B3D) : const Color(0xFF172238), borderRadius: BorderRadius.circular(16)),
                child: data['kind'] == 'photo' || data['kind'] == 'video'
                    ? AttachmentMessage(message: data, sharedSecret: _secret.text, conversationId: _conversationId)
                    : FutureBuilder<String>(
                        future: _decrypt(data),
                        builder: (_, value) => Text(value.data ?? 'Şifre çözülüyor…'),
                      ),
              ));
            },
          );
        },
      )),
      SafeArea(child: Padding(padding: const EdgeInsets.all(10), child: Row(children: [
        IconButton(tooltip: 'Şifreli fotoğraf/video gönder', onPressed: _busy ? null : _pickAttachment, icon: const Icon(Icons.attach_file)),
        Expanded(child: TextField(controller: _text, minLines: 1, maxLines: 4, decoration: const InputDecoration(hintText: 'Şifreli mesaj yaz…', border: OutlineInputBorder()), onSubmitted: (_) => _send())),
        const SizedBox(width: 8),
        IconButton.filled(onPressed: _busy ? null : _send, icon: const Icon(Icons.send)),
      ]))),
    ]),
  );
}
