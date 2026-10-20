import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'firebase_bootstrap.dart';

/// WebRTC signaling starter. A production release still needs TURN servers,
/// call timeouts, push notifications, and an independent media-security review.
class CallService {
  final String callId;
  final String localUid;
  final String peerUid;
  final bool isCaller;
  final bool audioOnly;
  final void Function(MediaStream stream) onRemoteStream;
  final void Function(String message) onStatus;

  RTCPeerConnection? _peer;
  MediaStream? _local;
  bool _answerApplied = false;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _candidateStream;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  DocumentReference<Map<String, dynamic>> get _call =>
      FirebaseBootstrap.db.collection('calls').doc(callId);

  CallService({
    required this.callId,
    required this.localUid,
    required this.peerUid,
    required this.isCaller,
    required this.audioOnly,
    required this.onRemoteStream,
    required this.onStatus,
  });

  MediaStream? get localStream => _local;

  Future<void> start() async {
    final config = <String, dynamic>{
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    };
    _peer = await createPeerConnection(config);
    _peer!.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      final collection = _call.collection(isCaller ? 'callerCandidates' : 'calleeCandidates');
      collection.add({
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };
    _peer!.onTrack = (event) {
      if (event.streams.isNotEmpty) onRemoteStream(event.streams.first);
    };
    _local = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': audioOnly ? false : {
        'facingMode': 'user',
        'width': {'ideal': 640},
        'height': {'ideal': 480},
      },
    });
    for (final track in _local!.getTracks()) {
      await _peer!.addTrack(track, _local!);
    }

    if (isCaller) {
      await _call.set({
        'callerUid': localUid,
        'calleeUid': peerUid,
        'status': 'preparing',
        'audioOnly': audioOnly,
        'createdAt': FieldValue.serverTimestamp(),
      });
      final offer = await _peer!.createOffer();
      await _peer!.setLocalDescription(offer);
      await _call.update({'offer': {'type': offer.type, 'sdp': offer.sdp}, 'status': 'ringing'});
      _subscriptions.add(_call.snapshots().listen((snapshot) async {
        final data = snapshot.data();
        final answer = data?['answer'];
        if (answer != null && !_answerApplied) {
          try {
            await _peer?.setRemoteDescription(RTCSessionDescription(answer['sdp'], answer['type']));
            _answerApplied = true;
            onStatus('Bağlandı');
          } catch (_) {}
        }
        if (data?['status'] == 'declined' || data?['status'] == 'ended') {
          onStatus('Arama sona erdi');
        }
      }));
      _watchCandidates('calleeCandidates');
    } else {
      final snap = await _call.get();
      final offer = snap.data()?['offer'];
      if (offer == null) throw StateError('Arama teklifi bulunamadı.');
      await _peer!.setRemoteDescription(RTCSessionDescription(offer['sdp'], offer['type']));
      final answer = await _peer!.createAnswer();
      await _peer!.setLocalDescription(answer);
      await _call.update({
        'answer': {'type': answer.type, 'sdp': answer.sdp},
        'status': 'accepted',
      });
      _watchCandidates('callerCandidates');
      onStatus('Bağlanıyor…');
    }
  }

  void _watchCandidates(String collectionName) {
    final sub = _call.collection(collectionName).snapshots().listen((snapshot) async {
      for (final change in snapshot.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final data = change.doc.data();
        if (data == null) continue;
        try {
          await _peer?.addCandidate(RTCIceCandidate(
            data['candidate'] as String?,
            data['sdpMid'] as String?,
            data['sdpMLineIndex'] as int?,
          ));
        } catch (_) {}
      }
    });
    _subscriptions.add(sub);
  }

  Future<void> toggleMicrophone() async {
    for (final track in _local?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !track.enabled;
    }
  }

  Future<void> toggleCamera() async {
    for (final track in _local?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !track.enabled;
    }
  }

  Future<void> end() async {
    try { await _call.update({'status': 'ended'}); } catch (_) {}
    for (final sub in _subscriptions) { await sub.cancel(); }
    await _peer?.close();
    await _local?.dispose();
  }
}
