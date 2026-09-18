import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
// url_launcher removed — AI chat never opens tel: dialer; use in-app WebRTC.

import '../../../../app/router/route_names.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/l10n/locale_scope.dart';
import '../../../../core/location/app_location.dart';
import '../../../../core/navigation/customer_navigation.dart';
import '../../../../core/utils/toast_utils.dart';
import '../../../../services/gemini_live_service.dart';
import '../../../../services/live_pcm_capture.dart';
import '../../../../services/live_pcm_player.dart';
import '../../../../services/live_voice_output.dart';
import '../../../../services/speech_service.dart';
import '../../../../services/webrtc_call_service.dart';
import '../../../ai/data/ai_api_repository.dart';
import '../../../ai/data/ai_app_actions.dart';
import '../../../ai/presentation/widgets/ai_thinking_dots.dart';
import '../../../ai/presentation/widgets/fixly_live_orb.dart';
// TEMP test: siri_orb package commented — swap FixlyLiveOrb back later.
// import 'package:siri_orb/siri_orb.dart';
// import 'package:siri_orb/basic_orb.dart';
import '../../../ai/presentation/widgets/siri_glow_frame.dart';
import '../../../auth/presentation/cubit/app_session_cubit.dart';
import '../../../bookings/data/bookings_api_repository.dart';
import '../../../../shared/models/models.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../services/live_ui_sounds.dart';

enum LiveVoiceState { listening, thinking, speaking, paused }

class _ChatMessage {
  const _ChatMessage({
    required this.isBot,
    required this.text,
    required this.timestamp,
    this.loading = false,
    this.action,
    this.booking,
    this.bookings = const [],
    this.workers = const [],
    this.estimate,
    this.policy,
    this.category,
    this.imagePath,
    this.appActions = const [],
    this.isNew = false,
  });

  final bool isBot;
  final String text;
  final DateTime timestamp;
  final bool loading;
  final String? action;
  final Map<String, dynamic>? booking;
  final List<dynamic> bookings;
  final List<dynamic> workers;
  final Map<String, dynamic>? estimate;
  final Map<String, dynamic>? policy;
  final String? category;
  final String? imagePath;
  final List<AiAppAction> appActions;
  final bool isNew;
}

/// Character-by-character typewriter text animation without a cursor.
class _TypewriterText extends StatefulWidget {
  const _TypewriterText({
    required this.text,
    required this.style,
  });

  final String text;
  final TextStyle style;
  static const Duration _typingSpeed = Duration(milliseconds: 22);

  @override
  State<_TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<_TypewriterText> {
  int _charIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTyping();
  }

