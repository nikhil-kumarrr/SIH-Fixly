import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Service for handling speech-to-text and text-to-speech functionality
class SpeechService {
  static final SpeechService _instance = SpeechService._internal();
  factory SpeechService() => _instance;
  SpeechService._internal();

  static const _audioChannel = MethodChannel('com.example.fixly/audio');

  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _isListening = false;
  String _lastWords = '';
  bool _isInitialized = false;
  bool _isSpeaking = false;
  String? _speakingText;
  DateTime? _lastSpeakAt;
  Map<String, String>? _preferredEnVoice;
  Map<String, String>? _preferredHiVoice;

  VoidCallback? _onSpeechComplete;
  Function(bool)? _listeningChanged;

  void _emitListening(bool val) {
    if (_isListening != val) {
      _isListening = val;
      _listeningChanged?.call(val);
    }
  }

  /// Temporarily mutes Android STREAM_SYSTEM to suppress mic-click beep.
  static Future<void> _muteSystemSounds() async {
    if (!Platform.isAndroid) return;
    try { await _audioChannel.invokeMethod('muteSystemSounds'); } catch (_) {}
  }

  /// Restores STREAM_SYSTEM after STT has started (100ms delay is enough).
  static Future<void> _unmuteSystemSounds() async {
    if (!Platform.isAndroid) return;
    try { await _audioChannel.invokeMethod('unmuteSystemSounds'); } catch (_) {}
  }

  /// Request system permissions for microphone & speech recognition
  Future<bool> requestPermissions() async {
    try {
      final micStatus = await Permission.microphone.status;
      if (!micStatus.isGranted) {
        await Permission.microphone.request();
      }
      final speechStatus = await Permission.speech.status;
      if (!speechStatus.isGranted) {
        await Permission.speech.request();
      }
      final micGranted = await Permission.microphone.isGranted;
      final speechGranted = await Permission.speech.isGranted;
      return micGranted && speechGranted;
    } catch (e) {
      debugPrint('Error requesting speech permissions: $e');
      return false;
    }
  }

  /// Initialize the speech service
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      await requestPermissions();

      final bool sttAvailable = await _speech.initialize(
        options: [
          SpeechToText.androidNoBluetooth,
          SpeechToText.androidAlwaysUseStop,
        ],
        onStatus: (val) {
          debugPrint('onStatus: $val');
          if (val == 'listening') {
            _emitListening(true);
          } else if (val == 'done') {
            _emitListening(false);
          }
        },
        onError: (val) {
          debugPrint('onError: $val');
          _emitListening(false);
        },
      );

      if (!sttAvailable) {
        debugPrint('Speech-to-text not available');
        return false;
      }

      try {
        await _tts.setEngine('com.google.android.tts');
      } catch (e) {
        debugPrint('⚠️ TTS setEngine: $e');
      }
      try {
        await _tts.awaitSpeakCompletion(true);
      } catch (_) {}

      // Route TTS to speaker (not silent earpiece / dead stream).
      try {
        await _tts.setAudioAttributesForNavigation();
        debugPrint('🔊 TTS audio attrs = navigation guidance (speaker)');
      } catch (e) {
        debugPrint('⚠️ TTS setAudioAttributesForNavigation: $e');
      }

      await _tts.setSpeechRate(0.50);
      await _tts.setVolume(1.0);
      await _tts.setPitch(0.85); // Natural, resonant male voice pitch
      await _tts.setLanguage('en-IN');
      await _preferMaleIndianVoice();

      try {
        final engines = await _tts.getEngines;
        debugPrint('🔊 TTS engines: $engines');
        final voice = await _tts.getDefaultVoice;
        debugPrint('🔊 TTS defaultVoice: $voice');
        final langs = await _tts.getLanguages;
        debugPrint('🔊 TTS languages count=${(langs is List) ? langs.length : 0}');
      } catch (e) {
        debugPrint('⚠️ TTS debug probes failed: $e');
      }

