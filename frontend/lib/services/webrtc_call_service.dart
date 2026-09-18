import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../core/auth/token_storage.dart';
import '../core/network/api_config.dart';
import 'call_sound_service.dart';
import 'speech_service.dart';


enum CallState { idle, initiating, ringing, connected, ended, failed }

class CallSessionInfo {
  final String bookingId;
  final String callSessionId;
  final String peerName;
  final String peerRole;
  final String? peerAvatar;
  final String serviceTitle;

  CallSessionInfo({
    required this.bookingId,
    required this.callSessionId,
    required this.peerName,
    required this.peerRole,
    this.peerAvatar,
    required this.serviceTitle,
  });
}

class WebRTCCallService {
  WebRTCCallService._();
  static final WebRTCCallService instance = WebRTCCallService._();

  /// Dedupe CallKit shows from socket + FCM for same session.
  static final Map<String, int> _recentIncomingCallShows = <String, int>{};

  io.Socket? socket;
  RTCPeerConnection? peerConnection;
  MediaStream? localStream;
  MediaStream? remoteStream;

  CallState currentState = CallState.idle;
  String? currentBookingId;
  String? currentCallSessionId;
  String? currentUserId;
  String? peerUserId;
  String? peerName;
  String? peerRole;
  String? peerAvatar;
  String? serviceTitle;

  bool isMuted = false;
  bool isSpeakerOn = false;
  bool isOutgoing = false;
  bool _cleaning = false;
  bool _remoteDescriptionSet = false;
  dynamic _pendingRemoteOffer;
  final List<RTCIceCandidate> _pendingRemoteCandidates = [];

  int callDurationSeconds = 0;
  Timer? durationTimer;

  final TokenStorage _tokenStorage = TokenStorage();

  Function(CallState state)? onCallStateChanged;
  Function(CallSessionInfo info)? onIncomingCall;
  Function(String message)? onFirewallError;
  Function(String message)? onPeerNetworkIssue;

  String get serverUrl => ApiConfig.baseUrl;

  bool get isInCall =>
      currentState == CallState.initiating ||
      currentState == CallState.ringing ||
      currentState == CallState.connected;

  static String? _normalizeRole(String? raw) {
    final r = (raw ?? '').trim().toLowerCase();
    if (r.contains('customer')) return 'customer';
    if (r.contains('worker')) return 'worker';
    return null;
  }

  /// Stash ids from FCM/CallKit before accept so decline/timeout can notify peer.
  void noteIncomingRing({
    required String bookingId,
    String? callSessionId,
    String? callerName,
    String? callerRole,
    String? callerAvatar,
    String? serviceTitleParam,
  }) {
    if (bookingId.isEmpty) return;
    currentBookingId = bookingId;
    if (callSessionId != null && callSessionId.isNotEmpty) {
      currentCallSessionId = callSessionId;
    }
    if (callerName != null && callerName.trim().isNotEmpty) {
      peerName = callerName.trim();
    }
    final role = _normalizeRole(callerRole);
    if (role != null) peerRole = role;
    if (callerAvatar != null) peerAvatar = callerAvatar;
    if (serviceTitleParam != null) serviceTitle = serviceTitleParam;
    isOutgoing = false;
  }

  Future<void> initializeSocket({String? token, String? userId}) async {
    final authToken = token ?? await _tokenStorage.accessToken;
    currentUserId = userId ?? await _tokenStorage.userId;

    if (authToken == null || authToken.isEmpty) {
      debugPrint('[WebRTC] Cannot init socket without auth token');
      return;
    }

    if (socket != null && socket!.connected) {
      _registerUserRoom();
      return;
    }

    socket?.disconnect();
    socket?.dispose();

    socket = io.io(
      serverUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setExtraHeaders({'Authorization': 'Bearer $authToken'})
          .build(),
    );

    _bindSocketListeners();

    final connected = Completer<void>();
    socket!.onConnect((_) {
      debugPrint('[WebRTC-Client] ✅ Socket connected! Registering user room.');
      _registerUserRoom();
      if (isInCall && currentBookingId != null && currentBookingId!.isNotEmpty) {
        debugPrint('[WebRTC-Client] 🔄 Socket reconnected during active call. Rejoining booking room: $currentBookingId');
        _joinRoomReady(currentBookingId!);
      }
      if (!connected.isCompleted) connected.complete();
    });
    socket!.onDisconnect((reason) {
      debugPrint('[WebRTC-Client] 🔌 Socket disconnected: $reason');
    });
    socket!.connect();
    try {
      await connected.future.timeout(const Duration(seconds: 5));
    } catch (_) {
      debugPrint('[WebRTC-Client] ⏱️ socket connect timeout — continuing');
    }
  }

  void _registerUserRoom() {
    final uid = currentUserId;
    if (uid == null || uid.isEmpty || socket == null) return;
    debugPrint('[WebRTC-Client] 👤 Emitting webrtc:register for user $uid');
    socket!.emit('webrtc:register', {'userId': uid});
  }

