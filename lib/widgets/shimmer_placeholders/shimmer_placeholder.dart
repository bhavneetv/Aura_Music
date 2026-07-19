import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../themes/app_theme.dart';

class ShimmerPlaceholder extends StatelessWidget {
  final Widget child;

  const ShimmerPlaceholder({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Use low-contrast colors matching the glass surfaces to avoid stark white flashes
    final baseColor = isDark
        ? const Color(0xFF262626)
        : const Color(0xFFE0E0E0);
        
    final highlightColor = isDark
        ? const Color(0xFF3A3A3A)
        : const Color(0xFFF5F5F5);

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      period: const Duration(milliseconds: 1200),
      direction: ShimmerDirection.ltr,
      child: child,
    );
  }
}

// 1. Card Shimmer for Album/Track Art
class CardShimmer extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const CardShimmer({
    super.key,
    this.width = 120,
    this.height = 120,
    this.radius = AppTheme.cardRadius,
  });

  @override
  Widget build(BuildContext context) {
    return ShimmerPlaceholder(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

// 2. Thin Rounded Bar for Title/Artist Text Lines
class TextLineShimmer extends StatelessWidget {
  final double width;
  final double height;

  const TextLineShimmer({
    super.key,
    this.width = 100,
    this.height = 12,
  });

  @override
  Widget build(BuildContext context) {
    return ShimmerPlaceholder(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(height / 2),
        ),
      ),
    );
  }
}

// 3. Circular Placeholder for Artist Avatars
class AvatarShimmer extends StatelessWidget {
  final double size;

  const AvatarShimmer({
    super.key,
    this.size = 60,
  });

  @override
  Widget build(BuildContext context) {
    return ShimmerPlaceholder(
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// 4. Combined Shimmer Layouts for easy section building
class TrackTileShimmer extends StatelessWidget {
  const TrackTileShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          const CardShimmer(width: 50, height: 50, radius: 12),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const TextLineShimmer(width: 150, height: 14),
                const SizedBox(height: 8),
                const TextLineShimmer(width: 90, height: 10),
              ],
            ),
          ),
          const SizedBox(width: 16),
          const CardShimmer(width: 24, height: 24, radius: 12), // Favorite/Action placeholder
        ],
      ),
    );
  }
}

class RailShimmer extends StatelessWidget {
  const RailShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const TextLineShimmer(width: 120, height: 18),
              const TextLineShimmer(width: 60, height: 12),
            ],
          ),
        ),
        SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: 24),
            itemCount: 4,
            physics: const NeverScrollableScrollPhysics(),
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CardShimmer(width: 120, height: 120),
                    const SizedBox(height: 12),
                    const TextLineShimmer(width: 100, height: 12),
                    const SizedBox(height: 6),
                    const TextLineShimmer(width: 60, height: 10),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