      _tts.setCompletionHandler(() {
        debugPrint('🔊 TTS completed textLen=${_speakingText?.length}');
        _isSpeaking = false;
        _speakingText = null;
        unawaited(_releasePlaybackSession());
        final cb = _onSpeechComplete;
        _onSpeechComplete = null;
        cb?.call();
      });
      _tts.setCancelHandler(() {
        debugPrint('🔊 TTS cancelled/interrupted');
        _isSpeaking = false;
        _speakingText = null;
        unawaited(_releasePlaybackSession());
        final cb = _onSpeechComplete;
        _onSpeechComplete = null;
        cb?.call();
      });
      _tts.setErrorHandler((dynamic msg) {
        debugPrint('❌ TTS Error: $msg');
        _isSpeaking = false;
        _speakingText = null;
        unawaited(_releasePlaybackSession());
        final cb = _onSpeechComplete;
        _onSpeechComplete = null;
        cb?.call();
      });

      _isInitialized = true;
      debugPrint('Speech service initialized successfully');
      return true;
    } catch (e) {
      debugPrint('Error initializing speech service: $e');
      return false;
    }
  }

  /// Configures a natural, resonant Indian male voice for English and Hindi.
  Future<void> _preferMaleIndianVoice() async {
    try {
      final raw = await _tts.getVoices;
      if (raw is! List) return;
      debugPrint('🔊 TTS checking ${raw.length} available voices for male Indian tone');

      Map<String, String>? maleEnVoice;
      Map<String, String>? maleHiVoice;

      for (final v in raw) {
        if (v is! Map) continue;
        final locale = (v['locale']?.toString() ?? '').toLowerCase();
        final name = (v['name']?.toString() ?? '').toLowerCase();

        final isEn = locale.startsWith('en-in') || locale.startsWith('en_in');
        final isHi = locale.startsWith('hi-in') || locale.startsWith('hi_in');
        if (!isEn && !isHi) continue;

        // Google TTS male Indian English voice: en-in-x-end or en-in-x-ene
        // Google TTS male Hindi voice: hi-in-x-hid or hi-in-x-hie
        final isMale = name.contains('male') ||
            name.contains('-end') ||
            name.contains('-ene') ||
            name.contains('-hid') ||
            name.contains('-hie') ||
            name.contains('voice 2') ||
            name.contains('voice 4');

        if (isEn && (isMale || maleEnVoice == null)) {
          maleEnVoice = {'name': v['name'].toString(), 'locale': v['locale'].toString()};
          if (isMale) break;
        }
        if (isHi && (isMale || maleHiVoice == null)) {
          maleHiVoice = {'name': v['name'].toString(), 'locale': v['locale'].toString()};
        }
      }

      _preferredEnVoice = maleEnVoice;
      _preferredHiVoice = maleHiVoice;
      if (_preferredEnVoice != null) {
        await _tts.setVoice(_preferredEnVoice!);
        debugPrint('🔊 TTS male voice selected: $_preferredEnVoice');
      }
    } catch (e) {
      debugPrint('⚠️ TTS getVoices/setVoice: $e');
    }
  }

  Future<void> _preparePlaybackSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
          avAudioSessionMode: AVAudioSessionMode.spokenAudio,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            usage: AndroidAudioUsage.assistanceNavigationGuidance,
          ),
          androidAudioFocusGainType:
              AndroidAudioFocusGainType.gainTransientMayDuck,
          androidWillPauseWhenDucked: false,
        ),
      );
      await session.setActive(true);
      debugPrint('🔊 TTS audio session active (nav/speech → speaker)');
    } catch (e) {
      debugPrint('⚠️ TTS audio session: $e');
    }
    try {
      await _tts.setAudioAttributesForNavigation();
    } catch (_) {}
  }

  Future<void> _releasePlaybackSession() async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(false);
    } catch (_) {}
  }

  Future<void> _prepareRecordingSession({bool keepSpeaking = false}) async {
    // Stop TTS if it's playing — unless keepSpeaking is enabled for barge-in
    if (!keepSpeaking && _isSpeaking) {
      try { await _tts.stop(); } catch (_) {}
      _isSpeaking = false;
      _speakingText = null;
    }
    debugPrint('🎙️ STT ready (keepSpeaking=$keepSpeaking) — SpeechRecognizer will manage audio focus');
  }

  /// Start listening for speech input
  Future<bool> startListening({
    required Function(String) onResult,
    required Function(bool) onListeningChanged,
    Function(String)? onPartialResult,
    Function(double)? onSoundLevelChange,
    String? localeId,
    bool suppressBeep = false,
    bool keepSpeaking = false,
  }) async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) return false;
    }

    if (_speech.isListening) {
      debugPrint('⚠️ STT already listening — stopping old session before new one');
      await _speech.stop();
      await Future.delayed(const Duration(milliseconds: 60));
    }

    try {
      await _prepareRecordingSession(keepSpeaking: keepSpeaking);

      _listeningChanged = onListeningChanged;
      _emitListening(true);

      double smoothedLevel = 0.0;
      String lastPartial = '';
      bool deliveredFinal = false;

      await _speech.listen(
        onResult: (val) {
          if (val.recognizedWords.isNotEmpty) {
            _lastWords = val.recognizedWords;
            lastPartial = val.recognizedWords;
            onPartialResult?.call(val.recognizedWords);
            smoothedLevel = 0.7;
            onSoundLevelChange?.call(smoothedLevel);
          }
          if (val.finalResult) {
            final best = val.recognizedWords.isNotEmpty
                ? val.recognizedWords
                : lastPartial;
            if (best.isNotEmpty && !deliveredFinal) {
              deliveredFinal = true;
              onResult(best);
            }
          }
        },
        onSoundLevelChange: (level) {
          final normalized = ((level + 2.0) / 10.0).clamp(0.0, 1.0);
          smoothedLevel = smoothedLevel * 0.75 + normalized * 0.25;
          onSoundLevelChange?.call(smoothedLevel);
        },
        listenOptions: SpeechListenOptions(
          listenMode: ListenMode.deviceDefault,
          partialResults: true,
          localeId: localeId,
          cancelOnError: false,
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 4),
        ),
      );

      _isListening = _speech.isListening;
      return _isListening;
    } catch (e) {
      debugPrint('Error starting speech recognition: $e');
      _emitListening(false);
      return false;
    }
  }


  Future<void> stopListening() async {
    _emitListening(false);
    try {
      if (_speech.isListening) {
        await _speech.stop();
      }
    } catch (_) {}
  }

  bool get isListening => _isListening;

  String get lastWords => _lastWords;

  static String cleanForSpeech(String text) {
    return text
        .replaceAll(RegExp(r'[*_#`~]'), '')
        .replaceAll(RegExp(r'https?:\/\/\S+'), '')
        .replaceAll(RegExp(r'\[(.*?)\]\(.*?\)'), r'$1')
        .replaceAll(RegExp(r'[•·▪◦]'), ',')
        .replaceAll(RegExp(r'[\r\n]+'), '. ')
        .replaceAll(RegExp(r'\s*,\s*,+'), ',')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .replaceAll(RegExp(r'(\.\s*){2,}'), '. ')
        .trim();
  }

  /// Client-side check for user wanting to stop, silence, or dismiss the AI assistant.
  /// Fully handled locally on the device without making any backend API call.
  static bool isDismissOrStopCommand(String rawText) {
    final text = rawText.trim().toLowerCase();
    if (text.isEmpty) return false;

    // Fast-path exact set check
    const exactDismiss = {
      'stop', 'stop ai', 'stop it', 'stop now', 'stop please', 'stop fixly', 'stop flexi',
      'quit', 'exit', 'cancel', 'close', 'close ai', 'shut up', 'quiet', 'silence', 'be quiet',
      'band karo', 'band kar', 'band ho jao', 'band', 'band kar do',
      'chup', 'chup raho', 'chup ho jao', 'chup kar', 'chup baitho',
      'bas', 'bas karo', 'bas kar', 'bas ho gaya', 'bas bahut hua',
      'khatam', 'khatam karo', 'khatam kar',
      'ruko', 'ruk jao', 'ruk', 'rok do', 'roko',
      'alvida', 'bye', 'goodbye', 'tata',
      'turn off', 'turn off ai', 'switch off',
      'स्टॉप', 'स्टॉप एआई', 'स्टॉप करो', 'स्टॉप कर',
      'बंद', 'बंद करो', 'बंद हो जाओ', 'बंद कर दो',
      'चुप', 'चुप रहो', 'चुप हो जाओ', 'शांत', 'शांत रहो',
      'बस', 'बस करो', 'बस कर', 'बस बहुत हुआ',
      'खत्म', 'खत्म करो', 'रोक', 'रोको', 'रोक दो',
      'रुक', 'रुको', 'रुक जाओ', 'अलविदा', 'बाय', 'टाटा',
      'कैंसिल', 'रद्द', 'रद्द करो', 'रहने दो'
    };
    if (exactDismiss.contains(text)) return true;

    // Regex pattern matching for compound phrases
    final stopRegex = RegExp(
      r'(^|\s)(stop(\s*(ai|it|please|now|karo|fixly|flexi))?|exit|quit|cancel|close(\s*ai)?|shut\s*up|quiet|silence|be\s*quiet|band\s*(karo|kar|ho\s*jao|kar\s*do)?|chup(\s*(raho|ho\s*jao|kar|baitho))?|bas(\s*(karo|kar|ho\s*gaya|bahut\s*hua))?|khatam(\s*(karo|kar))?|ruko?|rok(\s*do)?|alvida|goodbye|bye(\s*bye)?|turn\s*off(\s*ai)?|स्टॉप(\s*(एआई|करो|कर))?|बंद\s*(करो|हो\s*जाओ|कर\s*दो)?|चुप(\s*(रहो|हो\s*जाओ|कर))?|बस(\s*(करो|बहुत\s*हुआ))?|खत्म(\s*(करो))?|रोक(\s*(दो))?|रुक(\s*(जाओ))?|रुको|अलविदा|बाय|कैंसिल|रद्द\s*(करो)?|रहने\s*दो)($|\s)',
      caseSensitive: false,
      unicode: true,
    );
    return stopRegex.hasMatch(text);
  }

  /// Extracts a punchy, concise 1-2 sentence spoken summary for voice TTS.
  /// Large details/lists remain in chat, but voice remains crisp (< 4-6 seconds).
  static String cleanForSpeechSummary(String text) {
    final cleaned = cleanForSpeech(text);
    if (cleaned.isEmpty) return '';

    // Split into sentences using '.', '!', '?', '।', '\n', '|'
    final sentences = cleaned
        .split(RegExp(r'(?<=[.!?।|])\s+|\n+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && s.length > 2)
        .toList();

    if (sentences.isEmpty) {
      return cleaned.length > 130 ? '${cleaned.substring(0, 130)}...' : cleaned;
    }

    final first = sentences.first;
    if (sentences.length == 1 || first.length >= 120) {
      return first.length > 140 ? '${first.substring(0, 135)}...' : first;
    }

    final second = sentences[1];
    if (first.length + second.length + 1 <= 150) {
      return '$first $second';
    }

    return first;
  }

  /// Pick installed TTS locale; English prefers en-IN.
  Future<String> resolveAvailableLanguage(String requested) async {
    try {
      final raw = await _tts.getLanguages;
      if (raw is! List) return requested;
      final langs =
          raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
      if (langs.isEmpty) return requested;

      final want = requested.trim();
      for (final l in langs) {
        if (l.toLowerCase() == want.toLowerCase()) return l;
      }
      final prefix = want.split(RegExp(r'[-_]')).first.toLowerCase();
      if (prefix == 'en') {
        for (final prefer in ['en-IN', 'en_IN', 'en-GB', 'en_GB', 'en-US', 'en_US']) {
          for (final l in langs) {
            if (l.toLowerCase() == prefer.toLowerCase()) return l;
          }
        }
      }
      for (final l in langs) {
        if (l.toLowerCase().startsWith(prefix)) return l;
      }
      for (final fallback in ['en-IN', 'en_IN', 'en-US', 'en_US', 'en']) {
        for (final l in langs) {
          if (l.toLowerCase() == fallback.toLowerCase()) {
            debugPrint('⚠️ TTS language "$want" unavailable — using "$l"');
            return l;
          }
        }
      }
      return langs.first;
    } catch (e) {
      debugPrint('⚠️ TTS getLanguages failed: $e');
      return requested;
    }
  }

  Future<void> speak(
    String text, {
    String? language,
    VoidCallback? onComplete,
  }) async {
    if (!_isInitialized) {
      final ok = await initialize();
      if (!ok) {
        debugPrint('❌ TTS speak aborted — init failed');
        onComplete?.call();
        return;
      }
    }

    final cleaned = cleanForSpeech(text);
    if (cleaned.isEmpty) {
      onComplete?.call();
      return;
    }

    // Ignore spam taps on same line (was causing Interrupted: true loop).
    if (_isSpeaking &&
        _speakingText == cleaned &&
        _lastSpeakAt != null &&
        DateTime.now().difference(_lastSpeakAt!) < const Duration(seconds: 8)) {
      debugPrint('🔊 TTS ignore duplicate tap (already speaking)');
      return;
    }

    if (_isSpeaking) await stopSpeaking();

    try {
      _onSpeechComplete = onComplete;
      await _preparePlaybackSession();

      final requested = language ??
          (RegExp(r'[\u0900-\u097F]').hasMatch(cleaned) ? 'hi-IN' : 'en-IN');
      final lang = await resolveAvailableLanguage(requested);
      await _tts.setLanguage(lang);
      if (lang.toLowerCase().startsWith('hi') && _preferredHiVoice != null) {
        try {
          await _tts.setVoice(_preferredHiVoice!);
        } catch (_) {}
      } else if (_preferredEnVoice != null) {
        try {
          await _tts.setVoice(_preferredEnVoice!);
        } catch (_) {}
      }
      await _tts.setSpeechRate(0.50);
      await _tts.setVolume(1.0);
      await _tts.setPitch(0.85); // Natural, resonant Indian male voice pitch

      _isSpeaking = true;
      _speakingText = cleaned;
      _lastSpeakAt = DateTime.now();
      debugPrint('🔊 TTS speak lang=$lang chars=${cleaned.length} focus=true');

      // Android: focus:true requests STREAM_MUSIC audio focus so sound is audible.
      final dynamic result = Platform.isAndroid
          ? await _tts.speak(cleaned, focus: true)
          : await _tts.speak(cleaned);

      if (result == 0) {
        debugPrint('❌ TTS speak returned failure result=$result');
        _isSpeaking = false;
        _speakingText = null;
        await _releasePlaybackSession();
        final cb = _onSpeechComplete;
        _onSpeechComplete = null;
        cb?.call();
      }
    } catch (e) {
      debugPrint('❌ Error in TTS: $e');
      _isSpeaking = false;
      _speakingText = null;
      await _releasePlaybackSession();
      onComplete?.call();
      _onSpeechComplete = null;
    }
  }

  Future<void> stopSpeaking() async {
    _onSpeechComplete = null;
    _speakingText = null;
    try {
      await _tts.stop();
    } catch (e) {
      debugPrint('Error stopping TTS: $e');
    } finally {
      _isSpeaking = false;
      await _releasePlaybackSession();
    }
  }

  bool get isSpeaking => _isSpeaking;

  Future<List<dynamic>> getLocales() async {
    if (!_isInitialized) {
      await initialize();
    }
    return await _speech.locales();
  }

  void dispose() {
    _speech.cancel();
    _tts.stop();
  }
}
