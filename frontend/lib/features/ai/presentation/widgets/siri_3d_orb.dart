import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum SiriOrbState {
  listening,
  thinking,
  speaking,
  paused,
}

/// A 3D-styled interactive Siri Orb widget.
/// Features dynamic holographic gradients, layered luminous halos,
/// slow voice-reactive color shifting, and sound-reactive ripple pulses.
class Siri3dOrb extends StatefulWidget {
  const Siri3dOrb({
    super.key,
    required this.state,
    this.size = 120.0,
    this.voiceActivity = 0.0,
    this.onTap,
    this.statusText,
  });

  final SiriOrbState state;
  final double size;
  final double voiceActivity;
  final VoidCallback? onTap;
  final String? statusText;

  @override
  State<Siri3dOrb> createState() => _Siri3dOrbState();
}

class _Siri3dOrbState extends State<Siri3dOrb> with TickerProviderStateMixin {
  late final AnimationController _spinController;
  late final AnimationController _pulseController;
  late final AnimationController _waveController;
  late final AnimationController _colorShiftController;

  double _smoothedVoice = 0.0;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6000),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    // Slow color shift controller (12 seconds)
    _colorShiftController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 12000),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant Siri3dOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      switch (widget.state) {
        case SiriOrbState.speaking:
          _spinController.duration = const Duration(milliseconds: 2400);
          _pulseController.duration = const Duration(milliseconds: 800);
          break;
        case SiriOrbState.thinking:
          _spinController.duration = const Duration(milliseconds: 1800);
          _pulseController.duration = const Duration(milliseconds: 1000);
          break;
        case SiriOrbState.listening:
          _spinController.duration = const Duration(milliseconds: 4000);
          _pulseController.duration = const Duration(milliseconds: 1200);
          break;
        case SiriOrbState.paused:
          _spinController.duration = const Duration(milliseconds: 8000);
          _pulseController.duration = const Duration(milliseconds: 2000);
          break;
      }
      if (!_spinController.isAnimating) _spinController.repeat();
      if (!_pulseController.isAnimating) _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _spinController.dispose();
    _pulseController.dispose();
    _waveController.dispose();
    _colorShiftController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orbSize = widget.size;

    // Smooth voice activity filter
    final targetVoice = widget.state == SiriOrbState.speaking
        ? math.max(widget.voiceActivity, 0.55)
        : widget.voiceActivity;
    _smoothedVoice = _smoothedVoice * 0.86 + targetVoice * 0.14;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap?.call();
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _spinController,
          _pulseController,
          _waveController,
          _colorShiftController,
        ]),
        builder: (context, child) {
          final pulseVal = _pulseController.value;
          final waveVal = _waveController.value;
          final spinVal = _spinController.value;
          final colorVal = _colorShiftController.value;

          // Scale factor smoothly reacts with voice
          final baseScale = switch (widget.state) {
            SiriOrbState.speaking => 1.0 + 0.12 * pulseVal + 0.08 * _smoothedVoice,
            SiriOrbState.listening => 0.98 + 0.08 * pulseVal + 0.06 * _smoothedVoice,
            SiriOrbState.thinking => 0.95 + 0.06 * math.sin(spinVal * math.pi * 2),
            SiriOrbState.paused => 0.92,
          };

          return SizedBox(
            width: orbSize + 36,
            height: orbSize + 36,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Layer 1: Ambient Luminous Sound Waves (expanding ripple rings reacting to voice)
                if (widget.state == SiriOrbState.listening || widget.state == SiriOrbState.speaking)
                  CustomPaint(
                    size: Size(orbSize + 34, orbSize + 34),
                    painter: _OrbWavePainter(
                      progress: waveVal,
                      state: widget.state,
                      pulse: pulseVal,
                      voiceActivity: _smoothedVoice,
                      colorProgress: colorVal,
                    ),
                  ),

                // Layer 2: 3D Holographic Base Glow
                Container(
                  width: orbSize * baseScale,
                  height: orbSize * baseScale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _getPrimaryGlowColor(widget.state, colorVal).withValues(
                          alpha: widget.state == SiriOrbState.speaking
                              ? 0.7 + 0.15 * _smoothedVoice
                              : 0.5 + 0.2 * _smoothedVoice,
                        ),
                        blurRadius: (28 + 12 * _smoothedVoice) * baseScale,
                        spreadRadius: (4 + 4 * _smoothedVoice) * baseScale,
                      ),
                      BoxShadow(
                        color: _getSecondaryGlowColor(widget.state, colorVal).withValues(
                          alpha: widget.state == SiriOrbState.thinking ? 0.6 : 0.4,
                        ),
                        blurRadius: 18 * baseScale,
                        spreadRadius: -2,
                      ),
                    ],
                  ),
                ),

                // Layer 3: Dynamic 3D Spherical Shader Surface (slow color morphing)
                CustomPaint(
                  size: Size(orbSize * baseScale, orbSize * baseScale),
                  painter: _SiriSpherePainter(
                    spinProgress: spinVal,
                    pulseProgress: pulseVal,
                    colorProgress: colorVal,
                    voiceActivity: _smoothedVoice,
                    state: widget.state,
                  ),
                ),

                // Layer 4: Siri Orb GIF overlay with subtle opacity blending for fluid particles
                ClipOval(
                  child: SizedBox(
                    width: orbSize * 0.92 * baseScale,
                    height: orbSize * 0.92 * baseScale,
                    child: Image.asset(
                      'assets/ai/siri_orb.gif',
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                    ),
                  ),
                ),

                // Layer 5: Specular Glass Reflection (curved 3D light sheen)
                Positioned(
                  top: (orbSize * baseScale) * 0.12,
                  child: Container(
                    width: orbSize * 0.52 * baseScale,
                    height: orbSize * 0.24 * baseScale,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(100),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.55 + 0.15 * _smoothedVoice),
                          Colors.white.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Color _getPrimaryGlowColor(SiriOrbState state, double colorProgress) {
    final t = colorProgress;
    switch (state) {
      case SiriOrbState.speaking:
        return Color.lerp(const Color(0xFF64D2FF), const Color(0xFF30D158), math.sin(t * math.pi * 2).abs())!;
      case SiriOrbState.thinking:
        return Color.lerp(const Color(0xFFBF5AF2), const Color(0xFFFF9F0A), math.cos(t * math.pi * 2).abs())!;
      case SiriOrbState.listening:
        return Color.lerp(const Color(0xFFFF375F), const Color(0xFF5E5CE6), math.sin(t * math.pi * 2).abs())!;
      case SiriOrbState.paused:
        return const Color(0xFF5E5CE6);
    }
  }

  Color _getSecondaryGlowColor(SiriOrbState state, double colorProgress) {
    final t = colorProgress;
    switch (state) {
      case SiriOrbState.speaking:
        return Color.lerp(const Color(0xFF30D158), const Color(0xFF64D2FF), math.cos(t * math.pi * 2).abs())!;
      case SiriOrbState.thinking:
        return Color.lerp(const Color(0xFFFF9F0A), const Color(0xFFBF5AF2), math.sin(t * math.pi * 2).abs())!;
      case SiriOrbState.listening:
        return Color.lerp(const Color(0xFF5E5CE6), const Color(0xFF64D2FF), math.cos(t * math.pi * 2).abs())!;
      case SiriOrbState.paused:
        return const Color(0xFF64D2FF);
    }
  }
}

