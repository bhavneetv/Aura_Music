import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../themes/app_theme.dart';
import '../../providers/customization_provider.dart';

class EqualizerScreen extends ConsumerStatefulWidget {
  const EqualizerScreen({super.key});

  @override
  ConsumerState<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends ConsumerState<EqualizerScreen> {
  // Slider values representing decibel gains (from -12dB to +12dB)
  final List<double> _bandGains = [2.0, -1.0, 4.0, 1.5, -3.0];
  final List<String> _bandLabels = ['60 Hz', '230 Hz', '910 Hz', '4 kHz', '14 kHz'];
  String _selectedPreset = 'Custom';

  final Map<String, List<double>> _presets = {
    'Rock': [4.0, 2.0, -1.0, 2.0, 5.0],
    'Pop': [-2.0, 1.5, 3.0, 2.0, -1.0],
    'Lo-Fi': [3.0, 1.0, -2.0, -3.0, -4.0],
    'Electronic': [5.0, 2.5, 0.0, 3.0, 4.0],
    'Flat': [0.0, 0.0, 0.0, 0.0, 0.0],
  };

  void _applyPreset(String name) {
    if (_presets.containsKey(name)) {
      setState(() {
        _selectedPreset = name;
        final presetGains = _presets[name]!;
        for (int i = 0; i < _bandGains.length; i++) {
          _bandGains[i] = presetGains[i];
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final customBranding = ref.watch(customizationProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Equalizer',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontFamily: 'Outfit',
                fontWeight: FontWeight.w800,
              ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Live Curve Graphic
            Container(
              margin: const EdgeInsets.all(24),
              height: 180,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF141414) : const Color(0xFFF3EFE9),
                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                border: Border.all(
                  color: (isDark ? Colors.white : Colors.black).withOpacity(0.06),
                  width: 1.0,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                child: CustomPaint(
                  painter: EqualizerCurvePainter(
                    gains: _bandGains, 
                    isDark: isDark, 
                    accentColor: customBranding.accentColor
                  ),
                  child: Container(),
                ),
              ),
            ),

            // Preset Selector Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: _presets.keys.map((presetName) {
                  final isSelected = _selectedPreset == presetName;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(presetName),
                      selected: isSelected,
                      onSelected: (val) {
                        if (val) _applyPreset(presetName);
                      },
                      selectedColor: customBranding.accentColor.withOpacity(0.12),
                      checkmarkColor: customBranding.accentColor,
                      labelStyle: TextStyle(
                        color: isSelected ? customBranding.accentColor : Colors.grey,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 24),

            // Gain Band Controllers
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(_bandGains.length, (index) {
                    return _buildVerticalSlider(index, customBranding.accentColor);
                  }),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildVerticalSlider(int index, Color accentColor) {
    final gain = _bandGains[index];

    return Column(
      children: [
        // Gain display text
        Text(
          '${gain > 0 ? "+" : ""}${gain.toStringAsFixed(1)}dB',
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
        ),
        const SizedBox(height: 12),

        // Vertical Slider Track
        Expanded(
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: accentColor,
                inactiveTrackColor: Colors.black.withOpacity(0.06),
                thumbColor: accentColor,
                overlayColor: accentColor.withOpacity(0.2),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                value: gain,
                min: -12.0,
                max: 12.0,
                onChanged: (val) {
                  setState(() {
                    _selectedPreset = 'Custom';
                    _bandGains[index] = val;
                  });
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Frequency Label
        Text(
          _bandLabels[index],
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

// Live Bezier Curve Painter for Equalizer Graph
class EqualizerCurvePainter extends CustomPainter {
  final List<double> gains;
  final bool isDark;
  final Color accentColor;

  EqualizerCurvePainter({
    required this.gains, 
    required this.isDark, 
    required this.accentColor
  });

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final middleY = height / 2;

    // Background Grid lines
    final gridPaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withOpacity(0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Draw horizontal grid lines
    canvas.drawLine(Offset(0, height * 0.25), Offset(width, height * 0.25), gridPaint);
    canvas.drawLine(Offset(0, middleY), Offset(width, middleY), gridPaint);
    canvas.drawLine(Offset(0, height * 0.75), Offset(width, height * 0.75), gridPaint);

    // Map gains to Y coordinates
    final points = <Offset>[];
    final stepX = width / (gains.length - 1);

    for (int i = 0; i < gains.length; i++) {
      final x = i * stepX;
      final normalizedGain = gains[i] / 12.0;
      final y = middleY - (normalizedGain * (height * 0.35));
      points.add(Offset(x, y));
    }

    // Draw Curve connecting points via Cubic Beziers
    final path = Path()..moveTo(0, points[0].dy);

    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final controlPoint1 = Offset(p0.dx + stepX / 2, p0.dy);
      final controlPoint2 = Offset(p1.dx - stepX / 2, p1.dy);
      path.cubicTo(controlPoint1.dx, controlPoint1.dy, controlPoint2.dx, controlPoint2.dy, p1.dx, p1.dy);
    }

    // Glow under the path
    final fillPath = Path.from(path)
      ..lineTo(width, height)
      ..lineTo(0, height)
      ..close();

    final areaShader = LinearGradient(
      colors: [
        accentColor.withOpacity(0.2),
        accentColor.withOpacity(0.0),
      ],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ).createShader(Rect.fromLTRB(0, 0, width, height));

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = areaShader;

    canvas.drawPath(fillPath, fillPaint);

    // Main line paint
    final linePaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, linePaint);

    // Draw node dots
    final dotPaint = Paint()
      ..color = isDark ? Colors.white : const Color(0xFF090909)
      ..style = PaintingStyle.fill;
    final dotOuterPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    for (var point in points) {
      canvas.drawCircle(point, 5, dotPaint);
      canvas.drawCircle(point, 5, dotOuterPaint);
    }
  }

  @override
  bool shouldRepaint(covariant EqualizerCurvePainter oldDelegate) => true;
}
