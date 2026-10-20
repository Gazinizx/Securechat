import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../services/crypto_service.dart';
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
  CollectionReference<Map<String, dynamic>> get _messages =>
      FirebaseBootstrap.db.collection('conversations').doc(_conversationId).collection('messages');

  Future<void> _send() async {
    if (_text.text.trim().isEmpty) return;
    if (_secret.text.trim().length < 16) {
      setState(() => _error = 'Sohbet için en az 16 karakterlik ortak gizli anahtar girin ve bunu güvenli kanaldan paylaşın.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
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
    } catch (e) { setState(() => _error = e.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _markRead(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data();
    if (data == null || data['senderUid'] == _uid) return;
    final readBy = List<String>.from(data['readBy'] ?? const <String>[]);
    if (!readBy.contains(_uid)) {
      await doc.reference.update({'readBy': FieldValue.arrayUnion([_uid])});
      if (data['ghost'] == true) {
        // Best-effort cleanup only. A production implementation needs server
        // enforcement, TTL cleanup, and clear UX that screenshots remain possible.
        await doc.reference.delete();
      }
    }
  }

  Future<String> _decrypt(Map<String, dynamic> data) async {
    if (_secret.text.trim().length < 16) return 'Mesajı açmak için ortak gizli anahtarı gir.';
    try {
      return await CryptoService.decryptText(payload: data, sharedSecret: _secret.text, conversationId: _conversationId);
    } catch (_) { return 'Şifre çözülemedi: anahtar yanlış olabilir.'; }
  }

  @override
  void dispose() { _text.dispose(); _secret.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('@${widget.peerUsername}'), actions: [
      IconButton(tooltip: 'Sesli arama (kurulum aşamasında)', onPressed: () => _showCallNotice(context), icon: const Icon(Icons.call)),
      IconButton(tooltip: 'Görüntülü arama (kurulum aşamasında)', onPressed: () => _showCallNotice(context), icon: const Icon(Icons.videocam)),
    ]),
    body: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 0), child: TextField(
        controller: _secret, obscureText: !_revealed,
        decoration: InputDecoration(labelText: 'Ortak sohbet anahtarı (min. 16 karakter)', border: const OutlineInputBorder(), suffixIcon: IconButton(onPressed: () => setState(() => _revealed = !_revealed), icon: Icon(_revealed ? Icons.visibility_off : Icons.visibility))),
      )),
      SwitchListTile(
        title: const Text('Hayalet mod'),
        subtitle: const Text('Okunma sonrası silme denemesi; ekran görüntüsünü engellemez.'),
        value: _ghost, onChanged: (v) => setState(() => _ghost = v),
      ),
      if (_error != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
      Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _messages.orderBy('createdAt').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('Mesajlar yüklenemedi. Firebase kurallarını kontrol et.'));
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
                child: FutureBuilder<String>(
                  future: _decrypt(data),
                  builder: (_, value) => Text(value.data ?? 'Şifre çözülüyor…'),
                ),
              ));
            },
          );
        },
      )),
      SafeArea(child: Padding(padding: const EdgeInsets.all(10), child: Row(children: [
        IconButton(tooltip: 'Fotoğraf/video gönderme altyapısı sıradaki aşamada', onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fotoğraf/video şifreli yükleme modülü sıradaki aşamada eklenecek.'))), icon: const Icon(Icons.attach_file)),
        Expanded(child: TextField(controller: _text, minLines: 1, maxLines: 4, decoration: const InputDecoration(hintText: 'Şifreli mesaj yaz…', border: OutlineInputBorder()), onSubmitted: (_) => _send())),
        const SizedBox(width: 8),
        IconButton.filled(onPressed: _busy ? null : _send, icon: const Icon(Icons.send)),
      ]))),
    ]),
  );

  void _showCallNotice(BuildContext context) => ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Sesli/görüntülü arama arayüzü hazırlandı; WebRTC sinyalleşmesi ve cihaz testleri henüz tamamlanmadı.')),
  );
}
