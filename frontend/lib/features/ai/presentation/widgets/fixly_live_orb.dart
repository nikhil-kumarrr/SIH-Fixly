import 'package:flutter/material.dart';

/// Temporary test orb — looping GIF. Easy to delete / swap back to siri_orb.
/// Asset: `assets/ai/fixly_live_orb.gif`
class FixlyLiveOrb extends StatelessWidget {
  const FixlyLiveOrb({
    super.key,
    this.size = 92,
    this.onTap,
    this.voiceActivity = 0.0,
  });

  final double size;
  final VoidCallback? onTap;
  final double voiceActivity;

  static const assetPath = 'assets/ai/fixly_live_orb.gif';

  @override
  Widget build(BuildContext context) {
    final scale = 1.0 + (voiceActivity.clamp(0.0, 1.0) * 0.06);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: size,
        height: size,
        child: Transform.scale(
          scale: scale,
          child: ClipOval(
            child: Image.asset(
              assetPath,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, error, stack) => Container(
                color: const Color(0xFF1A1030),
                alignment: Alignment.center,
                child: const Icon(Icons.auto_awesome, color: Colors.white70),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
