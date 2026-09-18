import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Live-mode UI SFX — dynamic timeline, never loops.
///
/// Timeline:
/// - Live tap → [start]
/// - +2s while still open → [th1] (thinking bed)
/// - +7.5s still waiting on API/reply → [th2]
/// - Response ready → cancel wait cues → [end] → caller speaks
///
/// Easy to delete later (TEMP test assets under `assets/sounds/live/`).
class LiveUiSounds {
  LiveUiSounds._();
  static final LiveUiSounds instance = LiveUiSounds._();

  final AudioPlayer _player = AudioPlayer();

  static const _start = 'sounds/live/start.mp3';
  static const _th1 = 'sounds/live/th1.mp3';
  static const _th2 = 'sounds/live/th2.mp3';
  static const _end = 'sounds/live/end.mp3';

  static const _th1After = Duration(seconds: 2);
  static const _th2After = Duration(milliseconds: 7500);

  int _gen = 0;
  bool _active = false;
  bool _waiting = false;
  bool _th1Done = false;
  bool _th2Done = false;
  Timer? _th1Timer;
  Timer? _th2Timer;

  bool get isActive => _active;

  /// Live button: play start sound only.
  Future<void> beginLiveSession() async {
    await stop();
    _active = true;
    final gen = ++_gen;
    _waiting = false;
    _th1Done = false;
    _th2Done = false;
    debugPrint('🔔 live-ui session begin gen=$gen');
    await _playOnce(_start, volume: 0.85, wait: true, gen: gen);
  }

  /// User utterance / tool / API in flight — keep wait cues alive on every turn.
  void markThinking() {
    if (!_active) return;
    final gen = _gen;
    _waiting = true;
    _th1Done = false;
    _th2Done = false;
    _cancelTimers();
    debugPrint('🔔 live-ui markThinking gen=$gen');
    _armTh1(gen);
    _armTh2(gen);
  }

  /// Model / agent started talking — cancel wait cues (no end).
  void markSpeaking() {
    if (!_active) return;
    _waiting = false;
    _cancelTimers();
    debugPrint('🔔 live-ui markSpeaking — wait cues cancelled');
  }

  /// Response ready: play end cue.
  Future<void> cueBeforeSpeak() async {
    if (!_active) return;
    final gen = _gen;
    _waiting = false;
    _cancelTimers();
    debugPrint('🔔 live-ui cueBeforeSpeak (end) gen=$gen');
    await _playOnce(_end, volume: 0.85, wait: true, gen: gen);
  }

  /// API / Live error — silence SFX immediately.
  Future<void> failAndStop() async {
    debugPrint('🔔 live-ui failAndStop');
    await stop();
  }

  /// Stop current clip without ending the live SFX session.
  Future<void> hush() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  Future<void> stop() async {
    _active = false;
    _waiting = false;
    _gen++;
    _cancelTimers();
    await hush();
  }

  void _cancelTimers() {
    _th1Timer?.cancel();
    _th1Timer = null;
    _th2Timer?.cancel();
    _th2Timer = null;
  }

  void _armTh1(int gen) {
    _th1Timer?.cancel();
    if (_th1Done) return;
    _th1Timer = Timer(_th1After, () {
      if (!_active || !_waiting || gen != _gen || _th1Done) return;
      unawaited(_playTh1(gen));
    });
  }

  void _armTh2(int gen) {
    _th2Timer?.cancel();
    if (_th2Done) return;
    _th2Timer = Timer(_th2After, () {
      if (!_active || !_waiting || gen != _gen || _th2Done) return;
      unawaited(_playTh2(gen));
    });
  }

  Future<void> _playTh1(int gen) async {
    if (!_active || gen != _gen || _th1Done) return;
    _th1Done = true;
    await _playOnce(_th1, volume: 0.7, gen: gen);
  }

  Future<void> _playTh2(int gen) async {
    if (!_active || !_waiting || gen != _gen || _th2Done) return;
    _th2Done = true;
    await _playOnce(_th2, volume: 0.75, gen: gen);
  }

  Future<void> _playOnce(
    String asset, {
    double volume = 1.0,
    bool wait = false,
    required int gen,
  }) async {
    if (!_active || gen != _gen) return;
    try {
      await _player.stop();
      // Never loop — one shot only.
      await _player.setReleaseMode(ReleaseMode.release);
      await _player.setVolume(volume);
      debugPrint('🔔 live-ui sfx: $asset wait=$wait gen=$gen');
      await _player.play(AssetSource(asset));
      if (wait) {
        try {
          await _player.onPlayerComplete.first.timeout(const Duration(milliseconds: 1200));
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('⚠️ live-ui sfx error ($asset): $e');
    }
  }

  Future<void> dispose() async {
    await stop();
    await _player.dispose();
  }
}
