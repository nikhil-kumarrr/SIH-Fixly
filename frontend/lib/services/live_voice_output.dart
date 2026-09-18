import 'dart:async';

import 'package:flutter/foundation.dart';

import 'gemini_live_service.dart';
import 'live_pcm_player.dart';
import 'speech_service.dart';

class _SpeechJob {
  _SpeechJob({
    required this.text,
    required this.ttsLocale,
    required this.livePcmReady,
    required this.expectModelAlreadySpeaking,
    required this.commitTextTurn,
    this.liveSpeakPrompt,
    this.onSpeaking,
    this.onListening,
    this.onComplete,
  });

  final String text;
  final String ttsLocale;
  final bool livePcmReady;
  final bool expectModelAlreadySpeaking;
  final bool commitTextTurn;
  final String? liveSpeakPrompt;
  final VoidCallback? onSpeaking;
  final VoidCallback? onListening;
  final VoidCallback? onComplete;
}

/// Single authority for AI voice out:
/// Gemini Live PCM → speaker first; flutter_tts only on genuine PCM failure.
/// Multiple replies → FIFO queue (play one fully, then next).
class LiveVoiceOutputController {
  LiveVoiceOutputController({
    required this.player,
    required this.speech,
    required this.live,
  });

  final LivePcmPlayer player;
  final SpeechService speech;
  final GeminiLiveService live;

  int _speechGeneration = 0;
  Timer? _watchdog;
  bool _pcmConfirmed = false;
  bool _ttsStarted = false;
  bool _completed = false;
  String? _pendingText;
  String? _pendingLocale;
  VoidCallback? _onComplete;
  VoidCallback? _onSpeaking;
  VoidCallback? _onListening;

  final List<_SpeechJob> _queue = [];
  bool _pumping = false;
  Completer<void>? _activeDone;
  bool _endingTurn = false;

  int get speechGeneration => _speechGeneration;
  bool get pcmPlaybackConfirmed => _pcmConfirmed;
  bool get isBusy => _pumping || _queue.isNotEmpty;
  /// True for whole speak job including drain (blocks soft barge-in).
  bool get isPlaying => (_pumping && !_completed) || player.isPlaying;

  void attachPlayerCallbacks() {
    player.onPlaybackConfirmed = () {
      final gen = _speechGeneration;
      if (_completed || _ttsStarted) return;
      if (!_isCurrent(gen)) return;
      _pcmConfirmed = true;
      _watchdog?.cancel();
      _watchdog = null;
      debugPrint('🎯 voice: PCM confirmed gen=$gen — TTS cancelled');
    };
    player.onPlaybackFailed = (err) {
      debugPrint('❌ voice: PCM failed gen=$_speechGeneration err=$err');
      final gen = _speechGeneration;
      final text = _pendingText;
      final locale = _pendingLocale;
      if (text == null || locale == null) return;
      if (!_isCurrent(gen) || _completed || _ttsStarted || _pcmConfirmed) {
        return;
      }
      unawaited(_fallbackTts(gen, text, locale));
    };
  }

  bool _isCurrent(int gen) => gen == _speechGeneration;

