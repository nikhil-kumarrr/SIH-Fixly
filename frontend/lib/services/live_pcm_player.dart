import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

/// PCM output lifecycle for Gemini Live (24 kHz mono s16le).
enum PcmPlaybackState {
  idle,
  receiving,
  queued,
  playing,
  completed,
  failed,
}

/// Streams Gemini Live PCM16 @ 24 kHz mono to the speaker.
/// Distinguishes packet arrival from confirmed speaker playback.
class LivePcmPlayer {
  AudioSource? _source;
  SoundHandle? _handle;
  bool _inited = false;
  bool _starting = false;
  bool _captureSession = false;
  Future<void>? _initInFlight;
  bool _ended = false;
  bool _playbackConfirmed = false;
  bool _acceptingPcm = true;
  int _bytesReceived = 0;
  int _bytesQueued = 0;
  PcmPlaybackState _state = PcmPlaybackState.idle;
  final List<Uint8List> _pending = [];
  Timer? _progressTimer;
  Duration _lastConsumed = Duration.zero;
  DateTime? _lastProgressAt;
  bool _stallLogged = false;

  void Function(PcmPlaybackState state)? onStateChanged;
  void Function()? onPlaybackConfirmed;
  void Function(Object error)? onPlaybackFailed;

  PcmPlaybackState get state => _state;
  bool get isPlaying => _state == PcmPlaybackState.playing;
  bool get isReady => _inited && SoLoud.instance.isInitialized;
  bool get playbackConfirmed => _playbackConfirmed;
  bool get acceptingPcm => _acceptingPcm;
  bool get hasReceivedPcm => _bytesReceived > 0;

  void _setState(PcmPlaybackState next) {
    if (_state == next) return;
    _state = next;
    onStateChanged?.call(next);
  }

  /// [forCapture] true = playAndRecord (live mic). false = playback only (chat speaker).
  Future<void> ensureInit({bool forCapture = true}) async {
    if (_inited && SoLoud.instance.isInitialized) return;
    if (_initInFlight != null) {
      await _initInFlight;
      return;
    }
    _initInFlight = _doEnsureInit(forCapture: forCapture);
    try {
      await _initInFlight;
    } finally {
      _initInFlight = null;
    }
  }

  Future<void> _doEnsureInit({required bool forCapture}) async {
    if (_inited && SoLoud.instance.isInitialized) {
      if (forCapture && !_captureSession) {
        await _configureSession(forCapture: true);
        _captureSession = true;
      }
      return;
    }
    await _configureSession(forCapture: forCapture);

    debugPrint('🎧 LivePcmPlayer SoLoud.init starting…');
    await SoLoud.instance.init(
      sampleRate: 24000,
      bufferSize: 2048,
      channels: Channels.mono,
    );
    try {
      SoLoud.instance.setGlobalVolume(1.0);
    } catch (e) {
      debugPrint('⚠️ LivePcmPlayer setGlobalVolume: $e');
    }
    _inited = true;
    _captureSession = forCapture;
    debugPrint('✅ LivePcmPlayer ready (24kHz mono s16le) capture=$forCapture');
  }

  Future<void> _configureSession({required bool forCapture}) async {
    try {
      final session = await AudioSession.instance;
      if (forCapture) {
        await session.configure(
          AudioSessionConfiguration(
            avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
            avAudioSessionCategoryOptions:
                AVAudioSessionCategoryOptions.defaultToSpeaker |
                    AVAudioSessionCategoryOptions.allowBluetooth |
                    AVAudioSessionCategoryOptions.mixWithOthers,
            avAudioSessionMode: AVAudioSessionMode.voiceChat,
            androidAudioAttributes: const AndroidAudioAttributes(
              contentType: AndroidAudioContentType.speech,
              usage: AndroidAudioUsage.media,
            ),
            androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
            androidWillPauseWhenDucked: false,
          ),
        );
      } else {
        // Chat speak-only: no mic — avoid playAndRecord hang without permission.
        await session.configure(
          const AudioSessionConfiguration(
            avAudioSessionCategory: AVAudioSessionCategory.playback,
            avAudioSessionCategoryOptions:
                AVAudioSessionCategoryOptions.duckOthers,
            avAudioSessionMode: AVAudioSessionMode.spokenAudio,
            androidAudioAttributes: AndroidAudioAttributes(
              contentType: AndroidAudioContentType.speech,
              usage: AndroidAudioUsage.media,
            ),
            androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
            androidWillPauseWhenDucked: false,
          ),
        );
      }
      await session.setActive(true);
    } catch (e) {
      debugPrint('❌ LivePcmPlayer audio session: $e');
    }
  }

