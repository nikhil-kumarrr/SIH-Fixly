import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// In-app call tones: ringtone (incoming) + calling/ringback (outgoing).
class CallSoundService {
  CallSoundService._();
  static final CallSoundService instance = CallSoundService._();

  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;
  String? _currentAsset;

  Future<void> playRingtone() => _loop('sounds/ringtone.wav');

  Future<void> playCalling() => _loop('sounds/calling.wav');

  Future<void> stop() async {
    if (!_playing && _currentAsset == null) return;
    try {
      await _player.stop();
      await _player.release();
    } catch (e) {
      debugPrint('[CallSound] stop error: $e');
    }
    _playing = false;
    _currentAsset = null;
  }

  Future<void> _loop(String asset) async {
    if (_playing && _currentAsset == asset) return;
    try {
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(1.0);
      await _player.play(AssetSource(asset));
      _playing = true;
      _currentAsset = asset;
    } catch (e) {
      debugPrint('[CallSound] play $asset error: $e');
      _playing = false;
      _currentAsset = null;
    }
  }

  Future<void> dispose() async {
    await stop();
    await _player.dispose();
  }
}