/// Custom painter for the 3D spherical iridescent depth with slow color morphing
class _SiriSpherePainter extends CustomPainter {
  _SiriSpherePainter({
    required this.spinProgress,
    required this.pulseProgress,
    required this.colorProgress,
    required this.voiceActivity,
    required this.state,
  });

  final double spinProgress;
  final double pulseProgress;
  final double colorProgress;
  final double voiceActivity;
  final SiriOrbState state;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2;
    final center = Offset(radius, radius);

    // Dynamic color stops rotating around center
    final angle = spinProgress * math.pi * 2;
    final colorShift = (colorProgress + voiceActivity * 0.15) * math.pi * 2;

    // Deep cosmic core
    final coreGradient = RadialGradient(
      center: Alignment(
        -0.3 + 0.3 * math.cos(angle),
        -0.3 + 0.3 * math.sin(angle),
      ),
      radius: 0.88,
      colors: const [
        Color(0xFF2E0854), // Deep royal violet
        Color(0xFF0D0221), // Void navy
        Color(0xFF050510), // Obsidian black
      ],
      stops: const [0.0, 0.65, 1.0],
    );

    final corePaint = Paint()
      ..shader = coreGradient.createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius, corePaint);

    // Luminous Chromatic Plasma Sweep inside sphere - colors slowly morph with speech
    final s1 = math.sin(colorShift).abs();
    final c1 = math.cos(colorShift).abs();

    final sweepGradient = SweepGradient(
      center: Alignment.center,
      startAngle: 0,
      endAngle: math.pi * 2,
      transform: GradientRotation(angle + colorShift * 0.5),
      colors: [
        Color.lerp(const Color(0x99FF375F), const Color(0x9900C7BE), s1)!,
        Color.lerp(const Color(0x99FF9F0A), const Color(0x995E5CE6), c1)!,
        Color.lerp(const Color(0x9930D158), const Color(0x99BF5AF2), s1)!,
        Color.lerp(const Color(0x9964D2FF), const Color(0x99FF375F), c1)!,
        Color.lerp(const Color(0x995E5CE6), const Color(0x99FF9F0A), s1)!,
        Color.lerp(const Color(0x99BF5AF2), const Color(0x9930D158), c1)!,
        Color.lerp(const Color(0x99FF375F), const Color(0x9900C7BE), s1)!,
      ],
    );

    final sweepPaint = Paint()
      ..shader = sweepGradient.createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * (0.52 + 0.10 * voiceActivity)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 14 + 6 * voiceActivity);

    canvas.drawCircle(center, radius * 0.65, sweepPaint);

    // Inner highlight rim
    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 + 0.6 * voiceActivity
      ..shader = SweepGradient(
        transform: GradientRotation(-angle * 1.5 + colorShift),
        colors: [
          Colors.white.withValues(alpha: 0.8 + 0.2 * voiceActivity),
          const Color(0xFF64D2FF).withValues(alpha: 0.6),
          Colors.transparent,
          const Color(0xFFFF375F).withValues(alpha: 0.7),
          Colors.white.withValues(alpha: 0.8 + 0.2 * voiceActivity),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius - 1.5, rimPaint);
  }

  @override
  bool shouldRepaint(covariant _SiriSpherePainter oldDelegate) =>
      oldDelegate.spinProgress != spinProgress ||
      oldDelegate.pulseProgress != pulseProgress ||
      oldDelegate.colorProgress != colorProgress ||
      oldDelegate.voiceActivity != voiceActivity ||
      oldDelegate.state != state;
}

