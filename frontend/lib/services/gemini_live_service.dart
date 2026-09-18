import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Thin Gemini Live WebSocket client (hybrid: audio/text in, tool out).
/// Uses ephemeral token from backend. Falls back callers handle STT/TTS.
class GeminiLiveService {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  bool _setupDone = false;
  /// Suppress [onClosed]/[onError] while we intentionally tear down.
  bool _suppressClose = false;
  Completer<void>? _setupCompleter;

  void Function(String transcript)? onUserTranscript;
  void Function(String transcript)? onModelTranscript;
  void Function(Uint8List pcm)? onAudioChunk;
  void Function(Map<String, dynamic> call)? onToolCall;
  void Function()? onTurnComplete;
  void Function()? onInterrupted;
  void Function()? onSetupComplete;
  void Function(Object error)? onError;
  void Function()? onClosed;

  bool get isConnected => _channel != null;
  bool get setupComplete => _setupDone;

  /// Connect and wait until Live `setupComplete` (or [timeout]).
  Future<void> connect({
    required String websocketUrl,
    required String model,
    required String systemLanguage,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    await disconnect();
    _setupDone = false;
    _suppressClose = false;
    final setupWait = Completer<void>();
    _setupCompleter = setupWait;

    _channel = WebSocketChannel.connect(Uri.parse(websocketUrl));
    _sub = _channel!.stream.listen(
      _onMessage,
      onError: (e) {
        if (_suppressClose) return;
        if (!(setupWait.isCompleted)) {
          setupWait.completeError(e);
        }
        onError?.call(e);
      },
      onDone: () {
        if (_suppressClose) return;
        if (!(setupWait.isCompleted)) {
          setupWait.completeError(StateError('Live WS closed before setup'));
        }
        onClosed?.call();
        _channel = null;
      },
    );

    // Constrained tokens already lock config server-side — keep client setup minimal
    // so we don't fight the token constraints.
    final setup = <String, dynamic>{
      'setup': {
        'model': 'models/$model',
        'generationConfig': {
          'responseModalities': ['AUDIO'],
        },
      },
    };
    _channel!.sink.add(jsonEncode(setup));

    try {
      await setupWait.future.timeout(timeout);
    } on TimeoutException {
      await disconnect();
      throw TimeoutException('Live setup timed out');
    } catch (e) {
      await disconnect();
      rethrow;
    } finally {
      if (identical(_setupCompleter, setupWait)) {
        _setupCompleter = null;
      }
    }
  }

  void sendRealtimeText(String text, {bool commitTurn = false}) {
    if (_channel == null) return;
    _channel!.sink.add(
      jsonEncode({
        'realtimeInput': {'text': text},
      }),
    );
    // No mic stream (chat speak-only): flush so model starts AUDIO reply.
    if (commitTurn) {
      _channel!.sink.add(
        jsonEncode({
          'realtimeInput': {'audioStreamEnd': true},
        }),
      );
      debugPrint('🎙️ Live text turn committed (audioStreamEnd)');
    }
  }

  void sendAudioPcm16le(Uint8List pcm, {String mime = 'audio/pcm;rate=16000'}) {
    if (_channel == null) return;
    _channel!.sink.add(
      jsonEncode({
        'realtimeInput': {
          'audio': {
            'mimeType': mime,
            'data': base64Encode(pcm),
          },
        },
      }),
    );
  }

  void sendToolResponse({
    required String id,
    required String name,
    required Object response,
  }) {
    if (_channel == null) return;
    _channel!.sink.add(
      jsonEncode({
        'toolResponse': {
          'functionResponses': [
            {
              'id': id,
              'name': name,
              'response': response is Map ? response : {'result': response},
            },
          ],
        },
      }),
    );
  }

  void _onMessage(dynamic raw) {
    try {
      final data = raw is String
          ? jsonDecode(raw) as Map<String, dynamic>
          : jsonDecode(utf8.decode(raw as List<int>)) as Map<String, dynamic>;

      if (data['setupComplete'] != null) {
        _setupDone = true;
        final c = _setupCompleter;
        if (c != null && !c.isCompleted) c.complete();
        onSetupComplete?.call();
        return;
      }

      // Surface server errors instead of silent drop.
      final err = data['error'];
      if (err != null) {
        debugPrint('GeminiLive server error: $err');
        final c = _setupCompleter;
        if (c != null && !c.isCompleted) {
          c.completeError(StateError(err.toString()));
        }
        onError?.call(err);
        return;
      }

      final toolCall = data['toolCall'] as Map<String, dynamic>?;
      if (toolCall != null) {
        onToolCall?.call(toolCall);
      }

      final serverContent = data['serverContent'] as Map<String, dynamic>?;
      if (serverContent == null) return;

      if (serverContent['interrupted'] == true) {
        onInterrupted?.call();
      }

      final modelTurn = serverContent['modelTurn'] as Map<String, dynamic>?;
      final parts = (modelTurn?['parts'] as List?) ?? const [];
      for (final part in parts) {
        if (part is! Map) continue;
        final text = part['text']?.toString();
        if (text != null && text.isNotEmpty) {
          onModelTranscript?.call(text);
        }
        final inline = part['inlineData'] as Map<String, dynamic>?;
        if (inline != null && inline['data'] != null) {
          onAudioChunk?.call(base64Decode(inline['data'] as String));
        }
      }

      final inputTx = serverContent['inputTranscription'] as Map<String, dynamic>?;
      final inText = inputTx?['text']?.toString();
      if (inText != null && inText.isNotEmpty) {
        onUserTranscript?.call(inText);
      }
      final outputTx = serverContent['outputTranscription'] as Map<String, dynamic>?;
      final outText = outputTx?['text']?.toString();
      if (outText != null && outText.isNotEmpty) {
        onModelTranscript?.call(outText);
      }

      if (serverContent['turnComplete'] == true ||
          serverContent['generationComplete'] == true) {
        onTurnComplete?.call();
      }
    } catch (e) {
      debugPrint('GeminiLive parse error: $e');
      onError?.call(e);
    }
  }

  Future<void> disconnect() async {
    _suppressClose = true;
    final c = _setupCompleter;
    if (c != null && !c.isCompleted) {
      c.completeError(StateError('Live disconnected'));
    }
    _setupCompleter = null;
    await _sub?.cancel();
    _sub = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _setupDone = false;
    // Keep suppress briefly so late onDone is ignored.
    Future<void>.delayed(const Duration(milliseconds: 80), () {
      _suppressClose = false;
    });
  }
}
