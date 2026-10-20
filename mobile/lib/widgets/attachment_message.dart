import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import '../services/attachment_service.dart';

class AttachmentMessage extends StatefulWidget {
  final Map<String, dynamic> message;
  final String sharedSecret;
  final String conversationId;
  const AttachmentMessage({
    super.key,
    required this.message,
    required this.sharedSecret,
    required this.conversationId,
  });

  @override
  State<AttachmentMessage> createState() => _AttachmentMessageState();
}

class _AttachmentMessageState extends State<AttachmentMessage> {
  Uint8List? _bytes;
  VideoPlayerController? _video;
  bool _loading = false;
  String? _error;
  String? _filename;

  Future<void> _open() async {
    if (_loading) return;
    setState(() { _loading = true; _error = null; });
    try {
      final name = await AttachmentService.decryptFilename(
        message: widget.message,
        sharedSecret: widget.sharedSecret,
        conversationId: widget.conversationId,
      );
      final bytes = await AttachmentService.decryptAttachment(
        message: widget.message,
        sharedSecret: widget.sharedSecret,
        conversationId: widget.conversationId,
      );
      if (widget.message['kind'] == 'video') {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/securechat_${widget.message['storagePath'].hashCode}.mp4');
        await file.writeAsBytes(bytes, flush: true);
        final controller = VideoPlayerController.file(file);
        await controller.initialize();
        if (!mounted) { await controller.dispose(); return; }
        setState(() { _filename = name; _video = controller; _bytes = bytes; });
      } else {
        setState(() { _filename = name; _bytes = bytes; });
      }
    } catch (_) {
      setState(() => _error = 'Dosya açılamadı. Anahtarı ve Firebase Storage kurallarını kontrol et.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.message['kind'] == 'video';
    if (_bytes == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(isVideo ? Icons.videocam : Icons.image, color: const Color(0xFF69E6B1)),
            const SizedBox(width: 8),
            Flexible(child: Text(isVideo ? 'Şifreli video' : 'Şifreli fotoğraf')),
            IconButton(
              onPressed: _loading ? null : _open,
              icon: _loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download),
            ),
          ]),
          if (_error != null) Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
        ],
      );
    }
    if (isVideo && _video != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_filename ?? 'Video'),
          AspectRatio(
            aspectRatio: _video!.value.aspectRatio,
            child: VideoPlayer(_video!),
          ),
          IconButton(
            onPressed: () => setState(() {
              _video!.value.isPlaying ? _video!.pause() : _video!.play();
            }),
            icon: Icon(_video!.value.isPlaying ? Icons.pause : Icons.play_arrow),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_filename ?? 'Fotoğraf'),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240, maxHeight: 280),
          child: Image.memory(_bytes!, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Text('Bu dosya görüntülenemiyor.')),
        ),
      ],
    );
  }
}
