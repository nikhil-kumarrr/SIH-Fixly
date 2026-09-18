import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// Continuous mono PCM16 @ 16 kHz capture for Gemini Live.
class LivePcmCapture {
 final AudioRecorder _recorder = AudioRecorder();
 StreamSubscription<Uint8List>? _sub;
 bool _running = false;
 bool muted = false;

 void Function(Uint8List pcm)? onPcm;
 void Function(double rms01)? onLevel;

 bool get isRunning => _running;

 Future<bool> ensureMicPermission() async {
 final status = await Permission.microphone.request();
 return status.isGranted || status.isLimited;
 }

 Future<void> start() async {
 if (_running) return;
 final ok = await ensureMicPermission();
 if (!ok) {
 throw StateError('Microphone permission denied');
 }
 if (!await _recorder.hasPermission()) {
 throw StateError('Recorder has no mic permission');
 }

 final stream = await _recorder.startStream(
 const RecordConfig(
 encoder: AudioEncoder.pcm16bits,
 sampleRate: 16000,
 numChannels: 1,
 autoGain: true,
 echoCancel: true,
 noiseSuppress: true,
 ),
 );

 _running = true;
 _sub = stream.listen(
 (chunk) {
 if (chunk.isEmpty) return;
 onLevel?.call(_rms01(chunk));
 if (muted) return;
 onPcm?.call(chunk);
 },
 onError: (e) => debugPrint('LivePcmCapture stream error: $e'),
 );
 }

 Future<void> stop() async {
 _running = false;
 muted = false;
 await _sub?.cancel();
 _sub = null;
 try {
 if (await _recorder.isRecording()) {
 await _recorder.stop();
 }
 } catch (e) {
 debugPrint('LivePcmCapture stop: $e');
 }
 }

 Future<void> dispose() async {
 await stop();
 await _recorder.dispose();
 }

 static double _rms01(Uint8List pcm) {
 if (pcm.length < 2) return 0;
 final bd = ByteData.sublistView(pcm);
 final samples = pcm.length ~/ 2;
 var sum = 0.0;
 for (var i = 0; i < samples; i++) {
 final s = bd.getInt16(i * 2, Endian.little) / 32768.0;
 sum += s * s;
 }
 final rms = math.sqrt(sum / samples);
 return (rms * 4.0).clamp(0.0, 1.0);
 }
}