  /// Reject late PCM for a response that already fell back to TTS.
  void setAcceptingPcm(bool value) {
    _acceptingPcm = value;
  }

  Future<void> feed(Uint8List pcm) async {
    if (!_acceptingPcm) return;
    // s16le needs even byte count; ignore tiny/junk packets (e.g. 2 bytes).
    if (pcm.length < 4 || pcm.length.isOdd) {
      debugPrint('⚠️ PCM skip invalid packet bytes=${pcm.length}');
      return;
    }

    _bytesReceived += pcm.length;
    debugPrint('🎧 PCM RECEIVED bytes=${pcm.length} total=$_bytesReceived');
    _setState(PcmPlaybackState.receiving);

    try {
      // After setDataIsEnded, late packets must NOT restart stream (that calls stop()).
      if (_source != null && !_ended) {
        SoLoud.instance.addAudioDataStream(_source!, pcm);
        _bytesQueued += pcm.length;
        debugPrint('🎧 PCM QUEUED bytes=${pcm.length} totalQueued=$_bytesQueued');
        _setState(PcmPlaybackState.queued);
        _armProgressWatch();
        return;
      }

      if (_source != null && _ended) {
        // Turn already ending — drop late packets; drain handles the rest.
        debugPrint('⚠️ PCM late after endTurn bytes=${pcm.length} — drop');
        return;
      }

      _pending.add(pcm);
      _bytesQueued += pcm.length;
      debugPrint(
        '🎧 PCM QUEUED bytes=${pcm.length} totalQueued=$_bytesQueued '
        'pending=${_pending.length}',
      );
      _setState(PcmPlaybackState.queued);
      if (!_starting) {
        _starting = true;
        try {
          await _beginStream();
        } finally {
          _starting = false;
        }
      }
    } catch (e) {
      debugPrint('❌ PCM PLAYBACK FAILED feed: $e');
      _setState(PcmPlaybackState.failed);
      onPlaybackFailed?.call(e);
      _ended = true;
      _pending.add(pcm);
      if (!_starting && _acceptingPcm) {
        _starting = true;
        try {
          await _beginStream();
        } finally {
          _starting = false;
        }
      }
    }
  }

  Future<void> _beginStream() async {
    await ensureInit();
    await stop(keepInit: true, silent: true);
    _ended = false;
    _playbackConfirmed = false;
    _lastConsumed = Duration.zero;
    _lastProgressAt = DateTime.now();
    _stallLogged = false;
    _bytesQueued = 0;

    _source = SoLoud.instance.setBufferStream(
      bufferingType: BufferingType.released,
      bufferingTimeNeeds: 0.05,
      sampleRate: 24000,
      channels: Channels.mono,
      format: BufferType.s16le,
      maxBufferSizeBytes: 1024 * 1024 * 8,
      onBuffering: (isBuffering, handle, time) {
        debugPrint(
          '🎧 PCM buffering=$isBuffering handle=$handle time=${time.toStringAsFixed(3)}s',
        );
        if (!isBuffering && time > 0.02) {
          _confirmPlayback();
        }
      },
    );

    for (final chunk in _pending) {
      SoLoud.instance.addAudioDataStream(_source!, chunk);
      _bytesQueued += chunk.length;
    }
    _pending.clear();

    _handle = SoLoud.instance.play(_source!);
    try {
      SoLoud.instance.setVolume(_handle!, 1.0);
    } catch (_) {}
    debugPrint('🔊 PCM PLAYBACK STARTED handle=$_handle volume=1.0 (media/speaker)');
    _setState(PcmPlaybackState.playing);
    _armProgressWatch();
  }

