import 'dart:math' as math;
import 'package:flutter/material.dart';

class AiSearchLoading extends StatefulWidget {
  final String statusText;

  const AiSearchLoading({
    super.key,
    this.statusText = 'AI is curating your personalized music experience...',
  });

  @override
  State<AiSearchLoading> createState() => _AiSearchLoadingState();
}

class _AiSearchLoadingState extends State<AiSearchLoading> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const goldColor = Color(0xFFFFC72C);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 160,
            height: 160,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final angle = _controller.value * 2 * math.pi;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer glowing ring pulse
                    Transform.scale(
                      scale: 1.0 + (math.sin(_controller.value * 2 * math.pi) * 0.08),
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: goldColor.withValues(alpha: 0.35),
                              blurRadius: 24,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Rotating Vinyl Record
                    Transform.rotate(
                      angle: angle,
                      child: Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF141416),
                          border: Border.all(color: goldColor.withValues(alpha: 0.6), width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Vinyl grooves
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1),
                              ),
                            ),
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1),
                              ),
                            ),
                            // Gold Label Center
                            Container(
                              width: 32,
                              height: 32,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: goldColor,
                              ),
                              child: const Center(
                                child: Icon(Icons.auto_awesome_rounded, color: Colors.black, size: 16),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Floating Music Notes (radiating outwards)
                    ...List.generate(4, (index) {
                      final phase = (_controller.value + (index * 0.25)) % 1.0;
                      final noteAngle = (index * (math.pi / 2)) + (_controller.value * math.pi);
                      final radius = 55.0 + (phase * 35.0);
                      final noteDx = math.cos(noteAngle) * radius;
                      final noteDy = math.sin(noteAngle) * radius;
                      final opacity = (1.0 - phase).clamp(0.0, 1.0);
                      final scale = 0.6 + (phase * 0.6);

                      final noteIcons = [Icons.music_note_rounded, Icons.music_note_sharp, Icons.star_rounded, Icons.graphic_eq_rounded];

                      return Transform.translate(
                        offset: Offset(noteDx, noteDy),
                        child: Opacity(
                          opacity: opacity,
                          child: Transform.scale(
                            scale: scale,
                            child: Icon(
                              noteIcons[index % noteIcons.length],
                              color: goldColor,
                              size: 20,
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [goldColor, Color(0xFFFFE082)],
            ).createShader(bounds),
            child: const Text(
              '✨ AI Search Active',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                fontFamily: 'Outfit',
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              widget.statusText,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white70 : Colors.black.withValues(alpha: 0.6),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
