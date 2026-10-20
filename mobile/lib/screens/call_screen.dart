import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/call_service.dart';
import '../services/firebase_bootstrap.dart';

class CallScreen extends StatefulWidget {
  final String callId;
  final String peerUid;
  final bool isCaller;
  final bool audioOnly;
  const CallScreen({
    super.key,
    required this.callId,
    required this.peerUid,
    required this.isCaller,
    required this.audioOnly,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  CallService? _service;
  bool _micOn = true;
  bool _cameraOn = true;
  bool _starting = true;
  String _status = 'Arama başlatılıyor…';
  String? _error;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final service = CallService(
        callId: widget.callId,
        localUid: uid,
        peerUid: widget.peerUid,
        isCaller: widget.isCaller,
        audioOnly: widget.audioOnly,
        onRemoteStream: (stream) {
          _remoteRenderer.srcObject = stream;
          if (mounted) setState(() {});
        },
        onStatus: (status) {
          if (mounted) setState(() => _status = status);
        },
      );
      _service = service;
      await service.start();
      _localRenderer.srcObject = service.localStream;
      if (mounted) setState(() => _starting = false);
    } catch (e) {
      if (mounted) setState(() { _starting = false; _error = e.toString(); });
    }
  }

  Future<void> _end() async {
    await _service?.end();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _service?.end();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      title: Text(widget.audioOnly ? 'Sesli arama' : 'Görüntülü arama'),
      actions: [IconButton(onPressed: _end, icon: const Icon(Icons.call_end, color: Colors.redAccent))],
    ),
    body: Column(children: [
      Expanded(
        child: Stack(children: [
          Positioned.fill(
            child: widget.audioOnly
              ? const Center(child: Icon(Icons.account_circle, size: 110, color: Colors.white54))
              : RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RFC),
          ),
          if (!widget.audioOnly)
            Positioned(
              right: 16, top: 16, width: 110, height: 160,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: RTCVideoView(_localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RFC),
              ),
            ),
          Positioned(
            left: 16, right: 16, bottom: 20,
            child: Column(children: [
              Text(_status, style: const TextStyle(color: Colors.white, fontSize: 16)),
              if (_starting) const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()),
              if (_error != null) Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ]),
          ),
        ]),
      ),
      SafeArea(child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          IconButton.filledTonal(
            onPressed: () async { await _service?.toggleMicrophone(); setState(() => _micOn = !_micOn); },
            icon: Icon(_micOn ? Icons.mic : Icons.mic_off),
          ),
          if (!widget.audioOnly)
            IconButton.filledTonal(
              onPressed: () async { await _service?.toggleCamera(); setState(() => _cameraOn = !_cameraOn); },
              icon: Icon(_cameraOn ? Icons.videocam : Icons.videocam_off),
            ),
          IconButton.filled(
            style: IconButton.styleFrom(backgroundColor: Colors.red),
            onPressed: _end,
            icon: const Icon(Icons.call_end),
          ),
        ]),
      )),
    ]),
  );
}