  void _bindSocketListeners() {
    if (socket == null) return;

    socket!.on('webrtc:room-joined', (data) {
      debugPrint(
        '[WebRTC-Client] 🚪 Joined room: ${data['room']} for booking: ${data['bookingId']}',
      );
    });

    socket!.on('webrtc:incoming-call', (data) {
      debugPrint('[WebRTC-Client] 📲 Incoming call event received: $data');
      if (currentState != CallState.idle) {
        debugPrint('[WebRTC-Client] ⚠️ Already in call state $currentState, ignoring duplicate incoming call');
        return;
      }
      currentBookingId = data['bookingId']?.toString();
      currentCallSessionId =
          data['callSessionId']?.toString() ?? currentCallSessionId;
      final caller = Map<String, dynamic>.from(data['caller'] ?? {});
      peerUserId = caller['id']?.toString() ?? peerUserId;
      peerName = caller['name'] ?? 'User';
      peerRole = _normalizeRole(caller['role']?.toString()) ?? 'worker';
      peerAvatar = caller['avatar'];
      serviceTitle = data['serviceTitle'] ?? 'Audio Calling';
      isOutgoing = false;

      _setCallState(CallState.ringing);

      final info = CallSessionInfo(
        bookingId: currentBookingId ?? '',
        callSessionId: currentCallSessionId ?? '',
        peerName: peerName!,
        peerRole: peerRole!,
        peerAvatar: peerAvatar,
        serviceTitle: serviceTitle!,
      );
      onIncomingCall?.call(info);
      // Always show native incoming call heads-up notification with ringtone
      unawaited(_showIncomingCallUi(info));
    });

    socket!.on('webrtc:call-accepted', (data) async {
      if (data != null &&
          data['senderUserId'] != null &&
          currentUserId != null &&
          data['senderUserId'].toString() == currentUserId) {
        return;
      }
      debugPrint('[WebRTC-Client] 🟢 webrtc:call-accepted received: $data');
      _statusPoller?.cancel();
      await _onCallAcceptedByPeer();
    });

    socket!.on('webrtc:peer-ready', (data) async {
      debugPrint('[WebRTC-Client] 👥 webrtc:peer-ready received: $data');
      if (isOutgoing && currentState == CallState.ringing) {
        _statusPoller?.cancel();
        await _onCallAcceptedByPeer();
      }
    });

    socket!.on('webrtc:offer', (data) async {
      if (data != null &&
          data['senderUserId'] != null &&
          currentUserId != null &&
          data['senderUserId'].toString() == currentUserId) {
        return;
      }
      debugPrint('[WebRTC-Client] 📥 Received SDP offer from peer');
      final sdp = data['sdp'];
      if (sdp == null) return;
      if (peerConnection == null) {
        debugPrint('[WebRTC-Client] ⏳ PeerConnection not ready yet, caching remote offer');
        _pendingRemoteOffer = sdp;
        return;
      }
      await _handleRemoteOffer(sdp);
    });

    socket!.on('webrtc:answer', (data) async {
      if (data != null &&
          data['senderUserId'] != null &&
          currentUserId != null &&
          data['senderUserId'].toString() == currentUserId) {
        return;
      }
      debugPrint('[WebRTC-Client] 📥 Received SDP answer from peer');
      if (peerConnection == null || data['sdp'] == null) return;
      if (_remoteDescriptionSet) {
        debugPrint('[WebRTC-Client] ℹ️ Remote answer already processed; ignoring duplicate');
        return;
      }
      try {
        final sdpMap = Map<String, dynamic>.from(data['sdp']);
        await peerConnection!.setRemoteDescription(
          RTCSessionDescription(sdpMap['sdp'], sdpMap['type']),
        );
        _remoteDescriptionSet = true;
        await _flushPendingIce();
        debugPrint('[WebRTC-Client] ✅ Remote description answer set successfully');
      } catch (e) {
        debugPrint('[WebRTC-Client] ❌ Set remote description answer error: $e');
      }
    });

    socket!.on('webrtc:ice-candidate', (data) async {
      if (data != null &&
          data['senderUserId'] != null &&
          currentUserId != null &&
          data['senderUserId'].toString() == currentUserId) {
        return;
      }
      final cand = data['candidate'];
      if (cand == null) return;
      int? mLineIndex;
      final rawIndex = cand['sdpMLineIndex'] ??
          cand['sdpMlineIndex'] ??
          cand['sdpMLineindex'];
      if (rawIndex is int) {
        mLineIndex = rawIndex;
      } else if (rawIndex != null) {
        mLineIndex = int.tryParse(rawIndex.toString());
      }
      final sdpMid = cand['sdpMid']?.toString();
      final candStr = cand['candidate']?.toString();
      if (candStr == null || candStr.isEmpty) return;

      final candidate = RTCIceCandidate(
        candStr,
        sdpMid,
        mLineIndex ?? 0,
      );
      if (peerConnection == null || !_remoteDescriptionSet) {
        _pendingRemoteCandidates.add(candidate);
        return;
      }
      try {
        await peerConnection!.addCandidate(candidate);
        debugPrint('[WebRTC-Client] ❄️ Added ICE candidate successfully');
      } catch (e) {
        debugPrint('[WebRTC-Client] ❌ Add ICE candidate error: $e');
      }
    });

    socket!.on('webrtc:call-rejected', (data) {
      debugPrint('[WebRTC-Client] 🚫 webrtc:call-rejected received: $data');
      _setCallState(CallState.ended);
      unawaited(cleanupCall());
    });

    socket!.on('webrtc:call-ended', (data) {
      debugPrint('[WebRTC-Client] 🛑 webrtc:call-ended received: $data');
      _setCallState(CallState.ended);
      unawaited(cleanupCall());
    });

    socket!.on('webrtc:peer-disconnected', (data) {
      debugPrint('[WebRTC-Client] 📡 webrtc:peer-disconnected received: $data');
      if (isInCall) {
        _setCallState(CallState.ended);
        unawaited(cleanupCall());
      }
    });

    socket!.on('webrtc:error', (error) {
      debugPrint('[WebRTC-Client] ⚠️ webrtc:error received: $error');
      if (error['errorCode'] == 'FIREWALL_BLOCKED_WIFI_RESTRICTION') {
        _setCallState(CallState.failed);
        onFirewallError?.call(
          error['message'] ?? 'Wi-Fi firewall blocking audio call.',
        );
      }
    });

    socket!.on('webrtc:peer-network-issue', (data) {
      debugPrint('[WebRTC-Client] ⚠️ webrtc:peer-network-issue: $data');
      onPeerNetworkIssue?.call(
        data['message'] ?? 'Peer having firewall/network difficulties.',
      );
    });
  }

