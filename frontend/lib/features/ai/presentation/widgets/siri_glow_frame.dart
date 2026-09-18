import 'dart:math' as math;
import 'package:flutter/material.dart';

/// iOS 18 Apple Intelligence / Siri Screen Edge Glow Frame.
/// Features:
/// 1. True 4-side perimeter loop animation (Top -> Right -> Bottom -> Left -> Top)
///    with zero corner bunching and perfectly uniform linear travel speed.
/// 2. Responsive display geometry (flat, box, square, or curved) with edge-to-edge flush bounds.
/// 3. Balanced Apple-proportioned border width (+2-3px punchy ribbon, 0% obstruction of tab bar).
/// 4. Figma 4-step progressive color morphing (Start -> Step 1 -> Step 2 -> End).
enum SiriGlowMode { idle, listening, thinking, speaking }

class SiriGlowFrame extends StatefulWidget {
  const SiriGlowFrame({
    super.key,
    required this.child,
    this.active = true,
    this.mode = SiriGlowMode.idle,
    this.borderRadius = 0.0,
    this.voiceActivity = 0.0,
  });

  final Widget child;
  final bool active;
  final SiriGlowMode mode;
  final double borderRadius;
  final double voiceActivity;

  @override
  State<SiriGlowFrame> createState() => _SiriGlowFrameState();
}