  void _startTyping() {
    if (widget.text.isEmpty) return;
    _charIndex = 0;
    _timer = Timer.periodic(_TypewriterText._typingSpeed, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_charIndex < widget.text.length) {
        setState(() {
          _charIndex++;
        });
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void didUpdateWidget(covariant _TypewriterText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _timer?.cancel();
      _startTyping();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayText =
        widget.text.substring(0, _charIndex.clamp(0, widget.text.length));
    return Text(
      displayText,
      style: widget.style,
    );
  }
}

class CustomerAiHelperPage extends StatefulWidget {
  const CustomerAiHelperPage({
    super.key,
    this.startInLiveMode = false,
    this.initialQuery,
  });

  /// When true (Hey Fixly FAB), open straight into Siri-style live voice.
  final bool startInLiveMode;
  final String? initialQuery;

  @override
  State<CustomerAiHelperPage> createState() => _CustomerAiHelperPageState();
}

class _CustomerAiHelperPageState extends State<CustomerAiHelperPage> {
  final _queryController = TextEditingController();
  final _scrollController = ScrollController();
  final _picker = ImagePicker();
  final _speechService = SpeechService();
  final _liveService = GeminiLiveService();
  final _liveCapture = LivePcmCapture();
  final _livePlayer = LivePcmPlayer();
  late final LiveVoiceOutputController _voiceOut = LiveVoiceOutputController(
    player: _livePlayer,
    speech: _speechService,
    live: _liveService,
  );
  final _aiRepo = AiApiRepository();
  final _bookingsRepo = BookingsApiRepository();

  final _messages = <_ChatMessage>[];
  Map<String, dynamic> _conversationState = {};
  bool _awaitingReply = false;
  bool _isDictating = false;

  /// App locales only (LocaleScope.supportedLocales).
  String _selectedLanguage = 'en';

  // --- Dynamic AI Suggested Replies ---
  List<String> _suggestedReplies = [];

  // --- Live Voice Talking Mode ---
  bool _isLiveMode = false;
  /// True when Gemini Live PCM path active (no STT click loop).
  bool _livePcmActive = false;
  LiveVoiceState _liveVoiceState = LiveVoiceState.paused;
  String _liveSpokenText = '';
  String _liveModelDraft = '';
  bool _liveBridgeReady = false;
  /// Chat speaker uses Gemini Live speak-only (same Leda voice as live mode).
  bool _chatGeminiSpeak = false;
  Future<void>? _bridgeConnectInFlight;
  Future<void>? _chatSpeakInFlight;
  /// Local barge-in: need strong voice for ~450ms (ignore soft echo).
  int _bargeHoldMs = 0;
  static const _bargeRmsThreshold = 0.62;
  static const _bargeHoldNeedMs = 500;
  /// Endpointer: after user speech, 4s quiet → hit API. Speak again → cancel.
  Timer? _utteranceCommitTimer;
  bool _hadSpeechInUtterance = false;
  static const _silenceCommitGap = Duration(milliseconds: 2000); // 2s natural silence commit
  bool _liveVoiceFallback = false;
  Timer? _liveReconnectTimer;
  String _liveUserDraft = '';
  /// Greeting only after Live + PCM player + capture ready.
  bool _pendingLiveGreeting = false;
  bool _liveGreetingDone = false;
  bool _isStartingLiveMode = false;
  DateTime? _lastListeningStartedAt;
  /// One utterance → one brain (Live tool OR chat, never both).
  String? _lastHandledUtteranceNorm;
  DateTime? _lastHandledUtteranceAt;
  /// Monotonically increasing ID — incremented on each new STT session.
  /// Callbacks capture the ID at creation time and check before acting,
  /// ensuring stale callbacks from old sessions are silently ignored.
  int _sttSessionId = 0;
  OverlayEntry? _glowOverlayEntry;
  final ValueNotifier<double> _voiceActivityNotifier = ValueNotifier<double>(0.0);
  // TEMP: siri_orb OrbController commented while testing FixlyLiveOrb GIF.
  // late final OrbController _orbController = OrbController(initialAmplitude: 0.15);

  /// After AI creates a booking: poll until worker accepts (no auto-track).
  Timer? _bookingAcceptPoll;
  String? _polledBookingId;
  bool _workerAccepted = false;
  String? _acceptedWorkerName;

  static const _langLabels = <String, String>{
    'en': 'EN',
    'hi': 'हिन्दी',
    'ta': 'தமிழ்',
    'te': 'తెలుగు',
    'kn': 'ಕನ್ನಡ',
    'bn': 'বাংলা',
    'mr': 'मराठी',
    'gu': 'ગુજરાતી',
    'pa': 'ਪੰਜਾਬੀ',
  };

  @override
  void initState() {
    super.initState();
    _speechService.initialize();

    // App locale first; only supported Fixly locales.
    final appLocale = context.read<AppSessionCubit>().state.locale;
    _selectedLanguage = _normalizeLang(appLocale);
    _conversationState['language'] = _selectedLanguage;

    _initConversation();

    AiHelperQueryDispatcher.pendingQuery.addListener(_onDispatchedAiQuery);

    if (AppConstants.voiceAiEnabled && widget.startInLiveMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startLiveMode();
      });
    }

    final initialDispatched = AiHelperQueryDispatcher.pendingQuery.value;
    final startingQuery = widget.initialQuery ?? initialDispatched;
    if (startingQuery != null && startingQuery.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _sendMessage(startingQuery.trim());
        }
      });
    }
  }

  void _onDispatchedAiQuery() {
    final q = AiHelperQueryDispatcher.pendingQuery.value;
    if (q != null && q.trim().isNotEmpty && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _sendMessage(q.trim());
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant CustomerAiHelperPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialQuery != null &&
        widget.initialQuery != oldWidget.initialQuery &&
        widget.initialQuery!.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _sendMessage(widget.initialQuery!.trim());
        }
      });
    }
  }

  String _normalizeLang(String? raw) {
    final v = (raw ?? 'en').toLowerCase().trim();
    if (v == 'hindi') return 'hi';
    if (v == 'english') return 'en';
    final base = v.split(RegExp(r'[-_]')).first;
    if (LocaleScope.supportedLocales.contains(base)) return base;
    return 'en';
  }

  String _sttLocaleId(String lang) {
    const map = {
      'en': 'en_IN',
      'hi': 'hi_IN',
      'ta': 'ta_IN',
      'te': 'te_IN',
      'kn': 'kn_IN',
      'bn': 'bn_IN',
      'mr': 'mr_IN',
      'gu': 'gu_IN',
      'pa': 'pa_IN',
    };
    return map[lang] ?? 'en_IN';
  }

  /// TTS locales — English uses en-IN (Indian English).
  String _ttsLocaleId(String lang) {
    const map = {
      'en': 'en-IN',
      'hi': 'hi-IN',
      'ta': 'ta-IN',
      'te': 'te-IN',
      'kn': 'kn-IN',
      'bn': 'bn-IN',
      'mr': 'mr-IN',
      'gu': 'gu-IN',
      'pa': 'pa-IN',
    };
    return map[lang] ?? 'en-IN';
  }
  bool get _allowsHinglish =>
      _selectedLanguage == 'en' || _selectedLanguage == 'hi';

  List<String> _getDefaultSuggestedReplies(String lang) {
    if (lang == 'hi') {
      return [
        'बाथरूम में नल लीक हो रहा है',
        'स्विचबोर्ड से स्पार्क / एमसीबी ट्रिप',
        'घर की गहरी सफाई (डीप क्लीनिंग)',
        'एसी ठीक से ठंडा नहीं कर रहा',
        'मेरी बुकिंग की स्थिति जांचें',
      ];
    }
    return [
      'Tap leaking in bathroom',
      'Switchboard sparking / MCB tripping',
      'Deep home cleaning needed',
      'AC not cooling properly',
      'Check my booking status',
    ];
  }

  void _initConversation() {
    _suggestedReplies = _getDefaultSuggestedReplies(_selectedLanguage);
    final hinglishNote = _allowsHinglish
        ? (_selectedLanguage == 'hi'
            ? ' आप Hinglish में भी बोल सकते हैं।'
            : ' You can also speak in Hinglish.')
        : '';
    _messages.add(
      _ChatMessage(
        isBot: true,
        text: _selectedLanguage == 'hi'
            ? (AppConstants.voiceAiEnabled
                ? 'नमस्ते! मैं फिक्सली एआई हूँ। बताइए घर में क्या समस्या है, या Live Talk दबाएं।$hinglishNote'
                : 'नमस्ते! मैं फिक्सली एआई हूँ। चैट में बताइए घर में क्या समस्या है।$hinglishNote')
            : (AppConstants.voiceAiEnabled
                ? 'Hello! I am Fixly AI. Tell me the home issue, or tap Live Talk.$hinglishNote'
                : 'Hello! I am Fixly AI. Tell me the home issue in chat.$hinglishNote'),
        timestamp: DateTime.now(),
        action: 'PROMPT_CATEGORY',
      ),
    );
  }

  void _switchLanguage(String newLang) {
    final lang = _normalizeLang(newLang);
    if (_selectedLanguage == lang) return;
    setState(() {
      _selectedLanguage = lang;
      _conversationState['language'] = lang;
      if (_messages.length <= 1 && (_messages.isEmpty || _messages.first.isBot)) {
        _messages.clear();
        _initConversation();
      } else if (!_awaitingReply) {
        _suggestedReplies = _getDefaultSuggestedReplies(_selectedLanguage);
      }
    });

    if (_isLiveMode) {
      _reconnectLiveSession();
    }
    HapticFeedback.selectionClick();
  }

  @override
  void dispose() {
    AiHelperQueryDispatcher.pendingQuery.removeListener(_onDispatchedAiQuery);
    _liveReconnectTimer?.cancel();
    _voiceOut.dispose();
    _removeGlowOverlay();
    _voiceActivityNotifier.dispose();
    // _orbController.dispose();
    _stopBookingAcceptPoll();
    _queryController.dispose();
    _scrollController.dispose();
    _speechService.stopListening();
    _speechService.stopSpeaking();
    super.dispose();
  }

  void _showGlowOverlay() {
    _removeGlowOverlay();
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isLiveMode || _glowOverlayEntry != null) return;
      try {
        final overlay = Overlay.of(context, rootOverlay: true);
        _glowOverlayEntry = OverlayEntry(
          builder: (overlayCtx) => Positioned.fill(
            child: IgnorePointer(
              child: ValueListenableBuilder<double>(
                valueListenable: _voiceActivityNotifier,
                builder: (context, voiceVal, _) {
                  final glowMode = switch (_liveVoiceState) {
                    LiveVoiceState.listening => SiriGlowMode.listening,
                    LiveVoiceState.thinking => SiriGlowMode.thinking,
                    LiveVoiceState.speaking => SiriGlowMode.speaking,
                    LiveVoiceState.paused => SiriGlowMode.idle,
                  };
                  return SiriGlowFrame(
                    active: true,
                    mode: glowMode,
                    voiceActivity: voiceVal,
                    child: const SizedBox.expand(),
                  );
                },
              ),
            ),
          ),
        );
        overlay.insert(_glowOverlayEntry!);
      } catch (e) {
        debugPrint('Overlay attach error: $e');
      }
    });
  }

  void _removeGlowOverlay() {
    _glowOverlayEntry?.remove();
    _glowOverlayEntry = null;
  }

  void _stopBookingAcceptPoll() {
    _bookingAcceptPoll?.cancel();
    _bookingAcceptPoll = null;
  }

  void _startBookingAcceptPoll(String bookingId) {
    final id = bookingId.trim();
    if (id.isEmpty) return;
    _stopBookingAcceptPoll();
    setState(() {
      _polledBookingId = id;
      _workerAccepted = false;
      _acceptedWorkerName = null;
    });
    _pollBookingAccept();
    _bookingAcceptPoll = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _pollBookingAccept(),
    );
  }

  Future<void> _pollBookingAccept() async {
    final id = _polledBookingId;
    if (id == null || !mounted || _workerAccepted) return;
    try {
      final booking = await _bookingsRepo.getById(id);
      if (!mounted || _workerAccepted) return;
      final accepted = booking.status.index >= BookingStatus.accepted.index;
      if (!accepted) return;
      _stopBookingAcceptPoll();
      setState(() {
        _workerAccepted = true;
        _acceptedWorkerName = booking.workerName;
        _messages.add(
          _ChatMessage(
            isBot: true,
            text: _selectedLanguage == 'hi'
                ? 'वर्कर ने बुकिंग स्वीकार कर ली${booking.workerName != null ? ' (${booking.workerName})' : ''}। अब आप लाइव ट्रैक कर सकते हैं।'
                : 'A worker accepted your booking${booking.workerName != null ? ' (${booking.workerName})' : ''}. You can track them live now.',
            timestamp: DateTime.now(),
          ),
        );
      });
      _scrollToBottom();
    } catch (_) {
      // Keep polling; transient network errors are OK.
    }
  }

  void _onBookingCreatedFromAi(Map<String, dynamic>? booking) {
    // Prefer Mongo ObjectId for poll/API — human bookingId alone can 404 weird paths.
    final mongoId = (booking?['_id'] ?? booking?['id'])?.toString().trim();
    final humanId = booking?['bookingId']?.toString().trim();
    final bookingId = (mongoId != null &&
            mongoId.isNotEmpty &&
            RegExp(r'^[0-9a-fA-F]{24}$').hasMatch(mongoId))
        ? mongoId
        : (humanId != null && humanId.isNotEmpty && !humanId.startsWith('#')
            ? humanId
            : null);
    if (bookingId == null || bookingId.isEmpty) return;
    _startBookingAcceptPoll(bookingId);
  }

  /// Strip leaked phone digits from AI replies (privacy).
  String _redactPhones(String text) {
    return text
        .replaceAllMapped(
          RegExp(r'(\+?\d[\d\s\-()]{8,}\d)'),
          (_) => 'in-app call',
        )
        .replaceAll(RegExp(r'\(\s*in-app call\s*\)'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  Future<void> _callWorkerViaWebRtc({
    required String bookingId,
    required String workerName,
    String? workerAvatar,
  }) async {
    final id = bookingId.trim();
    if (id.isEmpty || id.startsWith('#')) {
      ToastUtils.showToast(
        context: context,
        message: 'Booking not ready for call yet',
      );
      return;
    }
    context.push(
      RouteNames.call,
      extra: {
        'bookingId': id,
        'peerName': workerName,
        'peerRole': 'worker',
        'peerAvatar': workerAvatar,
        'serviceTitle': 'Fixly service',
        'isIncoming': false,
      },
    );
    final success = await WebRTCCallService.instance.startCall(
      bookingId: id,
      expectedPeerName: workerName,
      expectedPeerRole: 'worker',
      expectedPeerAvatar: workerAvatar,
      expectedServiceTitle: 'Fixly service',
    );
    if (!success && mounted) {
      ToastUtils.showToast(context: context, message: 'Could not connect call');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Debug-console chat log (customer + AI). Chunks so logcat doesn't truncate.
  void _logChatDebug({
    required String role,
    required String text,
    String? action,
    String? channel,
    Object? extra,
  }) {
    if (!kDebugMode) return;
    final who = role == 'customer' ? '👤 CUSTOMER' : '🤖 AI REPLY';
    final ch = channel != null ? ' [$channel]' : '';
    debugPrint('');
    debugPrint('════════ AI CHAT$ch · $who ════════');
    if (action != null && action.isNotEmpty) {
      debugPrint('⚡ action: $action');
    }
    final body = text.trim().isEmpty ? '(empty)' : text;
    const chunkSize = 700;
    for (var i = 0; i < body.length; i += chunkSize) {
      final end = (i + chunkSize < body.length) ? i + chunkSize : body.length;
      debugPrint(body.substring(i, end));
    }
    if (extra != null) {
      debugPrint('📎 $extra');
    }
    debugPrint('════════════════════════════════════');
  }

  // --- Send Message & Process Agent Response ---
  Future<void> _sendMessage(
    String text, {
    String? imagePath,
    bool alreadyClaimed = false,
  }) async {
    final query = text.trim();
    if ((query.isEmpty && imagePath == null) || _awaitingReply) return;

    // 🛑 Client-side stop/dismiss check — halts speaking & live mode instantly without API call
    if (SpeechService.isDismissOrStopCommand(query)) {
      debugPrint('🛑 [AiHelper] Stop command detected ("$query") -> Halting speech & live mode');
      _interruptSpeaking();
      await _speechService.stopListening();
      if (_isLiveMode) {
        _closeLiveMode();
      }
      return;
    }

    if (alreadyClaimed && query.isNotEmpty) {
      _lastHandledUtteranceNorm = _normUtterance(query);
      _lastHandledUtteranceAt = DateTime.now();
    }

    _logChatDebug(
      role: 'customer',
      text: query.isNotEmpty
          ? query
          : (imagePath != null ? '[photo] $imagePath' : ''),
      channel: imagePath != null ? 'text+image' : (_isLiveMode ? 'voice→text' : 'text'),
      extra: 'lang=$_selectedLanguage state=$_conversationState',
    );

    // Add user message to chat stream
    setState(() {
      _liveSpokenText = '';
      _messages.add(
        _ChatMessage(
          isBot: false,
          text: query.isNotEmpty ? query : 'Attached photo of the issue',
          timestamp: DateTime.now(),
          imagePath: imagePath,
          isNew: true,
        ),
      );
      _messages.add(
        _ChatMessage(
          isBot: true,
          text: '...',
          timestamp: DateTime.now(),
          loading: true,
        ),
      );
      _awaitingReply = true;
      _queryController.clear();
      _suggestedReplies = [];
    });
    if (_isLiveMode) {
      _enterThinking();
    }
    _scrollToBottom();

    try {
      if (imagePath != null) {
        // 1) Vision: let Gemini understand WHAT is in the photo.
        final analysis = await AiApiRepository().analyzeIssue(
          query.isNotEmpty ? query : 'Diagnose the issue in this photo',
          imagePath: imagePath,
        );
        if (!mounted) return;

        final isHi = _selectedLanguage == 'hi';
        final desc = analysis.aiNote.trim();
        final visionLine = isHi
            ? '📷 आपकी फ़ोटो देखी। यह ${analysis.category} से जुड़ी समस्या लग रही है।${desc.isNotEmpty ? '\n$desc' : ''}'
            : '📷 I looked at your photo. This looks like a ${analysis.category} issue.${desc.isNotEmpty ? '\n$desc' : ''}';

        // Seed the detected category so the SAME agent continues its
        // diagnose-first booking flow (it will ask what exactly is wrong).
        _conversationState['category'] = analysis.category;
        _conversationState['language'] = _selectedLanguage;

        _logChatDebug(
          role: 'ai',
          text: visionLine,
          action: 'VISION_ANALYSIS',
          channel: 'text+image',
          extra: 'category=${analysis.category}',
        );

        setState(() {
          _messages.removeLast(); // remove loading bubble
          _messages.add(
            _ChatMessage(
              isBot: true,
              text: visionLine,
              timestamp: DateTime.now(),
              category: analysis.category,
            ),
          );
          _messages.add(
            _ChatMessage(
              isBot: true,
              text: '...',
              timestamp: DateTime.now(),
              loading: true,
            ),
          );
        });
        _scrollToBottom();

        // 2) Hand the image understanding to the conversational agent.
        List<double>? imgCoords;
        if (AppLocation.instance.hasFix) {
          imgCoords = [
            AppLocation.instance.requireLng,
            AppLocation.instance.requireLat,
          ];
        }
        final seed = query.isNotEmpty
            ? query
            : (desc.isNotEmpty ? desc : 'Issue seen in the photo');
        final res = await _aiRepo.chatWithAgent(
          message: seed,
          conversationState: _conversationState,
          language: _selectedLanguage,
          coordinates: imgCoords,
          addressLine: AppLocation.instance.addressLabel,
        );
        if (!mounted) return;
        _conversationState = Map<String, dynamic>.from(res.state);
        _conversationState['language'] = _selectedLanguage;

        _logChatDebug(
          role: 'ai',
          text: res.reply,
          action: res.action,
          channel: 'text+image',
          extra: 'state=${res.state}'
              '${res.workers.isNotEmpty ? ' workers=${res.workers.length}' : ''}'
              '${res.estimate != null ? ' estimate=${res.estimate}' : ''}',
        );

        setState(() {
          _messages.removeLast(); // remove loading bubble
          _messages.add(
            _ChatMessage(
              isBot: true,
              text: res.reply,
              timestamp: DateTime.now(),
              action: res.action,
              booking: res.booking,
              bookings: res.bookings,
              workers: res.workers,
              estimate: res.estimate,
              policy: res.policy,
              category: res.state['category']?.toString(),
            ),
          );
          _awaitingReply = false;
          _suggestedReplies = res.suggestedReplies.isNotEmpty
              ? res.suggestedReplies
              : _generateFallbackSuggestions(
                  res.action, res.reply, _selectedLanguage);
        });
        if (res.action == 'BOOKING_CREATED') {
          _onBookingCreatedFromAi(res.booking);
        }
        _scrollToBottom();
      } else {
        // Conversational Agent (Fixly AI)
        List<double>? coords;
        if (AppLocation.instance.hasFix) {
          coords = [
            AppLocation.instance.requireLng,
            AppLocation.instance.requireLat,
          ];
        }
        final address = AppLocation.instance.addressLabel;
        final lang = _selectedLanguage;

        final res = await _aiRepo.chatWithAgent(
          message: query,
          conversationState: _conversationState,
          language: lang,
          coordinates: coords,
          addressLine: address,
        );

        _logChatDebug(
          role: 'ai',
          text: res.reply,
          action: res.action,
          channel: _isLiveMode ? 'voice→agent' : 'text',
          extra: 'state=${res.state}'
              '${res.workers.isNotEmpty ? ' workers=${res.workers.length}' : ''}'
              '${res.estimate != null ? ' estimate=${res.estimate}' : ''}'
              ' coords=$coords address="$address"',
        );

        if (!mounted) return;

        final textAppActions = parseAppActions(res.appActions);
        final textAppNote = await _applyAppActions(
          textAppActions,
          booking: res.booking,
        );
        final displayReply = textAppNote.isNotEmpty
            ? '${res.reply}\n\n$textAppNote'
            : res.reply;

        // Session Handling
        if (res.action == 'SESSION_EXPIRED') {
          _conversationState = {'language': _selectedLanguage};
        } else if (res.action == 'SESSION_ABORTED') {
          _conversationState = {'language': _selectedLanguage};
          if (_isLiveMode) {
            _closeLiveMode();
          }
        } else {
          _conversationState = Map<String, dynamic>.from(res.state);
          _conversationState['language'] = _selectedLanguage;
        }

        // In Live Mode: play end.mp3 first, hold for 3 seconds, then display and speak response
        if (_isLiveMode) {
          debugPrint('🔔 live chat reply received → playing end.mp3 cue and waiting 3 seconds');
          await LiveUiSounds.instance.cueBeforeSpeak();
          await Future.delayed(const Duration(seconds: 3));
          if (!mounted || !_isLiveMode) return;
          await LiveUiSounds.instance.hush();
        }

        setState(() {
          _messages.removeLast();
          _messages.add(
            _ChatMessage(
              isBot: true,
              text: displayReply,
              timestamp: DateTime.now(),
              action: res.action,
              booking: res.booking,
              bookings: res.bookings,
              workers: res.workers,
              estimate: res.estimate,
              policy: res.policy,
              category: res.state['category']?.toString(),
              appActions: textAppActions,
            ),
          );
          _awaitingReply = false;
          _suggestedReplies = res.suggestedReplies.isNotEmpty
              ? res.suggestedReplies
              : _generateFallbackSuggestions(res.action, res.reply, _selectedLanguage);
        });

        if (_isLiveMode) {
          if (res.action == 'BOOKING_CREATED') {
            _onBookingCreatedFromAi(res.booking);
          }
          final toSpeak = _voiceLineFromAgent(res, displayReply);
          debugPrint(
            '🗣️ live chat reply → speak (Flutter TTS) action=${res.action} chars=${toSpeak.length}',
          );
          setState(() => _liveVoiceState = LiveVoiceState.speaking);
          _setVoiceActivity(0.7);
          unawaited(_speechService.speak(
            SpeechService.cleanForSpeechSummary(toSpeak),
            language: _ttsLocaleId(_selectedLanguage),
            onComplete: () {
              if (!mounted || !_isLiveMode) return;
              _setVoiceActivity(0.0);
              // Auto-listening: Automatically reactivate mic once AI finishes speaking
              Future.delayed(const Duration(milliseconds: 300), () {
                if (mounted &&
                    _isLiveMode &&
                    _liveVoiceState != LiveVoiceState.thinking) {
                  _listenInLiveMode();
                }
              });
            },
          ));
        } else if (res.action == 'BOOKING_CREATED') {
          _onBookingCreatedFromAi(res.booking);
        }
      }
    } catch (e) {
      if (!mounted) return;
      final errText = _selectedLanguage == 'hi'
          ? 'मैं अभी इस अनुरोध को पूरा नहीं कर सका। कृपया पुनः प्रयास करें या नीचे दिए गए विकल्पों में से चुनें।'
          : 'I could not process that request right now. Please try again or tap one of the suggested options.';
      _logChatDebug(
        role: 'ai',
        text: errText,
        action: 'ERROR',
        channel: 'error',
        extra: e,
      );
      setState(() {
        _messages.removeLast();
        _messages.add(
          _ChatMessage(
            isBot: true,
            text: errText,
            timestamp: DateTime.now(),
          ),
        );
        _awaitingReply = false;
        _suggestedReplies = _selectedLanguage == 'hi'
            ? [
                'प्लंबर सहायता',
                'इलेक्ट्रीशियन सहायता',
                'सफाई सेवा',
                'मेरी बुकिंग स्थिति',
              ]
            : [
                'Plumbing assistance',
                'Electrician assistance',
                'Cleaning services',
                'Track my orders',
              ];
      });

      if (_isLiveMode) {
        unawaited(LiveUiSounds.instance.failAndStop());
        ToastUtils.showError(context: context, message: errText);
        // ── PTT MODEL: On error → just go to paused. User taps mic to retry.
        setState(() => _liveVoiceState = LiveVoiceState.paused);
      }
    }

    _scrollToBottom();
  }

  List<String> _generateFallbackSuggestions(String? action, String reply, String lang) {
    final isHi = lang == 'hi';
    final lower = reply.toLowerCase();
    if (action == 'SESSION_EXPIRED') {
      return isHi
          ? ['नल लीक हो रहा है', 'स्विच में स्पार्क', 'डीप क्लीनिंग', 'बुकिंग स्थिति']
          : ['Tap leaking in bathroom', 'Switch sparking', 'Deep cleaning', 'Check booking status'];
    }
    if (action == 'SESSION_ABORTED') {
      return isHi
          ? ['प्लंबर चाहिए', 'इलेक्ट्रीशियन चाहिए', 'डीप क्लीनिंग', 'मदद']
          : ['Need a plumber', 'Need an electrician', 'Deep cleaning', 'Help'];
    }
    if (action == 'BOOKING_CREATED' || lower.contains('confirmed') || lower.contains('कन्फर्म')) {
      return isHi
          ? ['बुकिंग ट्रैक करें', 'मेरी बुकिंग्स देखें', 'नई सेवा बुक करें']
          : ['Track worker arrival', 'View my bookings', 'Book another service'];
    }
    if (action == 'BOOKING_STATUS' || lower.contains('booking #') || lower.contains('स्थिति')) {
      return isHi
          ? ['कार्यकर्ता को कॉल करें', 'ऑर्डर विवरण देखें', 'नई सेवा बुक करें']
          : ['Call worker', 'View order details', 'Book a new service'];
    }
    if (action == 'CONFIRM_EMERGENCY_BOOKING' || lower.contains('emergency') || lower.contains('sos') || lower.contains('आपातकालीन')) {
      return isHi
          ? ['हाँ, तुरंत कार्यकर्ता भेजें', 'विवरण बदलें', 'रद्द करें']
          : ['Yes, dispatch worker now', 'Change details', 'Cancel request'];
    }
    if (action == 'PROMPT_CONFIRMATION' || lower.contains('confirm') || lower.contains('कन्फर्म')) {
      return isHi
          ? ['हाँ, बुकिंग कन्फर्म करें', 'लागत क्या है?', 'रद्द करें']
          : ['Yes, confirm booking', 'What is the price?', 'Cancel'];
    }
    return isHi
        ? ['प्लंबर चाहिए', 'इलेक्ट्रीशियन चाहिए', 'डीप क्लीनिंग', 'बुकिंग स्थिति']
        : ['Need a plumber', 'Need an electrician', 'Deep cleaning', 'Check booking status'];
  }

  // --- Reset Conversation ---
  void _resetChat() {
    setState(() {
      _messages.clear();
      _conversationState = {'language': _selectedLanguage};
      _suggestedReplies = _getDefaultSuggestedReplies(_selectedLanguage);
      _messages.add(
        _ChatMessage(
          isBot: true,
          text: _selectedLanguage == 'hi'
              ? 'बातचीत रीसेट हो गई है। मैं आज आपकी क्या मदद कर सकता हूँ?'
              : 'Conversation reset. How can I help you today?',
          timestamp: DateTime.now(),
          action: 'PROMPT_CATEGORY',
        ),
      );
    });
  }

  // --- Live Voice Mode Engine ---
  Future<void> _startLiveMode() async {
    if (_isStartingLiveMode) return;
    _isStartingLiveMode = true;
    // Invalidate any lingering STT callbacks from before entering live mode.
    _sttSessionId++;
    setState(() {
      _isLiveMode = true;
      _livePcmActive = false;
      _liveVoiceState = LiveVoiceState.listening;
      _liveSpokenText = '';
      _liveUserDraft = '';
      _liveModelDraft = '';
    });
    _pendingLiveGreeting = false;
    _liveGreetingDone = true; // Upfront greeting removed as requested
    _setVoiceActivity(0.0);
    _showGlowOverlay();
    try {
      // Play initial start sound (waits for sound to complete before opening mic)
      await LiveUiSounds.instance.beginLiveSession();
      await Future.delayed(const Duration(milliseconds: 150));
      if (!mounted || !_isLiveMode) return;
      // Start first listening session.
      _listenInLiveMode();
    } finally {
      _isStartingLiveMode = false;
    }
  }

  /// ── Push-to-Talk tap handler ──────────────────────────────────────────────
  /// State machine:
  ///   • Not in live mode          → Enter live mode + start listening.
  ///   • paused  (mic off, idle)   → Start new listening session.
  ///   • listening (mic on)        → Stop mic; if text captured, commit it now.
  ///   • thinking / speaking       → AI is busy; ignore the tap.
  /// ─────────────────────────────────────────────────────────────────────────
  Future<void> _onVoiceButtonTap() async {
    if (_isStartingLiveMode) {
      debugPrint('🎙️ PTT: start live mode in progress — tap ignored');
      return;
    }

    if (!_isLiveMode) {
      // First tap — enter live mode.
      await _startLiveMode();
      return;
    }

    switch (_liveVoiceState) {
      case LiveVoiceState.paused:
        // Mic is OFF → user wants to speak.
        debugPrint('🎙️ PTT: paused → start listening');
        _liveSpokenText = '';
        _liveUserDraft = '';
        _listenInLiveMode();

      case LiveVoiceState.listening:
        // Protect against rapid double-tap turning mic off immediately after opening
        final now = DateTime.now();
        if (_lastListeningStartedAt != null &&
            now.difference(_lastListeningStartedAt!) < const Duration(milliseconds: 700)) {
          debugPrint('🎙️ PTT: rapid double-tap ignored (listening started recently)');
          return;
        }

        // Mic is ON → user taps to stop (or commit what was captured).
        debugPrint('🎙️ PTT: listening → stop mic');
        final captured = _stripWakeWords(
          _liveUserDraft.isNotEmpty ? _liveUserDraft : _liveSpokenText,
        ).trim();
        if (captured.isNotEmpty) {
          // Text was already partially captured — commit it immediately.
          _commitLiveUtterance();
        } else {
          // Nothing captured yet — just stop listening, go to paused.
          await _speechService.stopListening();
          if (mounted) {
            setState(() {
              _liveVoiceState = LiveVoiceState.paused;
              _liveSpokenText = '';
            });
            _setVoiceActivity(0.0);
          }
        }

      case LiveVoiceState.speaking:
        // User tapped while AI is speaking → interrupt and stay paused.
        debugPrint('🎙️ PTT: user tapped while speaking → interrupt');
        _interruptSpeaking();

      case LiveVoiceState.thinking:
        // AI is processing / waiting for API → ignore tap.
        debugPrint('🎙️ PTT: tap ignored — AI is thinking');
    }
  }

  /// Drain full AI audio; mic send stays open the whole time (full duplex).
  Future<void> _handleLiveTurnComplete() async {
    if (!mounted) return;
    if (!_isLiveMode && !_chatGeminiSpeak) return;
    await _voiceOut.onLiveTurnComplete();
    if (!mounted) return;
    if (!_isLiveMode) {
      _chatGeminiSpeak = false;
      return;
    }
    _flushLiveUserTranscript();
    _flushLiveModelTranscript();
    _setVoiceActivity(0.0);
    _bargeHoldMs = 0;
    _liveCapture.muted = false;
    setState(() => _liveVoiceState = LiveVoiceState.paused);
  }

  void _cancelUtteranceCommit() {
    _utteranceCommitTimer?.cancel();
    _utteranceCommitTimer = null;
  }

  void _armUtteranceCommit() {
    _utteranceCommitTimer?.cancel();
    _utteranceCommitTimer = Timer(_silenceCommitGap, _commitLiveUtterance);
  }

  String _stripWakeWords(String text) {
    var cleaned = text.trim();
    cleaned = cleaned.replaceFirst(
      RegExp(r'^(hey\s+|hi\s+|hello\s+)?(fixly|flexi|fix-ly|fixley|flexy)[,:\s]*', caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceFirst(
      RegExp(r'^(हे\s+|हाय\s+|हेलो\s+)?(फिक्सली|फ्लेक्सी|फिक्स ली)[,:\s]*', caseSensitive: false),
      '',
    );
    return cleaned.trim();
  }

  /// 4s silence after user speech → send utterance to chat API.
  void _commitLiveUtterance() {
    if (!mounted || !_isLiveMode) return;
    _cancelUtteranceCommit();
    // ── DOUBLE-COMMIT GUARD: already sent, don't fire twice ──────────────
    if (_liveVoiceState == LiveVoiceState.thinking ||
        _liveVoiceState == LiveVoiceState.speaking) {
      debugPrint('⏭️ silence-commit skip — already ${_liveVoiceState.name}');
      return;
    }
    final rawText =
        (_liveUserDraft.isNotEmpty ? _liveUserDraft : _liveSpokenText).trim();
    final text = _stripWakeWords(rawText);
    _hadSpeechInUtterance = false;
    _utteranceCommitTimer = null;
    if (text.isEmpty) return;
    // ── CLEAR IMMEDIATELY so any subsequent onListeningChanged sees '' ───
    if (mounted) {
      setState(() {
        _liveUserDraft = '';
        _liveSpokenText = '';
      });
    } else {
      _liveUserDraft = '';
      _liveSpokenText = '';
    }
    // ─────────────────────────────────────────────────────────────────────
    debugPrint('🎙️ committing live voice to API: "$text"');
    _enterThinking();
    _speechService.stopListening();
    unawaited(_sendMessage(text, alreadyClaimed: true));
  }

  /// Strong local barge-in only (mic always open — ignore soft echo).
  void _maybeLocalBargeIn(double rms) {
    if (!_isLiveMode || _liveVoiceState != LiveVoiceState.speaking) {
      _bargeHoldMs = 0;
      return;
    }
    if (rms >= _bargeRmsThreshold) {
      _bargeHoldMs += 80;
    } else {
      _bargeHoldMs = 0;
    }
    if (_bargeHoldMs >= _bargeHoldNeedMs) {
      debugPrint('🎙️ local barge-in rms=$rms hold=$_bargeHoldMs');
      _bargeHoldMs = 0;
      _interruptSpeaking();
    }
  }

  /// Normalize for utterance dedupe (ignore case / punctuation / extra spaces).
  String _normUtterance(String raw) {
    return raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s\u0900-\u097F\u0B80-\u0BFF\u0C00-\u0C7F]'), '')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Claim utterance for ~6s. false = already handled (skip second brain).
  bool _claimUtterance(String raw, {required String channel}) {
    final n = _normUtterance(raw);
    if (n.isEmpty) return true;
    final now = DateTime.now();
    final prev = _lastHandledUtteranceNorm;
    final at = _lastHandledUtteranceAt;
    if (prev != null &&
        at != null &&
        now.difference(at) < const Duration(seconds: 6)) {
      if (n == prev || n.contains(prev) || prev.contains(n)) {
        debugPrint('⏭️ utterance dedupe ($channel): "$n" ~ "$prev"');
        return false;
      }
    }
    _lastHandledUtteranceNorm = n;
    _lastHandledUtteranceAt = now;
    debugPrint('✅ utterance claim ($channel): "$n"');
    return true;
  }

  void _flushLiveUserTranscript() {
    final text = _liveUserDraft.trim();
    _liveUserDraft = '';
    _liveSpokenText = '';
    if (text.isEmpty || !mounted) return;
    // Tool path or _sendMessage already added this user line — don't duplicate bubble.
    final norm = _normUtterance(text);
    if (_lastHandledUtteranceNorm != null &&
        (norm == _lastHandledUtteranceNorm ||
            norm.contains(_lastHandledUtteranceNorm!) ||
            _lastHandledUtteranceNorm!.contains(norm))) {
      debugPrint('⏭️ skip transcript flush — already claimed: "$norm" ~ "$_lastHandledUtteranceNorm"');
      return;
    }
    if (_messages.isNotEmpty &&
        !_messages.last.isBot &&
        (_messages.last.text.trim() == text ||
            _normUtterance(_messages.last.text) == norm)) {
      debugPrint('⏭️ skip transcript flush — already matches last user bubble: "$text"');
      return;
    }
    setState(() {
      _messages.add(
        _ChatMessage(
          isBot: false,
          text: text,
          timestamp: DateTime.now(),
          isNew: true,
        ),
      );
    });
    _logChatDebug(role: 'customer', text: text, channel: 'live-transcript');
    _scrollToBottom();
  }

  void _enterLiveVoiceFallback() {
    if (!_isLiveMode || !mounted) return;
    debugPrint('⚠️ Live soft-path → STT/TTS fallback (paused)');
    unawaited(_voiceOut.interrupt());
    _livePcmActive = false;
    _liveBridgeReady = false;
    _liveVoiceFallback = true;
    unawaited(_liveCapture.stop());
    unawaited(_livePlayer.stop(keepInit: true));
    if (mounted) {
      setState(() => _liveVoiceState = LiveVoiceState.paused);
      _setVoiceActivity(0.0);
    }
  }

  void _scheduleLiveReconnect() {
    _liveReconnectTimer?.cancel();
    _liveReconnectTimer = null;
  }

  Future<String> _applyAppActions(
    List<AiAppAction> actions, {
    Map<String, dynamic>? booking,
  }) async {
    if (actions.isEmpty || !mounted) return '';
    final bookingId = (booking?['_id'] ??
            booking?['id'] ??
            booking?['bookingId'] ??
            _polledBookingId)
        ?.toString();
    return executeAiAppActions(
      context,
      actions,
      fallbackBookingId: bookingId,
      onLanguage: (lang) {
        if (!mounted) return;
        _switchLanguage(lang);
      },
    );
  }

  Widget _buildAppActionsCard(List<AiAppAction> actions) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: actions.map((a) {
          return FilledButton.tonal(
            onPressed: () async {
              final note = await _applyAppActions([a]);
              if (!mounted) return;
              if (note.isNotEmpty) {
                ToastUtils.showToast(context: context, message: note);
              }
            },
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            child: Text(
              a.buttonLabel,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _flushLiveModelTranscript() {
    final text = _liveModelDraft.trim();
    _liveModelDraft = '';
    if (text.isEmpty || !mounted) return;
    if (_messages.isNotEmpty &&
        _messages.last.isBot &&
        _messages.last.text.trim() == text) {
      return;
    }
    setState(() {
      _messages.add(
        _ChatMessage(
          isBot: true,
          text: text,
          timestamp: DateTime.now(),
        ),
      );
    });
    _scrollToBottom();
  }

  Future<void> _reconnectLiveSession() async {
    await _speechService.stopListening();
    _speechService.stopSpeaking();
    if (_isLiveMode && _liveVoiceState == LiveVoiceState.listening) {
      _listenInLiveMode();
    }
  }

  void _closeLiveMode() {
    _sttSessionId++; // Invalidate any in-flight STT callbacks immediately.
    _liveReconnectTimer?.cancel();
    _liveReconnectTimer = null;
    _cancelUtteranceCommit();
    _hadSpeechInUtterance = false;
    unawaited(LiveUiSounds.instance.stop());
    _removeGlowOverlay();
    _speechService.stopListening();
    _speechService.stopSpeaking();
    if (mounted) {
      setState(() {
        _isLiveMode = false;
        _liveVoiceState = LiveVoiceState.paused;
      });
    } else {
      _isLiveMode = false;
      _liveVoiceState = LiveVoiceState.paused;
    }
    _setVoiceActivity(0.0);
    if (mounted) _scrollToBottom();
  }

  /// Prefer backend speakHint; clean bullets/newlines for Live + TTS.
  String _voiceLineFromAgent(AiAgentResponse res, String displayFallback) {
    final raw = (res.speakHint != null && res.speakHint!.trim().isNotEmpty)
        ? res.speakHint!
        : displayFallback;
    var spoken = SpeechService.cleanForSpeech(raw);
    if (res.action == 'PROMPT_BOOKING_TYPE' &&
        res.suggestedReplies.isNotEmpty) {
      final opts = res.suggestedReplies.join(', or ');
      final lower = spoken.toLowerCase();
      if (!lower.contains('emergency') &&
          !lower.contains('standard') &&
          !lower.contains('schedule')) {
        spoken = '$spoken Your options are: $opts.';
      } else if (!spoken.contains('Emergency') &&
          !spoken.contains('Standard')) {
        // speakHint may already list options with bullets — cleaned form is enough
      }
    }
    return spoken;
  }

  void _enterThinking({double activity = 0.4}) {
    if (!mounted || !_isLiveMode) return;
    setState(() => _liveVoiceState = LiveVoiceState.thinking);
    _setVoiceActivity(activity);
    LiveUiSounds.instance.markThinking();
  }

  /// Live / API failure — stop SFX, surface error on UI.
  Future<void> _onLiveError(
    String message, {
    bool enterFallback = false,
  }) async {
    await LiveUiSounds.instance.failAndStop();
    if (!mounted) return;
    ToastUtils.showError(context: context, message: message);
    setState(() {
      _liveVoiceState = LiveVoiceState.paused;
      _messages.add(
        _ChatMessage(
          isBot: true,
          text: message,
          timestamp: DateTime.now(),
          action: 'ERROR',
        ),
      );
    });
    _scrollToBottom();
    if (enterFallback) {
      _enterLiveVoiceFallback();
    } else if (_livePcmActive) {
      _liveCapture.muted = false;
    }
  }

  /// One voice path: Gemini Live PCM first → confirmed playback → TTS only on failure.
  /// [withOutputCues]: end cue then speak (th1/th2 already from session timeline).
  void _requestSpeech(
    String text, {
    VoidCallback? onComplete,
    bool expectModelAlreadySpeaking = false,
    bool withOutputCues = true,
  }) {
    if (!_isLiveMode) {
      debugPrint('⚠️ _requestSpeech skipped — not in live mode');
      onComplete?.call();
      return;
    }
    final cleaned = SpeechService.cleanForSpeech(text);
    if (cleaned.isEmpty) {
      onComplete?.call();
      return;
    }

    final liveReady =
        _livePcmActive && _liveBridgeReady && !_liveVoiceFallback && _livePlayer.isReady;

    final prompt = _selectedLanguage == 'hi'
        ? 'अब यूज़र को एक बार, स्वाभाविक और दोस्ताना अंदाज़ में हिंदी में बोलो (रोबोट जैसी आवाज़ नहीं, बुलेट मत पढ़ो): $cleaned'
        : 'Now speak this once to the user in natural Indian English, warm and human — not robotic, no bullet symbols, no repeating: $cleaned';

    debugPrint(
      '🗣️ _requestSpeech liveReady=$liveReady toolExpect=$expectModelAlreadySpeaking cues=$withOutputCues chars=${cleaned.length}',
    );

    unawaited(() async {
      if (withOutputCues) {
        // Tiny non-blocking cue — don't stall Live conversation.
        await LiveUiSounds.instance.cueBeforeSpeak();
      }
      await LiveUiSounds.instance.hush();
      if (!mounted || !_isLiveMode) {
        onComplete?.call();
        return;
      }
      _liveCapture.muted = false;
      // Queue plays back-to-back; no stop() of prior mid-sentence unless barge-in.
      unawaited(
        _voiceOut.requestSpeech(
          text: cleaned,
          ttsLocale: _ttsLocaleId(_selectedLanguage),
          livePcmReady: liveReady,
          expectModelAlreadySpeaking: expectModelAlreadySpeaking,
          liveSpeakPrompt: expectModelAlreadySpeaking ? null : prompt,
          onSpeaking: () {
            if (!mounted || !_isLiveMode) return;
            setState(() => _liveVoiceState = LiveVoiceState.speaking);
            _setVoiceActivity(0.7);
            _liveCapture.muted = false;
          },
          onListening: () {
            if (!mounted || !_isLiveMode) return;
            _setVoiceActivity(0.0);
            _liveCapture.muted = false;
            setState(() => _liveVoiceState = LiveVoiceState.paused);
          },
          onComplete: () {
            if (!mounted || !_isLiveMode) return;
            _liveCapture.muted = false;
            onComplete?.call();
          },
        ),
      );
    }());
  }

  double _emaVoiceLevel = 0.0;
  double _maxVoiceLevel = 1.0;

  void _setVoiceActivity(double level) {
    if (level > _maxVoiceLevel) _maxVoiceLevel = level;
    _maxVoiceLevel = _maxVoiceLevel * 0.995;
    if (_maxVoiceLevel < 1.0) _maxVoiceLevel = 1.0;
    
    double normalized = (level / _maxVoiceLevel).clamp(0.0, 1.0);
    
    if (normalized > _emaVoiceLevel) {
      _emaVoiceLevel = _emaVoiceLevel + 0.6 * (normalized - _emaVoiceLevel);
    } else {
      _emaVoiceLevel = _emaVoiceLevel + 0.15 * (normalized - _emaVoiceLevel);
    }

    _voiceActivityNotifier.value = _emaVoiceLevel;
    // _orbController.amplitude = (_emaVoiceLevel * 0.87 + 0.13).clamp(0.13, 1.0);
  }

  /// Real-time STT loop with silence detection and wake word stripping.
  Future<void> _listenInLiveMode() async {
    if (!_isLiveMode || _livePcmActive) return;

    // ── SESSION ID: Capture at start so stale callbacks from old sessions
    // can be safely ignored. Prevents double-bubble and state corruption.
    final mySession = ++_sttSessionId;

    setState(() {
      _liveVoiceState = LiveVoiceState.listening;
      _liveSpokenText = '';   // Always clear on new session
      _liveUserDraft = '';    // Clear draft too
    });
    _setVoiceActivity(0.0);
    _lastListeningStartedAt = DateTime.now();

    final sttLocale = _sttLocaleId(_selectedLanguage);

    await _speechService.startListening(
      localeId: sttLocale,
      onPartialResult: (text) {
        if (mySession != _sttSessionId) return; // stale callback — ignore
        if (!mounted || !_isLiveMode) return;
        final clean = _stripWakeWords(text);
        if (SpeechService.isDismissOrStopCommand(clean) ||
            SpeechService.isDismissOrStopCommand(text)) {
          debugPrint('🛑 [LIVE STT PARTIAL] Stop command recognized: "$text"');
          _closeLiveMode();
          return;
        }
        _setVoiceActivity(0.70);
        _hadSpeechInUtterance = true;
        setState(() {
          _liveSpokenText = clean.isNotEmpty ? clean : text;
        });
        _scrollToBottom();
        _armUtteranceCommit();
      },
      onSoundLevelChange: (level) {
        if (mySession != _sttSessionId) return; // stale callback — ignore
        if (!mounted || !_isLiveMode) return;
        _setVoiceActivity(level);
        if (_liveSpokenText.trim().isNotEmpty) {
          if (level > 0.25) {
            _cancelUtteranceCommit();
          } else {
            _armUtteranceCommit();
          }
        }
      },
      onResult: (finalText) {
        if (mySession != _sttSessionId) return; // stale callback — ignore
        if (!mounted || !_isLiveMode) return;
        _setVoiceActivity(0.0);
        final clean = _stripWakeWords(finalText);
        final toUse = clean.isNotEmpty ? clean : finalText;
        if (toUse.trim().isEmpty) {
          return;
        }
        if (SpeechService.isDismissOrStopCommand(clean) ||
            SpeechService.isDismissOrStopCommand(finalText)) {
          debugPrint('🛑 [LIVE STT FINAL] Stop command recognized: "$toUse"');
          _closeLiveMode();
          return;
        }
        debugPrint('🎤 [VOICE STT FINAL] "$toUse" ($sttLocale)');
        setState(() => _liveSpokenText = toUse);
        _hadSpeechInUtterance = true;
        _commitLiveUtterance();
      },
      onListeningChanged: (listening) {
        if (mySession != _sttSessionId) return; // stale callback — ignore
        debugPrint('🎙️ STT onListeningChanged: $listening');
        if (!listening && mounted && _isLiveMode) {
          final leftover = _stripWakeWords(_liveSpokenText).trim();
          if (leftover.isNotEmpty &&
              _liveVoiceState != LiveVoiceState.thinking &&
              _liveVoiceState != LiveVoiceState.speaking) {
            // Leftover text from partial — commit it.
            _commitLiveUtterance();
          } else if (_liveVoiceState == LiveVoiceState.listening) {
            debugPrint('🛑 STT ended without speech → paused. Tap mic to speak.');
            setState(() {
              _liveVoiceState = LiveVoiceState.paused;
              _liveSpokenText = '';
            });
            _setVoiceActivity(0.0);
          }
        }
      },
    );
  }

  /// Speaker icon on bot bubbles — speak aloud via native Flutter TTS.
  void _speakBotMessageAloud(String text) {
    final cleaned = SpeechService.cleanForSpeechSummary(_redactPhones(text));
    if (cleaned.isEmpty) return;

    if (_isLiveMode) {
      setState(() => _liveVoiceState = LiveVoiceState.speaking);
      _setVoiceActivity(0.70);
    }
    unawaited(_speechService.speak(
      cleaned,
      language: _ttsLocaleId(_selectedLanguage),
      onComplete: () {
        if (!mounted) return;
        if (_isLiveMode) {
          _setVoiceActivity(0.0);
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted &&
                _isLiveMode &&
                _liveVoiceState != LiveVoiceState.thinking) {
              _listenInLiveMode();
            }
          });
        }
      },
    ));
  }

  void _interruptSpeaking() {
    unawaited(LiveUiSounds.instance.stop());
    unawaited(_voiceOut.interrupt());
    _speechService.stopSpeaking();
    if (_isLiveMode) {
      _setVoiceActivity(0.0);
      setState(() => _liveVoiceState = LiveVoiceState.paused);
    }
  }

  // --- Text Dictation in Standard Mode ---
  void _toggleDictation() async {
    if (_isDictating) {
      await _speechService.stopListening();
      setState(() => _isDictating = false);
    } else {
      setState(() => _isDictating = true);
      final sttLocale = _sttLocaleId(_selectedLanguage);
      await _speechService.startListening(
        localeId: sttLocale,
        onPartialResult: (text) {
          if (!mounted) return;
          setState(() {
            _queryController.text = text;
            _queryController.selection = TextSelection.fromPosition(
              TextPosition(offset: text.length),
            );
          });
        },
        onResult: (text) {
          if (!mounted) return;
          setState(() {
            _queryController.text = text;
            _isDictating = false;
          });
        },
        onListeningChanged: (listening) {
          if (mounted) setState(() => _isDictating = listening);
        },
      );
    }
  }

  // --- Photo Diagnostic Picker ---
  Future<void> _pickPhotoForAi() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
    );
    if (picked == null || !mounted) return;
    _sendMessage(_queryController.text.trim(), imagePath: picked.path);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Keep normal chat background in live mode (no black fill behind orb).
      backgroundColor: null,
        appBar: AppBar(
          titleSpacing: 14,
          elevation: 0,
          scrolledUnderElevation: 1,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _isLiveMode
                        ? const [Color(0xFF00C7BE), Color(0xFF5856D6), Color(0xFFFF2D55)]
                        : [
                            context.scheme.primary,
                            context.scheme.tertiary,
                          ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isLiveMode ? Icons.graphic_eq_rounded : Icons.auto_awesome,
                  size: 17,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Fixly AI',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        if (_isLiveMode) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF10B981), width: 0.8),
                            ),
                            child: const Text(
                              'LIVE',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF10B981),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: _isLiveMode ? const Color(0xFF00C7BE) : const Color(0xFF10B981),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            _isLiveMode
                            ? (_liveVoiceFallback
                                ? (_selectedLanguage == 'hi' ? 'सुन रहा हूँ…' : 'Listening…')
                                : (_selectedLanguage == 'hi' ? 'बोलिए, मैं सुन रहा हूँ' : 'Speak anytime'))
                            : 'Smart Assistant',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: context.scheme.onSurface.withValues(alpha: 0.55),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            _buildLanguageTogglePill(),
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert_rounded,
                color: context.scheme.onSurface.withValues(alpha: 0.7),
              ),
              onSelected: (val) {
                if (val == 'reset') _resetChat();
                if (val == 'discover') context.push(RouteNames.customerAiDiscovery);
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'reset',
                  child: Row(
                    children: [
                      Icon(Icons.refresh_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('Restart Session'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'discover',
                  child: Row(
                    children: [
                      Icon(Icons.explore_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Discover Services'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            // Message List (remains active and visible during live voice talking)
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                itemCount: _messages.length +
                    (_isLiveMode &&
                            _liveVoiceState == LiveVoiceState.listening &&
                            _liveSpokenText.trim().isNotEmpty
                        ? 1
                        : 0),
                itemBuilder: (context, index) {
                  if (index < _messages.length) {
                    final msg = _messages[index];
                    return _buildMessageItem(msg);
                  }
                  // Live partial transcript while user is speaking (type-as-you-go).
                  return _buildLiveSpeechBubble(_liveSpokenText);
                },
              ),
            ),

            // Dynamic Suggested Replies Horizontal Bar (hidden in live mode)
            if (_suggestedReplies.isNotEmpty && !_awaitingReply && !_isLiveMode)
              _buildSuggestedRepliesBar(),

            // Bottom Input Bar (transforms into Siri Wave Bar when _isLiveMode is true)
            _buildBottomInputBar(),
          ],
        ),
      );
  }

  // --- Multilingual Language Toggle Pill ---
  Widget _buildLanguageTogglePill() {
    return PopupMenuButton<String>(
      tooltip: 'Language',
      onSelected: _switchLanguage,
      itemBuilder: (context) => LocaleScope.supportedLocales
          .map(
            (code) => PopupMenuItem<String>(
              value: code,
              child: Text(
                '${_langLabels[code] ?? code}${_selectedLanguage == code ? '  ✓' : ''}',
              ),
            ),
          )
          .toList(),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: context.isDark
              ? context.scheme.surfaceContainerHighest
              : const Color(0xFFE2E8F0),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: context.scheme.outlineVariant.withValues(alpha: 0.5),
            width: 0.8,
          ),
        ),
        child: Text(
          _langLabels[_selectedLanguage] ?? _selectedLanguage.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: context.scheme.primary,
          ),
        ),
      ),
    );
  }

  // --- Message Item Builder ---
  Widget _buildMessageItem(_ChatMessage msg) {
    final isBot = msg.isBot;
    final timeStr = DateFormat('hh:mm a').format(msg.timestamp);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment:
            isBot ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isBot) ...[
            Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.only(right: 8, top: 2),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    context.scheme.primary,
                    context.scheme.tertiary,
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.auto_awesome,
                size: 16,
                color: Colors.white,
              ),
            ),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isBot ? CrossAxisAlignment.start : CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isBot
                        ? (context.isDark
                            ? context.scheme.surfaceContainerHighest
                            : const Color(0xFFF1F5F9))
                        : context.scheme.primary,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: isBot
                          ? const Radius.circular(4)
                          : const Radius.circular(18),
                      bottomRight: isBot
                          ? const Radius.circular(18)
                          : const Radius.circular(4),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: msg.loading
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                          child: AiThinkingStatusWidget(
                            language: _selectedLanguage,
                            color: context.scheme.primary,
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            !isBot && msg.isNew
                                ? _TypewriterText(
                                    text: msg.text,
                                    style: const TextStyle(
                                      fontSize: 14.5,
                                      height: 1.38,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    isBot ? _redactPhones(msg.text) : msg.text,
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      height: 1.38,
                                      color: isBot
                                          ? context.scheme.onSurface
                                          : Colors.white,
                                    ),
                                  ),
                            if (isBot) ...[
                              const SizedBox(height: 6),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  InkWell(
                                    onTap: () => _speakBotMessageAloud(msg.text),
                                    child: Icon(
                                      Icons.volume_up_rounded,
                                      size: 16,
                                      color: context.scheme.primary
                                          .withValues(alpha: 0.75),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  InkWell(
                                    onTap: () {
                                      Clipboard.setData(
                                        ClipboardData(
                                          text: _redactPhones(msg.text),
                                        ),
                                      );
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Copied to clipboard'),
                                          duration: Duration(seconds: 1),
                                        ),
                                      );
                                    },
                                    child: Icon(
                                      Icons.copy_rounded,
                                      size: 15,
                                      color: context.scheme.onSurface
                                          .withValues(alpha: 0.5),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                ),

                // Booking Type Selection Quick Action Chips
                if (msg.action == 'PROMPT_BOOKING_TYPE')
                  _buildBookingTypeChips(),

                // Worker Carousel Card — only on the worker-selection step so the
                // list appears once (after diagnosis), never repeated on every turn.
                if (msg.action == 'PROMPT_WORKER_SELECTION' &&
                    msg.workers.isNotEmpty)
                  _buildWorkerCarouselCard(msg.workers),

                // Strict Zero Workers Available Warning Card
                if (msg.action == 'NO_WORKERS_AVAILABLE')
                  _buildNoWorkersWarningCard(),

                // Estimate & Cooperative Fair Wage Policy Card
                if (msg.estimate != null && msg.booking == null)
                  _buildEstimateAndPolicyCard(msg.estimate!, msg.policy),

                // Booking Created Action Card
                if (msg.booking != null) _buildBookingCreatedCard(msg.booking!),

                // Booking Status Query Card
                if (msg.bookings.isNotEmpty)
                  _buildBookingListCard(msg.bookings),
                if (msg.appActions.isNotEmpty) _buildAppActionsCard(msg.appActions),

                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
                  child: Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: context.scheme.onSurface.withValues(alpha: 0.45),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!isBot) ...[
            Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.only(left: 8, top: 2),
              decoration: BoxDecoration(
                color: context.scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.person_rounded,
                size: 18,
                color: context.scheme.primary,
              ),
            ),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: 0.08, end: 0);
  }

  // --- Booking Type Selection Chips ---
  Widget _buildBookingTypeChips() {
    final isHi = _selectedLanguage == 'hi';
    return Container(
      margin: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          ActionChip(
            avatar: const Icon(Icons.bolt_rounded, size: 16, color: Color(0xFFEF4444)),
            label: Text(
              isHi ? 'Emergency SOS (तुरंत)' : 'Emergency SOS',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
            ),
            backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.12),
            side: const BorderSide(color: Color(0xFFEF4444), width: 1.2),
            onPressed: () => _sendMessage(isHi ? 'आपातकालीन सेवा (Emergency SOS) तुरंत' : 'Emergency SOS urgently needed'),
          ),
          ActionChip(
            avatar: Icon(Icons.schedule_rounded, size: 16, color: context.scheme.primary),
            label: Text(
              isHi ? 'Standard (सामान्य)' : 'Standard Booking',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
            ),
            backgroundColor: context.scheme.primary.withValues(alpha: 0.12),
            side: BorderSide(color: context.scheme.primary, width: 1.2),
            onPressed: () => _sendMessage(isHi ? 'सामान्य बुकिंग (Standard) कर दो' : 'Standard booking'),
          ),
          ActionChip(
            avatar: const Icon(Icons.calendar_month_rounded, size: 16, color: Color(0xFF8B5CF6)),
            label: Text(
              isHi ? 'Schedule (आगे का समय)' : 'Schedule Later',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
            ),
            backgroundColor: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
            side: const BorderSide(color: Color(0xFF8B5CF6), width: 1.2),
            onPressed: () => _sendMessage(isHi ? 'बाद के समय के लिए शेड्यूल करें' : 'Schedule for later time'),
          ),
        ],
      ),
    );
  }

  // --- Worker Selection Carousel Card ---
  Widget _buildWorkerCarouselCard(List<dynamic> workers) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      height: 195,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: workers.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final w = workers[i] as Map<String, dynamic>;
          final name = w['name']?.toString() ?? 'Verified Worker';
          final rate = w['hourlyRate'] ?? 199;
          final rating = (w['rating'] as num?)?.toDouble();
          final jobs = (w['ratingCount'] as num?)?.toInt() ??
              (w['totalJobs'] as num?)?.toInt() ??
              0;
          final society = w['society']?.toString() ?? 'Fixly Cooperative';
          final avatarUrl = w['avatar']?.toString();

          return Container(
            width: 220,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.isDark ? context.scheme.surfaceContainerHighest : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.scheme.primary.withValues(alpha: 0.35), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: context.scheme.primary.withValues(alpha: 0.15),
                      backgroundImage: (avatarUrl != null && avatarUrl.startsWith('http')) ? NetworkImage(avatarUrl) : null,
                      child: (avatarUrl == null || !avatarUrl.startsWith('http'))
                          ? Icon(Icons.person, color: context.scheme.primary)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 3),
                              const Icon(Icons.verified, size: 14, color: Color(0xFF10B981)),
                            ],
                          ),
                          Text(
                            society,
                            style: TextStyle(fontSize: 10.5, color: context.scheme.onSurface.withValues(alpha: 0.6)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, size: 16, color: Colors.amber),
                        const SizedBox(width: 2),
                        Text(
                          rating != null && rating > 0
                              ? '${rating.toStringAsFixed(1)}${jobs > 0 ? ' ($jobs)' : ''}'
                              : 'New',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                        ),
                      ],
                    ),
                    Text(
                      '₹$rate base price',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: context.scheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 34,
                  child: ElevatedButton(
                    onPressed: () => _sendMessage('Select worker: $name (ID: ${w['_id']})'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.scheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: EdgeInsets.zero,
                    ),
                    child: const Text('Select Worker', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // --- Strict Zero Workers Warning Card ---
  Widget _buildNoWorkersWarningCard() {
    final isHi = _selectedLanguage == 'hi';
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 18),
              const SizedBox(width: 6),
              Text(
                isHi ? 'कोई ऑनलाइन कार्यकर्ता उपलब्ध नहीं' : 'No Online Workers Available',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF92400E)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isHi
                ? 'इस श्रेणी में सभी सत्यापित कार्यकर्ता वर्तमान में ऑफ़लाइन या व्यस्त हैं। फिक्सली केवल वास्तविक कार्यकर्ता उपलब्धता की गारंटी देता है।'
                : 'All certified workers in this category are currently offline or busy. To avoid ghost bookings, Fixly requires verified worker availability.',
            style: const TextStyle(fontSize: 11.5, color: Color(0xFF78350F)),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonal(
                  onPressed: () => _sendMessage(isHi ? 'बाद के समय के लिए शेड्यूल करें' : 'Schedule for later'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    backgroundColor: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                  ),
                  child: Text(
                    isHi ? 'बाद में शेड्यूल करें' : 'Schedule for Later',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF92400E)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: () => _sendMessage(isHi ? 'अन्य सेवाएं देखें' : 'Try another service'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    backgroundColor: const Color(0xFFD97706),
                  ),
                  child: Text(
                    isHi ? 'अन्य सेवाएं' : 'Other Services',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Estimate & Cooperative Fair Wage Policy Card ---
  Widget _buildEstimateAndPolicyCard(Map<String, dynamic> estimate, Map<String, dynamic>? policy) {
    final isHi = _selectedLanguage == 'hi';
    final basePrice = estimate['baseServiceFee'] ?? 150;
    final urgentFee = estimate['urgentFee'] ?? 0;
    final platformFee = estimate['platformFee'] ?? 0;
    final total = estimate['totalAmount'] ?? (basePrice + urgentFee + platformFee);

    final policyTitle = policy?['title']?.toString() ??
        (isHi ? 'फिक्सली उचित पारिश्रमिक एवं कल्याण गारंटी' : 'Fixly Cooperative Fair Wage Guarantee');
    final fairWageNotice = policy?['fairWageNotice']?.toString() ??
        (isHi
            ? 'सेवा शुल्क का 100% सीधे सहकारी कार्यकर्ता को जाता है।'
            : '100% of the service fee goes directly to the cooperative worker.');
    final welfareNotice = policy?['welfareFundNotice']?.toString() ??
        (isHi
            ? 'कार्यकर्ता सामाजिक सुरक्षा और चिकित्सा दुर्घटना कोष में 5% योगदान शामिल।'
            : 'Includes 5% contribution to Worker Social Security & Medical Accident Fund.');

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.isDark ? context.scheme.surfaceContainerHighest : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_rounded, color: Color(0xFF3B82F6), size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isHi ? 'मूल्य अनुमान एवं पारिश्रमिक विवरण' : 'Price Estimate & Fair Wage Breakdown',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Color(0xFF1E40AF),
                  ),
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Divider(height: 16),
          _buildEstimateRow(
            isHi ? 'आधार विज़िट / जांच शुल्क' : 'Base Visiting / Diagnosis Fee',
            '₹$basePrice',
          ),
          if (urgentFee > 0)
            _buildEstimateRow(
              isHi ? 'आपातकालीन SOS प्राथमिकता शुल्क' : 'Emergency SOS Priority Surcharge',
              '+₹$urgentFee',
              isHighlight: true,
            ),
          _buildEstimateRow(
            isHi ? 'फिक्सली प्लेटफ़ॉर्म शुल्क (0% बिचौलिया)' : 'Fixly Platform Fee (0% Middleman)',
            '₹$platformFee',
            isGreen: true,
          ),
          const Divider(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  isHi ? 'कुल अनुमानित राशि' : 'Total Estimated Amount',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                  maxLines: 2,
                  softWrap: true,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '₹$total',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                  color: Color(0xFF047857),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.shield_rounded, color: Color(0xFF10B981), size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        policyTitle,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: Color(0xFF065F46)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$fairWageNotice • $welfareNotice',
                        style: TextStyle(fontSize: 10.5, color: context.scheme.onSurface.withValues(alpha: 0.75)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _sendMessage(isHi ? 'रद्द करें' : 'Cancel'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    side: BorderSide(color: Colors.grey.shade400),
                  ),
                  child: Text(
                    isHi ? 'रद्द करें' : 'Cancel',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: () => _sendMessage(isHi ? 'हाँ, बुकिंग कन्फर्म करें' : 'Yes, confirm booking'),
                  icon: const Icon(Icons.check, size: 16),
                  label: Text(
                    isHi ? 'बुकिंग कन्फर्म करें' : 'Confirm Booking',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    backgroundColor: const Color(0xFF10B981),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEstimateRow(String label, String value, {bool isHighlight = false, bool isGreen = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: context.scheme.onSurface.withValues(alpha: 0.7),
              ),
              maxLines: 2,
              softWrap: true,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isHighlight
                  ? const Color(0xFFDC2626)
                  : (isGreen ? const Color(0xFF059669) : context.scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  // --- Booking Created Rich Card ---
  Widget _buildBookingCreatedCard(Map<String, dynamic> booking) {
    final bookingId =
        (booking['bookingId'] ?? booking['_id'] ?? booking['id'] ?? '#BK-CONFIRMED')
            .toString();
    final totalAmount = booking['invoice']?['totalAmount'] ?? 200;
    final isThisPolled = _polledBookingId != null &&
        (_polledBookingId == bookingId ||
            _polledBookingId == booking['_id']?.toString() ||
            _polledBookingId == booking['id']?.toString());
    final accepted = isThisPolled && _workerAccepted;
    final waiting = isThisPolled && !_workerAccepted;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF10B981).withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                accepted
                    ? Icons.check_circle_rounded
                    : Icons.hourglass_top_rounded,
                color: accepted
                    ? const Color(0xFF10B981)
                    : context.scheme.primary,
                size: 18,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  accepted
                      ? 'Worker accepted ($bookingId)'
                      : 'Booking placed ($bookingId)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: accepted
                        ? const Color(0xFF10B981)
                        : context.scheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            accepted
                ? 'Estimated Fee: ₹$totalAmount • ${_acceptedWorkerName ?? 'Worker'} is on the way soon.'
                : waiting
                    ? 'Estimated Fee: ₹$totalAmount • Waiting for a worker to accept…'
                    : 'Estimated Fee: ₹$totalAmount • Verified worker will be assigned shortly.',
            style: TextStyle(
              fontSize: 12,
              color: context.scheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
          if (waiting) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.scheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedLanguage == 'hi'
                        ? 'वर्कर के स्वीकार करने की प्रतीक्षा…'
                        : 'Waiting for worker to accept…',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.scheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonal(
                  onPressed: () {
                    // Switch bottom-nav Bookings tab (index 3), don't push overlay.
                    if (context.canPop() &&
                        GoRouterState.of(context)
                            .uri
                            .path
                            .contains('ai-chat')) {
                      context.pop();
                    }
                    context.goCustomerTab(3);
                  },
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    backgroundColor:
                        const Color(0xFF10B981).withValues(alpha: 0.18),
                  ),
                  child: Text(
                    _selectedLanguage == 'hi' ? 'बुकिंग्स देखें' : 'Go to Bookings',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF047857),
                    ),
                  ),
                ),
              ),
              if (accepted) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      final id = _polledBookingId ?? bookingId;
                      if (id.trim().isEmpty || id.startsWith('#')) return;
                      context.push(
                        '${RouteNames.customerTracking}?bookingId=$id',
                      );
                    },
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      backgroundColor: const Color(0xFF10B981),
                    ),
                    child: Text(
                      _selectedLanguage == 'hi' ? 'लाइव ट्रैक' : 'Track Live',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // --- Booking List Rich Card ---
  Widget _buildBookingListCard(List<dynamic> bookings) {
    final latest = bookings.first as Map<String, dynamic>;
    final bookingId = latest['bookingId'] ?? latest['_id'] ?? latest['id'] ?? '#BK';
    final mongoId = (latest['_id'] ?? latest['id'] ?? bookingId).toString();
    final status = latest['status'] ?? 'PENDING';
    final worker = latest['worker'] as Map<String, dynamic>?;
    final workerName = worker?['name']?.toString() ?? 'Assigned Professional';
    final workerAvatar = worker?['avatar']?.toString();

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: context.scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Order $bookingId',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: context.scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    status.toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: context.scheme.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (worker != null) ...[
            const SizedBox(height: 6),
            Text(
              'Worker: $workerName',
              style: TextStyle(
                fontSize: 12,
                color: context.scheme.onSurface.withValues(alpha: 0.8),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            // Privacy: never show real phone — in-app WebRTC only.
            TextButton.icon(
              onPressed: () => _callWorkerViaWebRtc(
                bookingId: mongoId,
                workerName: workerName,
                workerAvatar: workerAvatar,
              ),
              icon: Icon(Icons.videocam_rounded, size: 16, color: context.scheme.primary),
              label: Text(
                _selectedLanguage == 'hi' ? 'ऐप से कॉल करें' : 'Call via Fixly',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.scheme.primary,
                ),
              ),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.centerLeft,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --- Dynamic AI Suggested Replies Bar ---
  Widget _buildSuggestedRepliesBar() {
    return Container(
      height: 44,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _suggestedReplies.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final reply = _suggestedReplies[index];
          return ActionChip(
            onPressed: () => _sendMessage(reply),
            backgroundColor: context.isDark
                ? context.scheme.surfaceContainerHighest
                : Colors.white,
            elevation: 1,
            shadowColor: Colors.black12,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: context.scheme.primary.withValues(alpha: 0.25),
              ),
            ),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 13,
                  color: context.scheme.primary,
                ),
                const SizedBox(width: 5),
                Text(
                  reply,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: context.scheme.onSurface,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // --- Bottom Messenger Style Input Bar ---
  Widget _buildBottomInputBar() {
    if (_isLiveMode) {
      return _buildLiveVoiceBar();
    }

    final hasText = _queryController.text.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(
            color: context.scheme.outlineVariant.withValues(alpha: 0.20),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Photo Diagnostic Button
            IconButton(
              onPressed: _pickPhotoForAi,
              tooltip: 'Attach Issue Photo',
              icon: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: context.isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.04),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.add_photo_alternate_rounded,
                  color: context.scheme.onSurface.withValues(alpha: 0.70),
                  size: 19,
                ),
              ),
            ),
            const SizedBox(width: 4),

            // Text Input Field
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: context.isDark
                      ? context.scheme.surfaceContainerHighest.withValues(alpha: 0.6)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: context.scheme.outlineVariant.withValues(alpha: 0.25),
                    width: 0.8,
                  ),
                ),
                child: TextField(
                  controller: _queryController,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (val) => _sendMessage(val),
                  onChanged: (text) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: _isDictating
                        ? (_selectedLanguage == 'hi' ? 'सुन रहा हूँ...' : 'Listening...')
                        : (_selectedLanguage == 'hi'
                            ? 'समस्या लिखें या पूछें...'
                            : 'Ask Fixly or describe issue...'),
                    hintStyle: TextStyle(
                      fontSize: 13.5,
                      color: context.scheme.onSurface.withValues(alpha: 0.45),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    border: InputBorder.none,
                    suffixIcon: IconButton(
                      onPressed: _toggleDictation,
                      tooltip: 'Dictate speech',
                      icon: Icon(
                        _isDictating
                            ? Icons.mic_rounded
                            : Icons.mic_none_rounded,
                        color: _isDictating
                            ? Colors.redAccent
                            : context.scheme.onSurface.withValues(alpha: 0.55),
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Single Unified Action: Send Button if text entered, else Siri Live Talk Button
            if (hasText)
              Material(
                color: context.scheme.primary,
                shape: const CircleBorder(),
                elevation: 2,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _awaitingReply
                      ? null
                      : () => _sendMessage(_queryController.text),
                  child: const Padding(
                    padding: EdgeInsets.all(11),
                    child: Icon(
                      Icons.arrow_upward_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              )
            else
              // Single Unified Live Talk Button
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _onVoiceButtonTap,
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF00C7BE), // Cyan
                          Color(0xFF5856D6), // Indigo
                          Color(0xFFFF2D55), // Coral Pink
                        ],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF5856D6).withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.graphic_eq_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _selectedLanguage == 'hi' ? 'लाइव' : 'Live',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // --- Siri 3D Orb Live Voice Bottom Controller Bar (Clean & Uncluttered) ---
  Widget _buildLiveVoiceBar() {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final onBg = context.scheme.onSurface;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          top: BorderSide(
            color: context.scheme.outlineVariant.withValues(alpha: 0.22),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Keyboard toggle button (restores typing field & send button)
            IconButton.filledTonal(
              onPressed: _closeLiveMode,
              tooltip: 'Type message',
              style: IconButton.styleFrom(
                backgroundColor: onBg.withValues(alpha: 0.06),
                padding: const EdgeInsets.all(12),
              ),
              icon: Icon(
                Icons.keyboard_alt_rounded,
                color: onBg.withValues(alpha: 0.75),
                size: 22,
              ),
            ),

            // TEMP test orb (GIF loop). Delete FixlyLiveOrb + restore SiriORB later.
            ValueListenableBuilder<double>(
              valueListenable: _voiceActivityNotifier,
              builder: (_, activity, child) => FixlyLiveOrb(
                size: 92,
                voiceActivity: activity,
                onTap: () async {
                  if (_liveVoiceState == LiveVoiceState.speaking) {
                    // Barge-in: user wants to interrupt AI speech.
                    _interruptSpeaking();
                  } else {
                    // All other states handled by PTT handler.
                    await _onVoiceButtonTap();
                  }
                },
              ),
            ),

            // End Live Mode Button
            IconButton.filledTonal(
              onPressed: _closeLiveMode,
              tooltip: 'End Live Talk',
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.12),
                padding: const EdgeInsets.all(12),
              ),
              icon: const Icon(
                Icons.close_rounded,
                color: Color(0xFFEF4444),
                size: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Real-time Live Speech Bubble shown in chat while user is speaking ---
  Widget _buildLiveSpeechBubble(String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * 0.78,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        context.scheme.primary,
                        const Color(0xFF6366F1),
                      ],
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(18),
                      topRight: Radius.circular(18),
                      bottomLeft: Radius.circular(18),
                      bottomRight: Radius.circular(4),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    text,
                    style: const TextStyle(
                      fontSize: 14.5,
                      height: 1.35,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 32,
            height: 32,
            margin: const EdgeInsets.only(left: 8, top: 2),
            decoration: BoxDecoration(
              color: context.scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person_rounded,
              size: 16,
              color: context.scheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}