  /// Enqueue speech. Plays fully before next item. Never cuts prior mid-sentence
  /// unless [interrupt] / barge-in.
  Future<void> requestSpeech({
    required String text,
    required String ttsLocale,
    required bool livePcmReady,
    bool expectModelAlreadySpeaking = false,
    bool commitTextTurn = false,
    String? liveSpeakPrompt,
    VoidCallback? onSpeaking,
    VoidCallback? onListening,
    VoidCallback? onComplete,
  }) async {
    final cleaned = SpeechService.cleanForSpeech(text);
    if (cleaned.isEmpty) {
      onComplete?.call();
      return;
    }

    _queue.add(
      _SpeechJob(
        text: cleaned,
        ttsLocale: ttsLocale,
        livePcmReady: livePcmReady,
        expectModelAlreadySpeaking: expectModelAlreadySpeaking,
        commitTextTurn: commitTextTurn,
        liveSpeakPrompt: liveSpeakPrompt,
        onSpeaking: onSpeaking,
        onListening: onListening,
        onComplete: onComplete,
      ),
    );
    debugPrint('🗣️ voice queue +1 size=${_queue.length} chars=${cleaned.length}');
    await _pump();
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (_queue.isNotEmpty) {
        final job = _queue.removeAt(0);
        debugPrint(
          '🗣️ voice queue play sizeLeft=${_queue.length} chars=${job.text.length}',
        );
        await _runJob(job);
      }
    } finally {
      _pumping = false;
      // Jobs enqueued from onComplete while we were pumping.
      if (_queue.isNotEmpty) {
        unawaited(_pump());
      }
    }
  }

  Future<void> _runJob(_SpeechJob job) async {
    _speechGeneration++;
    final gen = _speechGeneration;
    _watchdog?.cancel();
    _watchdog = null;
    _pcmConfirmed = false;
    _ttsStarted = false;
    _completed = false;
    _endingTurn = false;
    _pendingText = job.text;
    _pendingLocale = job.ttsLocale;
    _onComplete = job.onComplete;
    _onSpeaking = job.onSpeaking;
    _onListening = job.onListening;
    _activeDone = Completer<void>();

    await player.stop(keepInit: true);
    player.resetForNewResponse();
    player.setAcceptingPcm(true);

    if (speech.isSpeaking) {
      await speech.stopSpeaking();
    }

    _onSpeaking?.call();
    debugPrint(
      '🗣️ voice request gen=$gen livePcm=${job.livePcmReady} '
      'toolExpect=${job.expectModelAlreadySpeaking} commit=${job.commitTextTurn}',
    );

    if (!job.livePcmReady) {
      await _fallbackTts(gen, job.text, job.ttsLocale);
      await _activeDone?.future;
      return;
    }

    if (!job.expectModelAlreadySpeaking) {
      final prompt = job.liveSpeakPrompt ??
          'Say this once only, do not repeat in another language: ${job.text}';
      live.sendRealtimeText(prompt, commitTurn: job.commitTextTurn);
      debugPrint('🎙️ voice: asked Gemini Live to speak gen=$gen');
    } else {
      debugPrint('🎙️ voice: waiting for tool spokenReply PCM gen=$gen');
    }

    _armWatchdog(gen, job.text, job.ttsLocale, softExtend: false);
    await _activeDone!.future;
  }

  void _armWatchdog(
    int gen,
    String text,
    String locale, {
    required bool softExtend,
  }) {
    _watchdog?.cancel();
    final wait = softExtend
        ? const Duration(milliseconds: 2500)
        : const Duration(milliseconds: 4000);
    _watchdog = Timer(wait, () async {
      if (!_isCurrent(gen) || _completed || _ttsStarted) return;
      if (_pcmConfirmed || player.playbackConfirmed) {
        debugPrint('⏱️ voice: watchdog — PCM already confirmed gen=$gen');
        return;
      }

      final active = player.state == PcmPlaybackState.playing ||
          player.state == PcmPlaybackState.queued ||
          player.state == PcmPlaybackState.receiving ||
          player.hasReceivedPcm;

      if (active && !softExtend && player.state != PcmPlaybackState.failed) {
        debugPrint(
          '⏱️ voice: PCM active (state=${player.state}) — extend watchdog gen=$gen',
        );
        _armWatchdog(gen, text, locale, softExtend: true);
        return;
      }

      debugPrint(
        '⚠️ voice: PCM not confirmed (state=${player.state} '
        'recv=${player.hasReceivedPcm}) → TTS gen=$gen',
      );
      await _fallbackTts(gen, text, locale);
    });
  }

  Future<void> onLivePcmChunk(Uint8List pcm) async {
    if (_ttsStarted || _completed) return;
    if (!player.acceptingPcm) return;
    _onSpeaking?.call();
    await player.feed(pcm);
  }

  /// Model turn finished — quick stall-drain, then free queue for next line.
  Future<void> onLiveTurnComplete() async {
    if (_endingTurn) return;
    final gen = _speechGeneration;
    if (!_isCurrent(gen) || _completed || _ttsStarted) return;
    _endingTurn = true;
    try {
      if (_pcmConfirmed || player.playbackConfirmed || player.hasReceivedPcm) {
        debugPrint('✅ voice: turn complete — quick drain gen=$gen');
        await player.endTurn();
        if (!_isCurrent(gen) || _completed) return;
        _finish(gen);
        return;
      }
      if (!player.hasReceivedPcm && _pendingText != null) {
        debugPrint('⚠️ voice: turn complete, no PCM → accelerate TTS gen=$gen');
        _watchdog?.cancel();
        unawaited(
          _fallbackTts(gen, _pendingText!, _pendingLocale ?? 'en-IN'),
        );
      }
    } finally {
      _endingTurn = false;
    }
  }

  Future<void> _fallbackTts(int gen, String text, String locale) async {
    if (!_isCurrent(gen) || _completed || _ttsStarted) return;
    if (_pcmConfirmed || player.playbackConfirmed) {
      _finish(gen);
      return;
    }

    _ttsStarted = true;
    player.setAcceptingPcm(false);
    await player.stop(keepInit: true);
    _watchdog?.cancel();
    _watchdog = null;

    debugPrint('🔊 voice: TTS fallback START gen=$gen locale=$locale');
    await speech.speak(
      text,
      language: locale,
      onComplete: () {
        if (!_isCurrent(gen)) return;
        debugPrint('🔊 voice: TTS fallback DONE gen=$gen');
        _finish(gen);
      },
    );
  }

  void _finish(int gen) {
    if (!_isCurrent(gen) || _completed) return;
    _completed = true;
    _watchdog?.cancel();
    _watchdog = null;
    _onListening?.call();
    final cb = _onComplete;
    _onComplete = null;
    cb?.call();
    if (_activeDone != null && !_activeDone!.isCompleted) {
      _activeDone!.complete();
    }
  }

  Future<void> interrupt() async {
    _queue.clear();
    _endingTurn = false;
    _speechGeneration++;
    _watchdog?.cancel();
    _watchdog = null;
    _completed = true;
    _ttsStarted = false;
    _pcmConfirmed = false;
    _pendingText = null;
    _pendingLocale = null;
    player.setAcceptingPcm(true);
    await player.stop(keepInit: true);
    await speech.stopSpeaking();
    _onListening?.call();
    if (_activeDone != null && !_activeDone!.isCompleted) {
      _activeDone!.complete();
    }
  }

  void dispose() {
    _queue.clear();
    _watchdog?.cancel();
    _watchdog = null;
  }
}
