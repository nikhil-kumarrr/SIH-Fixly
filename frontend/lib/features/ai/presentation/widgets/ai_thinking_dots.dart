import 'dart:async';
import 'package:flutter/material.dart';

/// Smooth 3-dot wave loader shown while Fixly AI is thinking.
class AiThinkingDots extends StatefulWidget {
  const AiThinkingDots({
    super.key,
    this.color,
    this.size = 8,
    this.gap = 6,
  });

  final Color? color;
  final double size;
  final double gap;

  @override
  State<AiThinkingDots> createState() => _AiThinkingDotsState();
}

class _AiThinkingDotsState extends State<AiThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.color ?? Theme.of(context).colorScheme.primary;
    return Semantics(
      label: 'AI is thinking',
      child: SizedBox(
        height: widget.size * 3,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                final phase = (_controller.value + i * 0.18) % 1.0;
                final t = (phase < 0.5 ? phase : 1 - phase) * 2;
                final dy = -widget.size * Curves.easeInOut.transform(t);
                return Padding(
                  padding: EdgeInsets.only(
                    right: i == 2 ? 0 : widget.gap,
                  ),
                  child: Transform.translate(
                    offset: Offset(0, dy),
                    child: Container(
                      width: widget.size,
                      height: widget.size,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.55 + 0.45 * t),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}

/// Dynamic Thinking Status Indicator with 3 bouncing dots and rotating progress labels
class AiThinkingStatusWidget extends StatefulWidget {
  const AiThinkingStatusWidget({
    super.key,
    this.language = 'en',
    this.color,
  });

  final String language;
  final Color? color;

  @override
  State<AiThinkingStatusWidget> createState() => _AiThinkingStatusWidgetState();
}

class _AiThinkingStatusWidgetState extends State<AiThinkingStatusWidget> {
  int _step = 0;
  Timer? _timer;

  List<String> get _stages {
    final isHi = widget.language.toLowerCase().startsWith('hi');
    if (isHi) {
      return [
        'सोच रहा हूँ…',
        'समस्या का विश्लेषण कर रहा हूँ…',
        'निकटतम सत्यापित कार्यकर्ता खोज रहा हूँ…',
        'सुझाव तैयार कर रहा हूँ…',
      ];
    }
    return [
      'Thinking…',
      'Analyzing issue & symptoms…',
      'Checking verified workers near you…',
      'Preparing recommendation…',
    ];
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 1600), (_) {
      if (!mounted) return;
      setState(() {
        _step = (_step + 1) % _stages.length;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stages = _stages;
    final currentText = stages[_step % stages.length];
    final themeColor = widget.color ?? Theme.of(context).colorScheme.primary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AiThinkingDots(color: themeColor, size: 7, gap: 5),
        const SizedBox(width: 10),
        Flexible(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.25),
                  end: Offset.zero,
                ).animate(anim),
                child: child,
              ),
            ),
            child: Text(
              currentText,
              key: ValueKey<int>(_step),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: themeColor,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
