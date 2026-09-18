import 'package:flutter/material.dart';
import 'package:siri_wave/siri_wave.dart';

enum SiriWaveVisualizerState {
  listening,
  thinking,
  speaking,
  paused,
}

/// A modern, voice-reactive iOS 9/18 Siri waveform visualizer dock.
/// Replaces the 3D globe with genuine fluid undulating waveforms from `siri_wave`.
class SiriWaveVisualizer extends StatefulWidget {
  const SiriWaveVisualizer({
    required this.state,
    this.voiceActivity = 0.0,
    this.width = 180,
    this.height = 76,
    this.onTap,
    super.key,
  });

  final SiriWaveVisualizerState state;
  final double voiceActivity;
  final double width;
  final double height;
  final VoidCallback? onTap;

  @override
  State<SiriWaveVisualizer> createState() => _SiriWaveVisualizerState();
}

class _SiriWaveVisualizerState extends State<SiriWaveVisualizer>
    with SingleTickerProviderStateMixin {
  late final IOS9SiriWaveformController _controller;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _controller = IOS9SiriWaveformController(
      amplitude: _computeAmplitude(widget.state, widget.voiceActivity),
      speed: _computeSpeed(widget.state, widget.voiceActivity),
      color1: const Color(0xFFFF2D55), // iOS Siri Pink / Coral
      color2: const Color(0xFF00C7BE), // iOS Siri Cyan
      color3: const Color(0xFF5856D6), // iOS Siri Indigo / Violet
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  double _computeAmplitude(SiriWaveVisualizerState state, double voice) {
    switch (state) {
      case SiriWaveVisualizerState.listening:
        return (0.28 + voice * 0.70).clamp(0.18, 1.0);
      case SiriWaveVisualizerState.speaking:
        return (0.55 + voice * 0.40).clamp(0.40, 1.0);
      case SiriWaveVisualizerState.thinking:
        return 0.45;
      case SiriWaveVisualizerState.paused:
        return 0.05;
    }
  }

  double _computeSpeed(SiriWaveVisualizerState state, double voice) {
    switch (state) {
      case SiriWaveVisualizerState.listening:
        return (0.16 + voice * 0.16).clamp(0.14, 0.32);
      case SiriWaveVisualizerState.speaking:
        return 0.24;
      case SiriWaveVisualizerState.thinking:
        return 0.30;
      case SiriWaveVisualizerState.paused:
        return 0.05;
    }
  }

  @override
  void didUpdateWidget(covariant SiriWaveVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state ||
        (oldWidget.voiceActivity - widget.voiceActivity).abs() > 0.03) {
      _controller.amplitude =
          _computeAmplitude(widget.state, widget.voiceActivity);
      _controller.speed = _computeSpeed(widget.state, widget.voiceActivity);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, _) {
          final pulse = _pulseController.value;
          final voiceBoost = widget.voiceActivity.clamp(0.0, 1.0);

          return Stack(
            alignment: Alignment.center,
            children: [
              // Soft ambient backdrop glow behind the wave
              Container(
                width: widget.width + 12,
                height: widget.height + 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(widget.height / 2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF5856D6).withValues(
                        alpha: (0.18 + 0.12 * pulse + 0.15 * voiceBoost)
                            .clamp(0.0, 0.60),
                      ),
                      blurRadius: 22 + 8 * pulse,
                      spreadRadius: -2,
                    ),
                    BoxShadow(
                      color: const Color(0xFF00C7BE).withValues(
                        alpha: (0.14 + 0.10 * (1 - pulse) + 0.12 * voiceBoost)
                            .clamp(0.0, 0.50),
                      ),
                      blurRadius: 26,
                      spreadRadius: -4,
                    ),
                  ],
                ),
              ),

              // Glass container pod
              Container(
                width: widget.width,
                height: widget.height,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.50)
                      : Colors.white.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(widget.height / 2),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.12 + 0.08 * pulse)
                        : Colors.black.withValues(alpha: 0.06),
                    width: 1.0,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(widget.height / 2),
                  child: Center(
                    child: SizedBox(
                      width: widget.width - 16,
                      height: widget.height - 8,
                      child: IOS9SiriWaveform(
                        controller: _controller,
                        showSupportBar: false,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