  void _armProgressWatch() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      _pollProgress();
    });
  }

  void _pollProgress() {
    final src = _source;
    if (src == null || _ended) return;
    try {
      final consumed = SoLoud.instance.getStreamTimeConsumed(src);
      if (consumed > _lastConsumed) {
        debugPrint(
          '🔊 PCM PLAYBACK PROGRESS ${consumed.inMilliseconds}ms '
          '(+${(consumed - _lastConsumed).inMilliseconds}ms)',
        );
        _lastConsumed = consumed;
        _lastProgressAt = DateTime.now();
        _stallLogged = false;
      } else if (_lastProgressAt != null &&
          DateTime.now().difference(_lastProgressAt!) >
              const Duration(milliseconds: 1800) &&
          _bytesReceived > 0 &&
          !_playbackConfirmed) {
        if (!_stallLogged) {
          _stallLogged = true;
          debugPrint('⚠️ PCM PLAYBACK STALLED');
        }
      }
      if (consumed.inMilliseconds >= 25) {
        _confirmPlayback();
      }
    } catch (e) {
      debugPrint('⚠️ PCM progress poll: $e');
      _setState(PcmPlaybackState.failed);
      onPlaybackFailed?.call(e);
    }
  }

  void _confirmPlayback() {
    if (_playbackConfirmed || !_acceptingPcm) return;
    _playbackConfirmed = true;
    debugPrint('✅ PCM PLAYBACK CONFIRMED');
    _setState(PcmPlaybackState.playing);
    onPlaybackConfirmed?.call();
  }

  Future<void> endTurn() async {
    // Fast path: don't block conversation on byte-perfect drain.
    // Wait until playback stalls (~done), max ~1.2s.
    await waitForPlaybackDrain();
    try {
      if (_source != null) {
        SoLoud.instance.setDataIsEnded(_source!);
      }
    } catch (e) {
      debugPrint('LivePcmPlayer endTurn setDataIsEnded: $e');
    }
    _ended = true;
    _progressTimer?.cancel();
    _progressTimer = null;
    if (_playbackConfirmed) {
      _setState(PcmPlaybackState.completed);
    }
    await stop(keepInit: true, silent: true);
  }

  /// Done when progress stalls (audio finished) — not when byte math matches.
  /// Caps wait so next utterance / speaker tap isn't blocked for tens of seconds.
  Future<void> waitForPlaybackDrain({
    Duration stall = const Duration(milliseconds: 350),
    Duration maxWait = const Duration(milliseconds: 1200),
  }) async {
    if (_bytesReceived < 4) return;
    debugPrint(
      '🎧 PCM drain start bytes=$_bytesReceived '
      'consumed=${_lastConsumed.inMilliseconds}ms',
    );
    var lastMs = _lastConsumed.inMilliseconds;
    var lastBump = DateTime.now();
    final deadline = DateTime.now().add(maxWait);

    while (DateTime.now().isBefore(deadline)) {
      final src = _source;
      if (src != null) {
        try {
          final consumed = SoLoud.instance.getStreamTimeConsumed(src);
          _lastConsumed = consumed;
          final ms = consumed.inMilliseconds;
          if (ms > lastMs + 20) {
            lastMs = ms;
            lastBump = DateTime.now();
          } else if (ms >= 150 &&
              DateTime.now().difference(lastBump) >= stall) {
            debugPrint('✅ PCM drain stall-complete ${ms}ms');
            return;
          }
          // Near expected length — finish without waiting for exact match.
          final expectedMs = (_bytesReceived / 2 / 24000 * 1000).round();
          if (expectedMs > 0 && ms >= (expectedMs * 0.92).round()) {
            debugPrint('✅ PCM drain ~complete ${ms}ms / ${expectedMs}ms');
            return;
          }
        } catch (e) {
          debugPrint('⚠️ PCM drain poll: $e — done');
          return;
        }
      } else {
        debugPrint('✅ PCM drain (no source)');
        return;
      }
      await Future.delayed(const Duration(milliseconds: 40));
    }
    debugPrint(
      '✅ PCM drain max-wait bytes=$_bytesReceived '
      'last=${_lastConsumed.inMilliseconds}ms',
    );
  }

  Future<void> stop({bool keepInit = false, bool silent = false}) async {
    _progressTimer?.cancel();
    _progressTimer = null;
    _ended = true;
    _pending.clear();
    try {
      if (_handle != null) {
        await SoLoud.instance.stop(_handle!);
      }
    } catch (_) {}
    _handle = null;
    try {
      if (_source != null) {
        await SoLoud.instance.disposeSource(_source!);
      }
    } catch (_) {}
    _source = null;
    if (!silent) {
      _setState(PcmPlaybackState.idle);
    }
  }

  Future<void> dispose() async {
    await stop();
    _acceptingPcm = true;
    _playbackConfirmed = false;
    _bytesReceived = 0;
  }

  void resetForNewResponse() {
    _playbackConfirmed = false;
    _acceptingPcm = true;
    _bytesReceived = 0;
    _bytesQueued = 0;
    _lastConsumed = Duration.zero;
    _lastProgressAt = null;
    _stallLogged = false;
    _setState(PcmPlaybackState.idle);
  }
}
