import 'dart:math' as math;
import 'package:flutter/material.dart';

// ── 1. Snake (Sine Wave) Track Shape ──────────────────────────

class SnakeSliderTrackShape extends RoundedRectSliderTrackShape {
  final double waveAmplitude;
  final double waveFrequency;

  SnakeSliderTrackShape({
    this.waveAmplitude = 4.0,
    this.waveFrequency = 0.08,
  });

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    double additionalActiveTrackHeight = 0.0,
  }) {
    final Canvas canvas = context.canvas;
    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
      offset: offset,
    );

    final Paint activePaint = Paint()
      ..color = sliderTheme.activeTrackColor ?? Colors.amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final Paint inactivePaint = Paint()
      ..color = (sliderTheme.inactiveTrackColor ?? Colors.grey).withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final Path activePath = Path();
    final Path inactivePath = Path();

    // Draw active wave segment up to thumbCenter.dx
    bool isFirstActive = true;
    for (double x = trackRect.left; x <= thumbCenter.dx; x += 2.0) {
      final double y = trackRect.top + waveAmplitude * math.sin((x - trackRect.left) * waveFrequency);
      if (isFirstActive) {
        activePath.moveTo(x, y);
        isFirstActive = false;
      } else {
        activePath.lineTo(x, y);
      }
    }

    // Draw inactive wave segment from thumbCenter.dx to trackRect.right
    bool isFirstInactive = true;
    for (double x = thumbCenter.dx; x <= trackRect.right; x += 2.0) {
      final double y = trackRect.top + waveAmplitude * math.sin((x - trackRect.left) * waveFrequency);
      if (isFirstInactive) {
        inactivePath.moveTo(x, y);
        isFirstInactive = false;
      } else {
        inactivePath.lineTo(x, y);
      }
    }

    canvas.drawPath(inactivePath, inactivePaint);
    canvas.drawPath(activePath, activePaint);
  }
}

// ── 2. Zigzag Track Shape ─────────────────────────────────────

class ZigzagSliderTrackShape extends RoundedRectSliderTrackShape {
  final double zigzagHeight;
  final double stepWidth;

  ZigzagSliderTrackShape({
    this.zigzagHeight = 5.0,
    this.stepWidth = 8.0,
  });

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    double additionalActiveTrackHeight = 0.0,
  }) {
    final Canvas canvas = context.canvas;
    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
      offset: offset,
    );

    final Paint activePaint = Paint()
      ..color = sliderTheme.activeTrackColor ?? Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final Paint inactivePaint = Paint()
      ..color = (sliderTheme.inactiveTrackColor ?? Colors.grey).withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final Path activePath = Path();
    final Path inactivePath = Path();

    bool up = true;
    bool activeStarted = false;
    for (double x = trackRect.left; x <= thumbCenter.dx; x += stepWidth) {
      final double y = trackRect.top + (up ? -zigzagHeight : zigzagHeight);
      if (!activeStarted) {
        activePath.moveTo(x, y);
        activeStarted = true;
      } else {
        activePath.lineTo(x, y);
      }
      up = !up;
    }

    bool inactiveStarted = false;
    for (double x = thumbCenter.dx; x <= trackRect.right; x += stepWidth) {
      final double y = trackRect.top + (up ? -zigzagHeight : zigzagHeight);
      if (!inactiveStarted) {
        inactivePath.moveTo(x, y);
        inactiveStarted = true;
      } else {
        inactivePath.lineTo(x, y);
      }
      up = !up;
    }

    canvas.drawPath(inactivePath, inactivePaint);
    canvas.drawPath(activePath, activePaint);
  }
}

// ── 3. Neon Glow Track Shape ──────────────────────────────────

class NeonSliderTrackShape extends RoundedRectSliderTrackShape {
  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    double additionalActiveTrackHeight = 0.0,
  }) {
    final Canvas canvas = context.canvas;
    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
      offset: offset,
    );

    final Color accent = sliderTheme.activeTrackColor ?? Colors.cyanAccent;

    // Outer glow
    final Paint glowPaint = Paint()
      ..color = accent.withValues(alpha: 0.6)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0)
      ..strokeWidth = 8.0
      ..strokeCap = StrokeCap.round;

    // Solid core
    final Paint activePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    final Paint inactivePaint = Paint()
      ..color = (sliderTheme.inactiveTrackColor ?? Colors.grey).withValues(alpha: 0.2)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    // Inactive track
    canvas.drawLine(
      Offset(thumbCenter.dx, trackRect.top),
      Offset(trackRect.right, trackRect.top),
      inactivePaint,
    );

    // Glow line
    canvas.drawLine(
      Offset(trackRect.left, trackRect.top),
      Offset(thumbCenter.dx, trackRect.top),
      glowPaint,
    );

    // Active core line
    canvas.drawLine(
      Offset(trackRect.left, trackRect.top),
      Offset(thumbCenter.dx, trackRect.top),
      activePaint,
    );
  }
}

// ── Helper to resolve track shape based on style name ────────

SliderTrackShape resolveSliderTrackShape(String style) {
  switch (style.toLowerCase()) {
    case 'snake':
      return SnakeSliderTrackShape();
    case 'zigzag':
      return ZigzagSliderTrackShape();
    case 'neon':
      return NeonSliderTrackShape();
    case 'normal':
    default:
      return const RoundedRectSliderTrackShape();
  }
}