/// Pulsing ambient wave painter radiating outward with slow color morphing
class _OrbWavePainter extends CustomPainter {
  _OrbWavePainter({
    required this.progress,
    required this.state,
    required this.pulse,
    required this.voiceActivity,
    required this.colorProgress,
  });

  final double progress;
  final SiriOrbState state;
  final double pulse;
  final double voiceActivity;
  final double colorProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = (size.width / 2) * (1.0 + 0.15 * voiceActivity);
    final baseRadius = maxRadius * 0.72;

    final t = colorProgress;
    final speakingColor = Color.lerp(const Color(0xFF64D2FF), const Color(0xFF30D158), math.sin(t * math.pi * 2).abs())!;
    final listeningColor = Color.lerp(const Color(0xFFFF375F), const Color(0xFF00C7BE), math.cos(t * math.pi * 2).abs())!;
    final color = state == SiriOrbState.speaking ? speakingColor : listeningColor;

    // 2 staggered ripple rings
    for (int i = 0; i < 2; i++) {
      final ringProgress = (progress + (i * 0.5)) % 1.0;
      final currentRadius = baseRadius + (maxRadius - baseRadius) * ringProgress;
      final alpha = (1.0 - ringProgress).clamp(0.0, 1.0) *
          (state == SiriOrbState.speaking ? 0.45 + 0.25 * voiceActivity : 0.28 + 0.20 * voiceActivity);

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (2.0 + 1.2 * voiceActivity) * (1.0 - ringProgress)
        ..color = color.withValues(alpha: alpha.clamp(0.0, 1.0));

      canvas.drawCircle(center, currentRadius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _OrbWavePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.state != state ||
      oldDelegate.pulse != pulse ||
      oldDelegate.voiceActivity != voiceActivity ||
      oldDelegate.colorProgress != colorProgress;
}
