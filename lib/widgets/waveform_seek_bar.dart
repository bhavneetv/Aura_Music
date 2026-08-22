import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/track.dart';
import '../services/audio/waveform_service.dart';

class WaveformSeekBar extends StatefulWidget {
  final Track track;
  final double progress; // 0.0 to 1.0
  final Duration currentPosition;
  final Duration totalDuration;
  final Color activeColor;
  final Color? inactiveColor;
  final bool isDark;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final double height;
  final int barCount;

  const WaveformSeekBar({
    super.key,
    required this.track,
    required this.progress,
    required this.currentPosition,
    required this.totalDuration,
    required this.activeColor,
    this.inactiveColor,
    this.isDark = true,
    this.onChangeStart,
    this.onChanged,
    this.onChangeEnd,
    this.height = 50.0,
    this.barCount = 65,
  });

  @override
  State<WaveformSeekBar> createState() => _WaveformSeekBarState();
}

class _WaveformSeekBarState extends State<WaveformSeekBar> {
  List<double>? _amplitudes;
  bool _isLoading = true;
  bool _isDragging = false;
  double _dragProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _loadWaveform();
  }

  @override
  void didUpdateWidget(WaveformSeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id || oldWidget.barCount != widget.barCount) {
      _loadWaveform();
    }
  }

  Future<void> _loadWaveform() async {
    setState(() {
      _isLoading = true;
    });

    final amplitudes = await WaveformService.instance.getWaveform(
      widget.track,
      barCount: widget.barCount,
    );

    if (mounted) {
      setState(() {
        _amplitudes = amplitudes;
        _isLoading = false;
      });
    }
  }

  void _handleTouch(Offset localPosition, double width) {
    if (width <= 0) return;
    final clampedX = localPosition.dx.clamp(0.0, width);
    final val = (clampedX / width).clamp(0.0, 1.0);
    setState(() {
      _dragProgress = val;
    });
    widget.onChanged?.call(val);
  }

  @override
  Widget build(BuildContext context) {
    final effectiveProgress = _isDragging ? _dragProgress : widget.progress.clamp(0.0, 1.0);
    final inactive = widget.inactiveColor ??
        (widget.isDark ? Colors.white.withValues(alpha: 0.18) : Colors.black.withValues(alpha: 0.12));

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (details) {
            HapticFeedback.selectionClick();
            setState(() {
              _isDragging = true;
              _dragProgress = (details.localPosition.dx / width).clamp(0.0, 1.0);
            });
            widget.onChangeStart?.call(_dragProgress);
          },
          onHorizontalDragUpdate: (details) {
            _handleTouch(details.localPosition, width);
          },
          onHorizontalDragEnd: (details) {
            widget.onChangeEnd?.call(_dragProgress);
            setState(() {
              _isDragging = false;
            });
          },
          onTapDown: (details) {
            HapticFeedback.selectionClick();
            final val = (details.localPosition.dx / width).clamp(0.0, 1.0);
            widget.onChangeStart?.call(val);
            widget.onChanged?.call(val);
            widget.onChangeEnd?.call(val);
          },
          child: SizedBox(
            height: widget.height,
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Waveform Custom Painter
                CustomPaint(
                  size: Size(width, widget.height),
                  painter: _WaveformPainter(
                    amplitudes: _amplitudes ?? _generatePlaceholderBars(widget.barCount),
                    progress: effectiveProgress,
                    activeColor: widget.activeColor,
                    inactiveColor: inactive,
                    isLoading: _isLoading,
                    isDragging: _isDragging,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<double> _generatePlaceholderBars(int count) {
    return List.generate(count, (i) => 0.25 + (0.15 * (i % 3)));
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> amplitudes;
  final double progress; // 0.0 to 1.0
  final Color activeColor;
  final Color inactiveColor;
  final bool isLoading;
  final bool isDragging;

  _WaveformPainter({
    required this.amplitudes,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    required this.isLoading,
    required this.isDragging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (amplitudes.isEmpty || size.width <= 0) return;

    final int barCount = amplitudes.length;
    final double totalSpacingRatio = 0.35; // 35% gap between bars
    final double availableWidth = size.width;
    final double barWidth = (availableWidth / barCount) * (1.0 - totalSpacingRatio);
    final double gap = (availableWidth / barCount) * totalSpacingRatio;

    final double centerY = size.height / 2;
    final double maxBarHeight = size.height * 0.85;
    final double minBarHeight = 4.0;

    final double activeBoundaryX = progress * availableWidth;

    // Active Bar Paint
    final Paint activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.fill;

    // Active Glow Paint (when dragging or active)
    final Paint glowPaint = Paint()
      ..color = activeColor.withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);

    // Inactive Bar Paint
    final Paint inactivePaint = Paint()
      ..color = inactiveColor
      ..style = PaintingStyle.fill;

    for (int i = 0; i < barCount; i++) {
      final double x = (i * (barWidth + gap)) + (gap / 2);
      final double normAmp = amplitudes[i].clamp(0.1, 1.0);
      final double barHeight = (minBarHeight + (normAmp * (maxBarHeight - minBarHeight))).clamp(minBarHeight, maxBarHeight);
      
      final Rect barRect = Rect.fromCenter(
        center: Offset(x + (barWidth / 2), centerY),
        width: barWidth,
        height: barHeight,
      );

      final RRect roundedRect = RRect.fromRectAndRadius(barRect, Radius.circular(barWidth / 2));

      final bool isActive = (x + (barWidth / 2)) <= activeBoundaryX;

      if (isActive) {
        if (isDragging) {
          canvas.drawRRect(roundedRect, glowPaint);
        }
        canvas.drawRRect(roundedRect, activePaint);
      } else {
        canvas.drawRRect(roundedRect, inactivePaint);
      }
    }

    // Playhead Scrub Line / Dot Indicator
    final double playheadX = activeBoundaryX.clamp(0.0, availableWidth);
    
    // Draw playhead vertical glow line
    final Paint lineGlowPaint = Paint()
      ..color = activeColor.withValues(alpha: 0.6)
      ..strokeWidth = isDragging ? 3.5 : 2.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);
      
    final Paint linePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = isDragging ? 2.5 : 1.8
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(playheadX, 2),
      Offset(playheadX, size.height - 2),
      lineGlowPaint,
    );

    canvas.drawLine(
      Offset(playheadX, 4),
      Offset(playheadX, size.height - 4),
      linePaint,
    );

    // Draw thumb dot at playhead center
    final Paint dotPaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.fill;

    final Paint dotCorePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final double dotRadius = isDragging ? 6.0 : 4.5;
    canvas.drawCircle(Offset(playheadX, centerY), dotRadius + 2.0, lineGlowPaint);
    canvas.drawCircle(Offset(playheadX, centerY), dotRadius, dotPaint);
    canvas.drawCircle(Offset(playheadX, centerY), dotRadius * 0.45, dotCorePaint);
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.isLoading != isLoading ||
        oldDelegate.isDragging != isDragging ||
        oldDelegate.amplitudes != amplitudes;
  }
}
