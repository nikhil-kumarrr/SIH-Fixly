import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Android binding that drops mouse, stylus, and trackpad pointer events.
///
/// OnePlus (Oplus) injects hover events as [PointerDeviceKind.mouse] beside
/// each touch. [MouseTracker] then re-enters `_deviceUpdatePhase` and debug
/// builds assert `!_debugDuringDeviceUpdate` on every frame. Touch is kept.
class FixlyWidgetsBinding extends WidgetsFlutterBinding {
  static WidgetsBinding ensureInitialized() {
    if (BindingBase.debugBindingType() == null) {
      FixlyWidgetsBinding();
    }
    return WidgetsBinding.instance;
  }

  @override
  void dispatchEvent(PointerEvent event, HitTestResult? hitTestResult) {
    if (defaultTargetPlatform == TargetPlatform.android &&
        _isNonTouchPointer(event.kind)) {
      return;
    }
    super.dispatchEvent(event, hitTestResult);
  }

  static bool _isNonTouchPointer(PointerDeviceKind kind) {
    return switch (kind) {
      PointerDeviceKind.mouse ||
      PointerDeviceKind.stylus ||
      PointerDeviceKind.invertedStylus ||
      PointerDeviceKind.trackpad => true,
      PointerDeviceKind.touch || PointerDeviceKind.unknown => false,
    };
  }
}