class _SiriGlowFrameState extends State<SiriGlowFrame>
    with TickerProviderStateMixin {
  late final AnimationController _perimeterLoop;
  late final AnimationController _breathPulse;
  late final AnimationController _colorMorph;

  double _smoothedVoice = 0.0;

  @override
  void initState() {
    super.initState();
    // 1. Continuous smooth 4-side perimeter loop (2.8s full rotation around all 4 edges)
    _perimeterLoop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();

    // 2. Subtle breathing pulse (1200ms cycle)
    _breathPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    // 3. Smooth step-by-step color morphing through all 4 Figma steps (4000ms: 1s per step)
    _colorMorph = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat();
  }

  double get _baseIntensity {
    switch (widget.mode) {
      case SiriGlowMode.speaking:
        return 1.40;
      case SiriGlowMode.thinking:
        return 1.25;
      case SiriGlowMode.listening:
        return 1.20;
      case SiriGlowMode.idle:
        return 1.05;
    }
  }

  @override
  void dispose() {
    _perimeterLoop.dispose();
    _breathPulse.dispose();
    _colorMorph.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;

    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    final targetVoice = widget.mode == SiriGlowMode.speaking
        ? math.max(widget.voiceActivity, 0.50)
        : widget.voiceActivity;
    _smoothedVoice = _smoothedVoice * 0.85 + targetVoice * 0.15;

    return AnimatedBuilder(
      animation: Listenable.merge([_perimeterLoop, _breathPulse, _colorMorph]),
      builder: (context, child) {
        final pulse = reduceMotion ? 0.5 : _breathPulse.value;
        final intensity = _baseIntensity * (0.90 + 0.20 * pulse) + (_smoothedVoice * 0.25);
        final loopProgress = reduceMotion ? 0.0 : _perimeterLoop.value;
        final colorProgress = reduceMotion ? 0.0 : _colorMorph.value;

        return CustomPaint(
          foregroundPainter: _Ios18SiriEdgeGlowPainter(
            loopProgress: loopProgress,
            colorProgress: colorProgress,
            intensity: intensity,
            pulse: pulse,
            voiceActivity: _smoothedVoice,
            mode: widget.mode,
            borderRadius: widget.borderRadius,
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Official iOS 18 Apple Intelligence / Siri real-time cycling edge glow painter.
/// Uses perimeter-to-angle ray-box intersection to guarantee that the glowing light wave
/// travels around the 4 sides of the screen (Top -> Right -> Bottom -> Left)
/// at completely constant linear speed, with zero corner bunching.
class _Ios18SiriEdgeGlowPainter extends CustomPainter {
  _Ios18SiriEdgeGlowPainter({
    required this.loopProgress,
    required this.colorProgress,
    required this.intensity,
    required this.pulse,
    required this.voiceActivity,
    required this.mode,
    required this.borderRadius,
  });

  final double loopProgress;
  final double colorProgress;
  final double intensity;
  final double pulse;
  final double voiceActivity;
  final SiriGlowMode mode;
  final double borderRadius;

  // ── Exact 7 Colors from Figma Community iOS 18 Siri Design ──
  static const _cLilac   = Color(0xFFBC82F3); // Soft Lilac
  static const _cPink    = Color(0xFFF589EA); // Vivid Pink
  static const _cBlue    = Color(0xFF8D99FF); // Siri Blue
  static const _cViolet  = Color(0xFFAA5EEE); // Electric Violet
  static const _cCoral   = Color(0xFFFF6778); // Radiant Coral
  static const _cAmber   = Color(0xFFFFBA71); // Peach Amber
  static const _cMauve   = Color(0xFFC888FF); // Bright Mauve

  // ── Figma Step 0: Start (Node 1-14) ──
  static const _step0Colors = <Color>[
    _cLilac, _cLilac, _cPink, _cBlue, _cViolet, _cCoral, _cAmber, _cMauve, _cLilac,
  ];
  static const _step0Stops = <double>[
    0.00, 0.17, 0.24, 0.35, 0.58, 0.70, 0.81, 0.92, 1.00,
  ];

  // ── Figma Step 1: (Node 1-17) ──
  static const _step1Colors = <Color>[
    _cViolet, _cViolet, _cBlue, _cPink, _cAmber, _cLilac, _cMauve, _cCoral, _cViolet,
  ];
  static const _step1Stops = <double>[
    0.00, 0.08, 0.14, 0.26, 0.31, 0.33, 0.42, 0.70, 1.00,
  ];

  // ── Figma Step 2: (Node 1-22) ──
  static const _step2Colors = <Color>[
    _cMauve, _cMauve, _cPink, _cAmber, _cViolet, _cCoral, _cLilac, _cBlue, _cMauve,
  ];
  static const _step2Stops = <double>[
    0.00, 0.08, 0.16, 0.28, 0.32, 0.41, 0.57, 0.75, 1.00,
  ];

  // ── Figma Step 3: End (Node 1-27) ──
  static const _step3Colors = <Color>[
    _cMauve, _cMauve, _cAmber, _cCoral, _cViolet, _cBlue, _cPink, _cLilac, _cMauve,
  ];
  static const _step3Stops = <double>[
    0.00, 0.08, 0.19, 0.30, 0.42, 0.64, 0.76, 0.83, 1.00,
  ];

  static const _allStepsColors = [_step0Colors, _step1Colors, _step2Colors, _step3Colors];
  static const _allStepsStops = [_step0Stops, _step1Stops, _step2Stops, _step3Stops];

  /// Interpolates between the 4 Figma steps step-by-step with sinusoidal easing
  ({List<Color> colors, List<double> stops}) _interpolateSteps() {
    final stepProgress = (colorProgress * 4.0);
    final fromStep = stepProgress.floor() % 4;
    final toStep = (fromStep + 1) % 4;
    final rawT = stepProgress - stepProgress.floor();

    final t = (1.0 - math.cos(rawT * math.pi)) / 2.0;

    final fromColors = _allStepsColors[fromStep];
    final toColors = _allStepsColors[toStep];
    final fromStops = _allStepsStops[fromStep];
    final toStops = _allStepsStops[toStep];

    final colors = List<Color>.generate(
      9,
      (i) => Color.lerp(fromColors[i], toColors[i], t)!,
    );
    final stops = List<double>.generate(
      9,
      (i) => fromStops[i] * (1.0 - t) + toStops[i] * t,
    );

    return (colors: colors, stops: stops);
  }

  Color _sampleFigmaSpectrum(({List<Color> colors, List<double> stops}) stepData, double frac) {
    final p = frac.clamp(0.0, 1.0);
    for (int i = 0; i < stepData.stops.length - 1; i++) {
      final s0 = stepData.stops[i];
      final s1 = stepData.stops[i + 1];
      if (p >= s0 && p <= s1) {
        final span = s1 - s0;
        final t = span > 0 ? (p - s0) / span : 0.0;
        return Color.lerp(stepData.colors[i], stepData.colors[i + 1], t)!;
      }
    }
    return stepData.colors.last;
  }

  /// Builds a 64-stop SweepGradient shader where every angle stop is mapped
  /// to its exact perimeter intersection point. This ensures that colors
  /// move around all 4 edges of the screen at perfectly constant linear speed.
  ({List<Color> colors, List<double> stops}) _buildPerimeterCorrectedSweep(Size size) {
    final W = size.width;
    final H = size.height;
    final P = 2 * (W + H);
    final cx = W / 2.0;
    final cy = H / 2.0;

    final stepData = _interpolateSteps();

    const numStops = 64;
    final stops = <double>[];
    final colors = <Color>[];

    for (int i = 0; i <= numStops; i++) {
      final angleFrac = i / numStops;
      final theta = angleFrac * 2 * math.pi;
      final dx = math.cos(theta);
      final dy = math.sin(theta);

      // Ray-box intersection from (cx, cy) in direction (dx, dy)
      double t = double.infinity;
      if (dx > 1e-6) {
        final tr = (W - cx) / dx;
        if (tr > 0 && tr < t) t = tr;
      } else if (dx < -1e-6) {
        final tl = (0 - cx) / dx;
        if (tl > 0 && tl < t) t = tl;
      }
      if (dy > 1e-6) {
        final tb = (H - cy) / dy;
        if (tb > 0 && tb < t) t = tb;
      } else if (dy < -1e-6) {
        final tt = (0 - cy) / dy;
        if (tt > 0 && tt < t) t = tt;
      }

      final px = (cx + t * dx).clamp(0.0, W);
      final py = (cy + t * dy).clamp(0.0, H);

      // Calculate perimeter distance s starting clockwise from Top-Left (0,0):
      double s;
      if (py <= 1.0) {
        s = px; // Top edge: 0 -> W
      } else if (px >= W - 1.0) {
        s = W + py; // Right edge: W -> W + H
      } else if (py >= H - 1.0) {
        s = W + H + (W - px); // Bottom edge: W + H -> 2W + H
      } else {
        s = 2 * W + H + (H - py); // Left edge: 2W + H -> 2W + 2H
      }

      // Linear perimeter progression with constant travel speed along 4 sides
      final perimeterFrac = (s / P + loopProgress) % 1.0;
      final sampledColor = _sampleFigmaSpectrum(stepData, perimeterFrac);

      stops.add(angleFrac);
      colors.add(sampledColor);
    }

    return (colors: colors, stops: stops);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // Edge-to-edge flush rectangle hugging the screen edges
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = borderRadius > 0
        ? RRect.fromRectAndRadius(rect, Radius.circular(borderRadius))
        : RRect.fromRectAndRadius(rect, Radius.zero);

    final sweepData = _buildPerimeterCorrectedSweep(size);

    // ── Balanced Apple Siri Border Width (+2-3px punchy ribbon) ──
    //
    // Layer 1: Outer atmospheric bloom (width: 13.5px, blur: 6.5px)
    final bloomWidth = (13.5 + 2.5 * pulse + 1.5 * voiceActivity) * intensity.clamp(0.85, 1.25);
    final bloomBlur = 6.5 + 1.5 * pulse;
    final bloomPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = bloomWidth
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, bloomBlur)
      ..shader = SweepGradient(
        center: Alignment.center,
        colors: sweepData.colors
            .map((c) => c.withValues(alpha: (0.75 * intensity).clamp(0.0, 0.95)))
            .toList(),
        stops: sweepData.stops,
      ).createShader(rect);
    canvas.drawRRect(rrect, bloomPaint);

    // Layer 2: Core razor-sharp Apple Intelligence light ribbon (width: 5.5px, blur: 1.5px)
    final coreWidth = (5.5 + 1.2 * pulse + 1.0 * voiceActivity) * intensity.clamp(0.85, 1.25);
    final corePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = coreWidth
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5)
      ..shader = SweepGradient(
        center: Alignment.center,
        colors: sweepData.colors
            .map((c) => c.withValues(alpha: (0.95 * intensity).clamp(0.0, 1.0)))
            .toList(),
        stops: sweepData.stops,
      ).createShader(rect);
    canvas.drawRRect(rrect, corePaint);
  }

  @override
  bool shouldRepaint(covariant _Ios18SiriEdgeGlowPainter oldDelegate) =>
      oldDelegate.loopProgress != loopProgress ||
      oldDelegate.colorProgress != colorProgress ||
      oldDelegate.intensity != intensity ||
      oldDelegate.pulse != pulse ||
      oldDelegate.voiceActivity != voiceActivity ||
      oldDelegate.mode != mode ||
      oldDelegate.borderRadius != borderRadius;
}
