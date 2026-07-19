import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Brand Accents
  static const Color goldAccent = Color(0xFFD4AF37); // Default warm amber/gold accent
  static const Color goldLight = Color(0xFFF3E5AB);  // Muted gold

  // Dark Theme Colors
  static const Color darkBg = Color(0xFF090909);       // Near-black AMOLED
  static const Color darkSurface = Color(0xFF141414);  // Deep Charcoal
  static const Color darkSurfaceCard = Color(0xFF1F1F1F); // Elevated glass surface
  static const Color darkTextPrimary = Color(0xFFF5F5F5); // Off-white
  static const Color darkTextSecondary = Color(0xFF9E9E9E); // Muted grey

  // Light Theme Colors
  static const Color lightBg = Color(0xFFFAF8F5);      // Soft warm off-white/cream
  static const Color lightSurface = Color(0xFFF3EFE9); // Slightly darker warm cream
  static const Color lightSurfaceCard = Color(0xFFFFFFFF); // Clean paper white
  static const Color lightTextPrimary = Color(0xFF1C1A17); // Dark brown-charcoal
  static const Color lightTextSecondary = Color(0xFF7A756B); // Muted warm grey

  // Roundness
  static const double cardRadius = 24.0;
  static const double pillRadius = 500.0;

  // Custom Glassmorphic Box Decoration Helper
  static BoxDecoration glassDecoration({
    required BuildContext context,
    double opacity = 0.08,
    double borderOpacity = 0.1,
    double radius = cardRadius,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? Colors.white : Colors.black;
    return BoxDecoration(
      color: color.withOpacity(opacity),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: color.withOpacity(borderOpacity),
        width: 1.0,
      ),
    );
  }

  // Create Dark ThemeData from dynamic accent color
  static ThemeData buildDarkTheme(Color accentColor) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBg,
      primaryColor: accentColor,
      colorScheme: ColorScheme.dark(
        primary: accentColor,
        surface: darkSurface,
        onSurface: darkTextPrimary,
        onSurfaceVariant: darkTextSecondary,
      ),
      textTheme: TextTheme(
        labelLarge: GoogleFonts.outfit(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: darkTextPrimary,
        ),
        bodyLarge: GoogleFonts.outfit(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: darkTextPrimary,
        ),
        bodyMedium: GoogleFonts.outfit(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: darkTextSecondary,
        ),
        titleLarge: GoogleFonts.outfit(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          color: darkTextPrimary,
        ),
        headlineMedium: GoogleFonts.outfit(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          color: darkTextPrimary,
        ),
      ),
      iconTheme: const IconThemeData(
        color: darkTextPrimary,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accentColor,
        inactiveTrackColor: Colors.white.withOpacity(0.1),
        thumbColor: accentColor,
        overlayColor: accentColor.withOpacity(0.2),
        trackHeight: 4,
      ),
    );
  }

  // Create Light ThemeData from dynamic accent color
  static ThemeData buildLightTheme(Color accentColor) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightBg,
      primaryColor: accentColor,
      colorScheme: ColorScheme.light(
        primary: accentColor,
        surface: lightSurface,
        onSurface: lightTextPrimary,
        onSurfaceVariant: lightTextSecondary,
      ),
      textTheme: TextTheme(
        labelLarge: GoogleFonts.outfit(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: lightTextPrimary,
        ),
        bodyLarge: GoogleFonts.outfit(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: lightTextPrimary,
        ),
        bodyMedium: GoogleFonts.outfit(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: lightTextSecondary,
        ),
        titleLarge: GoogleFonts.outfit(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          color: lightTextPrimary,
        ),
        headlineMedium: GoogleFonts.outfit(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          color: lightTextPrimary,
        ),
      ),
      iconTheme: const IconThemeData(
        color: lightTextPrimary,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accentColor,
        inactiveTrackColor: Colors.black.withOpacity(0.06),
        thumbColor: accentColor,
        overlayColor: accentColor.withOpacity(0.2),
        trackHeight: 4,
      ),
    );
  }
}