  Timer? _statusPoller;

  void _startRingingStatusPoller(String bookingId, String authToken) {
    _statusPoller?.cancel();
    _statusPoller = Timer.periodic(const Duration(milliseconds: 1200), (timer) async {
      if (currentState != CallState.ringing) {
        timer.cancel();
        return;
      }
      try {
        final res = await http.get(
          Uri.parse('$serverUrl/api/webrtc/call/status/$bookingId'),
          headers: {'Authorization': 'Bearer $authToken'},
        );
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data['status'] == 'CONNECTED') {
            debugPrint('[WebRTC-Client] ⚡ Poller detected call status CONNECTED via REST!');
            timer.cancel();
            await _onCallAcceptedByPeer();
          }
        }
      } catch (e) {
        debugPrint('[WebRTC-Client] Status poll error: $e');
      }
    });
  }

  Future<void> _onCallAcceptedByPeer() async {
    if (currentState == CallState.connected) return;
    _statusPoller?.cancel();
    _setCallState(CallState.connected);
    _startDurationTimer();
    await _sendOffer();
  }

  Future<void> _sendOffer() async {
    if (peerConnection == null) return;
    try {
      final offer = await peerConnection!.createOffer({
        'mandatory': {
          'OfferToReceiveAudio': true,
          'OfferToReceiveVideo': false,
        },
        'optional': [],
      });
      await peerConnection!.setLocalDescription(offer);

      void emitOffer() {
        if (peerConnection != null && !_remoteDescriptionSet && currentState == CallState.connected) {
          socket?.emit('webrtc:offer', {
            'bookingId': currentBookingId,
            'targetUserId': peerUserId,
            'senderUserId': currentUserId,
            'sdp': offer.toMap(),
          });
          debugPrint('[WebRTC-Client] 📤 SDP offer emitted (audio=true, peer=$peerUserId)');
        }
      }

      emitOffer();
      Future.delayed(const Duration(milliseconds: 1500), emitOffer);
      Future.delayed(const Duration(milliseconds: 3000), emitOffer);
    } catch (e) {
      debugPrint('[WebRTC-Client] ❌ Create offer error: $e');
    }
  }

  Future<void> _handleRemoteOffer(dynamic sdpData) async {
    if (peerConnection == null) return;
    if (_remoteDescriptionSet) {
      debugPrint('[WebRTC-Client] ℹ️ Remote offer already processed; ignoring duplicate');
      return;
    }
    try {
      final sdpMap = Map<String, dynamic>.from(sdpData);
      await peerConnection!.setRemoteDescription(
        RTCSessionDescription(sdpMap['sdp'], sdpMap['type']),
      );
      _remoteDescriptionSet = true;
      await _flushPendingIce();

      final answer = await peerConnection!.createAnswer({
        'mandatory': {
          'OfferToReceiveAudio': true,
          'OfferToReceiveVideo': false,
        },
        'optional': [],
      });
      await peerConnection!.setLocalDescription(answer);

      void emitAnswer() {
        socket?.emit('webrtc:answer', {
          'bookingId': currentBookingId,
          'targetUserId': peerUserId,
          'senderUserId': currentUserId,
          'sdp': answer.toMap(),
        });
        debugPrint('[WebRTC-Client] 📤 SDP answer emitted (audio=true, peer=$peerUserId)');
      }

      emitAnswer();
      Future.delayed(const Duration(milliseconds: 1500), emitAnswer);
    } catch (e) {
      debugPrint('[WebRTC-Client] ❌ Handle remote offer error: $e');
    }
  }

  Future<void> _showIncomingCallUi(CallSessionInfo info) async {
    if (info.bookingId.isEmpty) return;
    final dedupeKey = info.callSessionId.isNotEmpty
        ? info.callSessionId
        : info.bookingId;
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _recentIncomingCallShows[dedupeKey];
    if (last != null && now - last < 15000) return;
    _recentIncomingCallShows[dedupeKey] = now;

    try {
      final isCustomerCaller = info.peerRole == 'customer';
      await FlutterCallkitIncoming.showCallkitIncoming(
        CallKitParams(
          id: info.callSessionId.isNotEmpty
              ? info.callSessionId
              : 'call_${info.bookingId}_${DateTime.now().millisecondsSinceEpoch}',
          nameCaller: info.peerName,
          appName: 'Fixly',
          avatar: info.peerAvatar,
          handle: isCustomerCaller
              ? 'Customer is calling'
              : 'Worker is calling',
          type: 0,
          duration: 30000,
          extra: <String, dynamic>{
            'bookingId': info.bookingId,
            'callerRole': info.peerRole,
            'callerId': peerUserId,
            'serviceTitle': info.serviceTitle,
            'callerName': info.peerName,
            'callerAvatar': info.peerAvatar,
          },
          android: const AndroidParams(
            isCustomNotification: true,
            isShowLogo: false,
            ringtonePath: 'system_ringtone_default',
            backgroundColor: '#0F172A',
            actionColor: '#10B981',
            textAccept: 'Accept',
            textDecline: 'Decline',
          ),
          ios: const IOSParams(
            iconName: 'AppIcon',
            handleType: 'generic',
            supportsVideo: false,
            maximumCallGroups: 1,
            maximumCallsPerCallGroup: 1,
            audioSessionMode: 'voiceChat',
            audioSessionActive: true,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[WebRTC] showIncomingCallUi error: $e');
    }
  }

  Future<void> _joinRoomReady(String bookingId) async {
    if (socket == null) return;
    final done = Completer<void>();
    void handler(dynamic data) {
      if (!done.isCompleted) done.complete();
    }

    socket!.once('webrtc:room-joined', handler);
    socket!.emit('webrtc:join-room', {
      'bookingId': bookingId,
      'userId': currentUserId,
    });
    try {
      await done.future.timeout(const Duration(seconds: 4));
    } catch (_) {
      debugPrint('[WebRTC] join-room ack timeout — continuing');
    }
  }

  Future<void> _configureAudioSession() async {
    try {
      // Disengage STT / TTS microphone listeners so WebRTC gets exclusive VoIP mic focus
      try {
        SpeechService().stopListening();
        SpeechService().stopSpeaking();
      } catch (_) {}

      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.allowBluetooth |
            AVAudioSessionCategoryOptions.defaultToSpeaker,
        avAudioSessionMode: AVAudioSessionMode.voiceChat,
        avAudioSessionRouteSharingPolicy:
            AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          flags: AndroidAudioFlags.none,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransient,
        androidWillPauseWhenDucked: true,
      ));
      await session.setActive(true);

      if (Platform.isAndroid) {
        await Helper.setAndroidAudioConfiguration(
          AndroidAudioConfiguration.communication,
        );
      }
      await Helper.setSpeakerphoneOn(isSpeakerOn);
      debugPrint('[WebRTC] 🎙️ AudioSession configured in communication mode (speaker=$isSpeakerOn)');
    } catch (e) {
      debugPrint('[WebRTC] Audio session config error: $e');
    }
  }

  Future<void> _createPeerWithLocalAudio({
    required List<dynamic> iceServers,
    required String bookingId,
  }) async {
    await _configureAudioSession();

    peerConnection = await createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    });
    _remoteDescriptionSet = false;
    _pendingRemoteCandidates.clear();

    localStream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    });

    for (final track in localStream!.getTracks()) {
      await peerConnection!.addTrack(track, localStream!);
    }

    for (final track in localStream!.getAudioTracks()) {
      track.enabled = true;
    }

    try {
      final transceivers = await peerConnection!.getTransceivers();
      for (final transceiver in transceivers) {
        if (transceiver.receiver.track?.kind == 'audio' ||
            transceiver.sender.track?.kind == 'audio') {
          await transceiver.setDirection(TransceiverDirection.SendRecv);
        }
      }
    } catch (e) {
      debugPrint('[WebRTC-Client] Transceiver direction setup error: $e');
    }

    peerConnection!.onAddStream = (MediaStream stream) {
      debugPrint('[WebRTC-Client] 🎵 onAddStream id=${stream.id}, tracks=${stream.getTracks().length}');
      remoteStream = stream;
      for (final track in remoteStream!.getAudioTracks()) {
        track.enabled = true;
      }
      unawaited(_applySpeakerRoute());
      onCallStateChanged?.call(currentState);
    };

    // Critical: without onTrack, remote audio never plays.
    peerConnection!.onTrack = (RTCTrackEvent event) {
      debugPrint('[WebRTC-Client] 🎵 onTrack kind=${event.track.kind}');
      if (event.track.kind == 'audio') {
        event.track.enabled = true;
      }
      if (event.streams.isNotEmpty) {
        remoteStream = event.streams.first;
        for (final track in remoteStream!.getAudioTracks()) {
          track.enabled = true;
        }
      }
      // Re-assert communication audio mode and speaker state
      unawaited(_applySpeakerRoute());
      onCallStateChanged?.call(currentState);
    };

    peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      debugPrint('[WebRTC-Client] 🔄 Peer Connection State: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        unawaited(_applySpeakerRoute());
        _startDurationTimer();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        debugPrint('[WebRTC-Client] ⚠️ Peer connection lost/closed ($state). Terminating call.');
        if (isInCall) {
          _setCallState(CallState.ended);
          unawaited(cleanupCall());
        }
      }
    };

    peerConnection!.onIceCandidate = (candidate) {
      if (candidate.candidate == null || candidate.candidate!.isEmpty) return;
      debugPrint('[WebRTC-Client] ❄️ Local ICE candidate generated');
      socket?.emit('webrtc:ice-candidate', {
        'bookingId': bookingId,
        'targetUserId': peerUserId,
        'senderUserId': currentUserId,
        'candidate': candidate.toMap(),
      });
    };

    peerConnection!.onIceConnectionState = (state) async {
      debugPrint('[WebRTC-Client] ❄️ ICE Connection State: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _setCallState(CallState.connected);
        unawaited(_applySpeakerRoute());
        // Media now flowing → begin counting talk time (idempotent).
        _startDurationTimer();
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
        debugPrint('[WebRTC-Client] ⚠️ ICE connection disconnected/closed ($state).');
        Future.delayed(const Duration(seconds: 4), () {
          if (peerConnection != null &&
              (peerConnection!.iceConnectionState ==
                      RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
                  peerConnection!.iceConnectionState ==
                      RTCIceConnectionState.RTCIceConnectionStateClosed)) {
            if (isInCall) {
              debugPrint('[WebRTC-Client] 🛑 ICE failed to recover after 4s. Ending call.');
              _setCallState(CallState.ended);
              unawaited(cleanupCall());
            }
          }
        });
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        final connectivityList = await Connectivity().checkConnectivity();
        final isWifi = connectivityList.contains(ConnectivityResult.wifi);

        socket?.emit('webrtc:ice-failed', {
          'bookingId': bookingId,
          'networkType': isWifi ? 'wifi' : 'cellular',
          'iceState': 'failed',
        });

        if (isWifi && isOutgoing) {
          _setCallState(CallState.failed);
          onFirewallError?.call(
            'Aapke Wi-Fi network ya router firewall ne audio call ports block kar diye hain. Kripya apna Wi-Fi band karke mobile data chalu karein aur call dobara lagayein.',
          );
        }
      }
    };
  }


  Future<void> _flushPendingIce() async {
    if (peerConnection == null) return;
    final pending = List<RTCIceCandidate>.from(_pendingRemoteCandidates);
    _pendingRemoteCandidates.clear();
    for (final candidate in pending) {
      try {
        await peerConnection!.addCandidate(candidate);
      } catch (e) {
        debugPrint('[WebRTC] Flush ICE candidate error: $e');
      }
    }
  }

  Future<List<dynamic>> _fetchIceServers(String authToken) async {
    try {
      final iceRes = await http.get(
        Uri.parse('$serverUrl/api/webrtc/config/ice-servers'),
        headers: {'Authorization': 'Bearer $authToken'},
      );
      final iceData = jsonDecode(iceRes.body);
      final list = iceData['iceServers'] as List<dynamic>?;
      if (list != null && list.isNotEmpty) return list;
    } catch (e) {
      debugPrint('[WebRTC] ICE servers fetch failed: $e');
    }
    return [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {'urls': 'stun:stun3.l.google.com:19302'},
      {'urls': 'stun:stun4.l.google.com:19302'},
      {'urls': 'stun:stun.services.mozilla.com'},
      {'urls': 'stun:stun.cloudflare.com:3478'},
      {
        'urls': [
          'turn:openrelay.metered.ca:80',
          'turn:openrelay.metered.ca:443',
          'turn:openrelay.metered.ca:443?transport=tcp',
          'turns:openrelay.metered.ca:443?transport=tcp',
          'turns:openrelay.metered.ca:5349',
          'turns:openrelay.metered.ca:5349?transport=tcp',
        ],
        'username': 'openrelay',
        'credential': 'openrelay',
      },
    ];
  }

  Future<bool> startCall({
    required String bookingId,
    String? token,
    String? expectedPeerName,
    String? expectedPeerRole,
    String? expectedPeerAvatar,
    String? expectedServiceTitle,
  }) async {
    if (isInCall) {
      debugPrint('[WebRTC] Already in a call');
      return false;
    }

    // Clean up any lingering previous peer/stream before establishing new one
    if (peerConnection != null) {
      try {
        await peerConnection?.close();
        await peerConnection?.dispose();
      } catch (_) {}
      peerConnection = null;
    }
    if (localStream != null) {
      try {
        localStream?.getTracks().forEach((track) => track.stop());
        await localStream?.dispose();
      } catch (_) {}
      localStream = null;
    }

    currentBookingId = bookingId;
    peerName = expectedPeerName ?? 'User';
    peerRole = _normalizeRole(expectedPeerRole) ?? 'participant';
    peerAvatar = expectedPeerAvatar;
    serviceTitle = expectedServiceTitle ?? 'Audio Calling';
    isMuted = false;
    isSpeakerOn = true;
    isOutgoing = true;
    callDurationSeconds = 0;

    _setCallState(CallState.initiating);

    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      status = await Permission.microphone.request();
    }
    if (!status.isGranted) {
      _setCallState(CallState.failed);
      await cleanupCall();
      return false;
    }

    try {
      final authToken = token ?? await _tokenStorage.accessToken;
      if (authToken == null || authToken.isEmpty) {
        _setCallState(CallState.failed);
        await cleanupCall();
        return false;
      }

      await initializeSocket(token: authToken);

      final initRes = await http.post(
        Uri.parse('$serverUrl/api/webrtc/call/initiate'),
        headers: {
          'Authorization': 'Bearer $authToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'bookingId': bookingId}),
      );

      final initData = jsonDecode(initRes.body);
      if (initRes.statusCode != 200 || initData['success'] != true) {
        debugPrint('[WebRTC] Initiate call API failed: ${initRes.body}');
        _setCallState(CallState.failed);
        await cleanupCall();
        return false;
      }

      currentCallSessionId = initData['callSessionId']?.toString();
      final receiver = initData['receiver'] ?? {};
      peerUserId = receiver['id']?.toString() ?? peerUserId;
      peerName = receiver['name']?.toString() ?? peerName;
      peerRole = _normalizeRole(receiver['role']?.toString()) ?? peerRole;
      peerAvatar = receiver['avatar']?.toString() ?? peerAvatar;
      serviceTitle = initData['serviceTitle']?.toString() ?? serviceTitle;

      final iceServers = await _fetchIceServers(authToken);
      await _createPeerWithLocalAudio(
        iceServers: iceServers,
        bookingId: bookingId,
      );

      await _joinRoomReady(bookingId);

      socket?.emit('webrtc:call-initiate', {
        'bookingId': bookingId,
        'callerId': currentUserId,
        'callerRole': initData['caller']?['role'],
        'callerName': initData['caller']?['name'],
        'callerAvatar': initData['caller']?['avatar'],
        'receiverId': receiver['id']?.toString(),
        'callSessionId': currentCallSessionId,
        'serviceTitle': serviceTitle,
      });

      isSpeakerOn = true;
      unawaited(_applySpeakerRoute());
      _setCallState(CallState.ringing);
      _startRingingStatusPoller(bookingId, authToken);
      return true;
    } catch (e) {
      debugPrint('[WebRTC] Start call exception: $e');
      _setCallState(CallState.failed);
      await cleanupCall();
      return false;
    }
  }

  Future<bool> acceptCall({
    required String bookingId,
    String? token,
    String? callerName,
    String? callerRole,
    String? callerAvatar,
    String? serviceTitleParam,
    String? callSessionId,
    String? callerId,
  }) async {
    if (currentState == CallState.connected && currentBookingId == bookingId) {
      debugPrint('[WebRTC-Client] Already connected to booking: $bookingId');
      return true;
    }

    // Clean up any lingering previous peer/stream before establishing new one
    if (peerConnection != null) {
      try {
        await peerConnection?.close();
        await peerConnection?.dispose();
      } catch (_) {}
      peerConnection = null;
    }
    if (localStream != null) {
      try {
        localStream?.getTracks().forEach((track) => track.stop());
        await localStream?.dispose();
      } catch (_) {}
      localStream = null;
    }

    currentBookingId = bookingId;
    if (callSessionId != null && callSessionId.isNotEmpty) {
      currentCallSessionId = callSessionId;
    }
    if (callerId != null && callerId.isNotEmpty) {
      peerUserId = callerId;
    }
    if (callerName != null && callerName.trim().isNotEmpty) {
      peerName = callerName.trim();
    }
    final normalizedRole = _normalizeRole(callerRole);
    if (normalizedRole != null) peerRole = normalizedRole;
    if (callerAvatar != null) peerAvatar = callerAvatar;
    if (serviceTitleParam != null) serviceTitle = serviceTitleParam;
    isMuted = false;
    isSpeakerOn = true;
    isOutgoing = false;
    callDurationSeconds = 0;

    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      status = await Permission.microphone.request();
    }
    if (!status.isGranted) {
      _setCallState(CallState.failed);
      await cleanupCall();
      return false;
    }

    try {
      final authToken = token ?? await _tokenStorage.accessToken;
      if (authToken == null || authToken.isEmpty) {
        _setCallState(CallState.failed);
        await cleanupCall();
        return false;
      }

      await initializeSocket(token: authToken);

      final iceServers = await _fetchIceServers(authToken);
      await _createPeerWithLocalAudio(
        iceServers: iceServers,
        bookingId: bookingId,
      );

      // If remote offer arrived while creating peer, process it immediately!
      if (_pendingRemoteOffer != null) {
        debugPrint('[WebRTC-Client] ⚡ Processing cached remote offer now');
        final sdp = _pendingRemoteOffer;
        _pendingRemoteOffer = null;
        unawaited(_handleRemoteOffer(sdp));
      }

      await _joinRoomReady(bookingId);

      socket?.emit('webrtc:call-accept', {
        'bookingId': bookingId,
        'receiverId': currentUserId,
        'targetUserId': peerUserId,
      });
      socket?.emit('webrtc:peer-ready', {
        'bookingId': bookingId,
        'userId': currentUserId,
      });

      // REST Accept Fallback: Guarantees status update across AWS ALB and triggers caller
      unawaited(() async {
        try {
          final res = await http.post(
            Uri.parse('$serverUrl/api/webrtc/call/accept'),
            headers: {
              'Authorization': 'Bearer $authToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'bookingId': bookingId}),
          );
          debugPrint('[WebRTC-Client] 🌐 POST /api/webrtc/call/accept status: ${res.statusCode}');
        } catch (err) {
          debugPrint('[WebRTC-Client] ⚠️ POST /api/webrtc/call/accept error: $err');
        }
      }());

      unawaited(_applySpeakerRoute());

      _setCallState(CallState.connected);
      _startDurationTimer();
      return true;
    } catch (e) {
      debugPrint('[WebRTC] Accept call error: $e');
      _setCallState(CallState.failed);
      await cleanupCall();
      return false;
    }
  }

  void rejectCall({
    String? reason,
    String? bookingId,
    String? callSessionId,
  }) {
    if (_cleaning) return;
    final id = bookingId ?? currentBookingId;
    if (callSessionId != null && callSessionId.isNotEmpty) {
      currentCallSessionId = callSessionId;
    }
    debugPrint(
      '[WebRTC-Client] 🚫 rejectCall triggered for bookingId: $id, reason: $reason',
    );

    if (id != null && id.isNotEmpty) {
      currentBookingId = id;
      unawaited(() async {
        try {
          await initializeSocket();
          socket?.emit('webrtc:call-reject', {
            'bookingId': id,
            'reason': reason ?? 'DECLINED',
            'callSessionId': currentCallSessionId,
          });
          debugPrint('[WebRTC-Client] 📤 webrtc:call-reject emitted over socket');
        } catch (e) {
          debugPrint('[WebRTC-Client] ⚠️ reject emit failed: $e');
        }

        // Fire REST API hangup as fallback as well
        try {
          final token = await _tokenStorage.accessToken;
          if (token != null && token.isNotEmpty) {
            await http.post(
              Uri.parse('$serverUrl/api/webrtc/call/hangup'),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'bookingId': id,
                'endReason': reason ?? 'DECLINED',
                'durationSeconds': 0,
              }),
            );
            debugPrint('[WebRTC-Client] 🌐 POST /api/webrtc/call/hangup fired for rejection');
          }
        } catch (_) {}

        _setCallState(CallState.ended);
        await cleanupCall();
      }());
      return;
    }
    debugPrint('[WebRTC-Client] ⚠️ rejectCall missing bookingId — cannot notify peer');
    _setCallState(CallState.ended);
    unawaited(cleanupCall());
  }

  /// Peer declined / CANCEL_CALL — end local UI without re-emitting hangup.
  void endFromRemoteCancel() {
    debugPrint('[WebRTC-Client] 📴 endFromRemoteCancel triggered');
    if (_cleaning || currentState == CallState.idle) {
      unawaited(_endNativeCallUi());
      return;
    }
    _setCallState(CallState.ended);
    unawaited(cleanupCall());
  }

  void hangUp({String? bookingIdParam, String? endReason}) {
    if (_cleaning || currentState == CallState.idle) {
      unawaited(_endNativeCallUi());
      return;
    }
    final bookingId = bookingIdParam ?? currentBookingId;
    debugPrint(
      '[WebRTC-Client] 🛑 hangUp triggered for bookingId: $bookingId, state: $currentState, reason: $endReason',
    );

    if (bookingId != null && bookingId.isNotEmpty) {
      try {
        socket?.emit('webrtc:call-hangup', {
          'bookingId': bookingId,
          'endedBy': currentUserId,
          'durationSeconds': callDurationSeconds,
          'endReason': endReason ?? 'NORMAL_HANGUP',
        });
        debugPrint('[WebRTC-Client] 📤 webrtc:call-hangup emitted over socket');
      } catch (e) {
        debugPrint('[WebRTC-Client] ⚠️ Socket hangup emit error: $e');
      }

      // REST fallback for 100% reliable two-way termination
      unawaited(() async {
        try {
          final token = await _tokenStorage.accessToken;
          if (token != null && token.isNotEmpty) {
            final res = await http.post(
              Uri.parse('$serverUrl/api/webrtc/call/hangup'),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'bookingId': bookingId,
                'endReason': endReason ?? 'NORMAL_HANGUP',
                'durationSeconds': callDurationSeconds,
              }),
            );
            debugPrint(
              '[WebRTC-Client] 🌐 POST /api/webrtc/call/hangup returned status: ${res.statusCode}',
            );
          }
        } catch (httpErr) {
          debugPrint('[WebRTC-Client] ⚠️ POST /api/webrtc/call/hangup error: $httpErr');
        }
      }());
    }

    _setCallState(CallState.ended);
    unawaited(cleanupCall());
  }

  void toggleMute() {
    isMuted = !isMuted;
    localStream?.getAudioTracks().forEach((track) {
      track.enabled = !isMuted;
    });
    onCallStateChanged?.call(currentState);
  }

  void toggleSpeaker() {
    isSpeakerOn = !isSpeakerOn;
    unawaited(_applySpeakerRoute());
    onCallStateChanged?.call(currentState);
  }

  Future<void> _applySpeakerRoute() async {
    try {
      if (Platform.isAndroid) {
        await Helper.setAndroidAudioConfiguration(
          AndroidAudioConfiguration.communication,
        );
      }
      await Helper.setSpeakerphoneOn(isSpeakerOn);
      debugPrint('[WebRTC] 🔊 Speakerphone set to: $isSpeakerOn');
    } catch (e) {
      debugPrint('[WebRTC] setSpeaker error: $e');
    }
  }

  Future<void> cleanupCall() async {
    if (_cleaning) return;
    _cleaning = true;
    try {
      unawaited(CallSoundService.instance.stop());
      _statusPoller?.cancel();
      _statusPoller = null;
      durationTimer?.cancel();
      durationTimer = null;
      callDurationSeconds = 0;
      isOutgoing = false;
      isMuted = false;
      isSpeakerOn = false;
      _remoteDescriptionSet = false;
      _pendingRemoteCandidates.clear();
      _pendingRemoteOffer = null;
      peerUserId = null;

      try {
        localStream?.getTracks().forEach((track) => track.stop());
        await localStream?.dispose();
      } catch (_) {}
      localStream = null;

      try {
        remoteStream?.getTracks().forEach((track) => track.stop());
        await remoteStream?.dispose();
      } catch (_) {}
      remoteStream = null;

      try {
        await peerConnection?.close();
        await peerConnection?.dispose();
      } catch (_) {}
      peerConnection = null;

      try {
        final session = await AudioSession.instance;
        await session.setActive(false);
      } catch (_) {}

      await _endNativeCallUi();

      currentBookingId = null;
      currentCallSessionId = null;
      // Return to idle without re-notifying UI (already got ended/failed).
      currentState = CallState.idle;
    } finally {
      _cleaning = false;
    }
  }

  Future<void> _endNativeCallUi() async {
    try {
      final sessionId = currentCallSessionId;
      if (sessionId != null && sessionId.isNotEmpty) {
        await FlutterCallkitIncoming.endCall(sessionId);
      }
      await FlutterCallkitIncoming.endAllCalls();
    } catch (e) {
      debugPrint('[WebRTC] endCallkit error: $e');
    }
  }

  void _startDurationTimer() {
    // First media-connect wins; ignore later ICE reconnect events.
    if (durationTimer != null) return;
    durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      callDurationSeconds++;
      onCallStateChanged?.call(currentState);
    });
  }

  void _setCallState(CallState state) {
    currentState = state;
    _syncCallSounds(state);
    onCallStateChanged?.call(state);
  }

  void _syncCallSounds(CallState state) {
    switch (state) {
      case CallState.initiating:
        unawaited(CallSoundService.instance.playCalling());
        break;
      case CallState.ringing:
        if (isOutgoing) {
          unawaited(CallSoundService.instance.playCalling());
        } else {
          unawaited(CallSoundService.instance.playRingtone());
        }
        break;
      case CallState.connected:
        unawaited(() async {
          await CallSoundService.instance.stop();
          await _applySpeakerRoute();
        }());
        break;
      case CallState.ended:
      case CallState.failed:
      case CallState.idle:
        unawaited(CallSoundService.instance.stop());
        break;
    }
  }
}
