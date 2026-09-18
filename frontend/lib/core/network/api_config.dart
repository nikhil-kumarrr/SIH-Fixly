import 'package:flutter/foundation.dart' show ValueNotifier;

/// API configuration — change [baseUrl] to point to your backend.
class ApiConfig {
  ApiConfig._();

  // ─── ✏️  CHANGE THIS to your backend URL ───────────────────────────────────
  //
  //  Android emulator (AVD):         http://10.0.2.2:8000
  //  iOS Simulator:                  http://localhost:8000
  //  Physical device (your WiFi):    http://192.168.29.34:8000  ← current LAN
  //  Tunnel / production:            https://your-tunnel-url.com
  //
  // Local backend (this Mac :8000) — Android emulator connects via 10.0.2.2:8000
  // static const String baseUrl = 'http://10.0.2.2:8000';
  static const String baseUrl = 'http://fexily-lb-380632449.ap-south-1.elb.amazonaws.com';

  // ───────────────────────────────────────────────────────────────────────────

  /// Notifier in case any widget needs to react to URL changes at runtime.
  static final ValueNotifier<String> urlNotifier = ValueNotifier<String>(
    baseUrl,
  );
}
