import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../themes/app_theme.dart';

class VinylRefreshIndicator extends StatefulWidget {
  final Widget child;
  final Future<void> Function() onRefresh;

  const VinylRefreshIndicator({
    super.key,
    required this.child,
    required this.onRefresh,
  });

  @override
  State<VinylRefreshIndicator> createState() => _VinylRefreshIndicatorState();
}

class _VinylRefreshIndicatorState extends State<VinylRefreshIndicator> with TickerProviderStateMixin {
  late AnimationController _spinController;
  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;

  double _dragOffset = 0.0;
  bool _isRefreshing = false;
  bool _canRefresh = false;

  final double _refreshThreshold = 75.0;

  @override
  void initState() {
    super.initState();
    
    // 1. Spinning animation
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    // 2. Bouncing animation (vertical displacement)
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _bounceAnimation = Tween<double>(begin: 0.0, end: -12.0).animate(
      CurvedAnimation(
        parent: _bounceController,
        curve: Curves.easeInOutSine,
      ),
    );
  }

  @override
  void dispose() {
    _spinController.dispose();
    _bounceController.dispose();
    super.dispose();
  }

  void _startLoading() {
    setState(() {
      _isRefreshing = true;
    });
    _spinController.repeat();
    _bounceController.repeat(reverse: true);
    
    widget.onRefresh().then((_) {
      if (mounted) {
        _stopLoading();
      }
    });
  }

  void _stopLoading() {
    _spinController.stop();
    _bounceController.stop();
    setState(() {
      _isRefreshing = false;
      _dragOffset = 0.0;
      _canRefresh = false;
    });
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (_isRefreshing) return false;

    if (notification is ScrollUpdateNotification) {
      final metrics = notification.metrics;
      // Scroll pixels < 0 means pulling past the top
      if (metrics.pixels < 0) {
        setState(() {
          _dragOffset = -metrics.pixels;
          _canRefresh = _dragOffset >= _refreshThreshold;
        });
      } else if (_dragOffset != 0.0) {
        setState(() {
          _dragOffset = 0.0;
        });
      }
    } else if (notification is ScrollEndNotification) {
      if (_canRefresh && !_isRefreshing) {
        _startLoading();
      } else if (!_isRefreshing) {
        setState(() {
          _dragOffset = 0.0;
          _canRefresh = false;
        });
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final double headerHeight = _isRefreshing ? 64.0 : math.min(_dragOffset, 120.0);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: Stack(
        children: [
          // 1. Pulled Content List
          Padding(
            padding: EdgeInsets.only(top: _isRefreshing ? 64.0 : 0.0),
            child: widget.child,
          ),

          // 2. Custom Pull-to-refresh Vinyl Header
          if (headerHeight > 0.0)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: headerHeight,
                width: double.infinity,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isDark 
                      ? Colors.black.withOpacity(0.04) 
                      : Colors.white.withOpacity(0.04),
                ),
                child: Opacity(
                  opacity: math.min(headerHeight / _refreshThreshold, 1.0),
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_spinController, _bounceAnimation]),
                    builder: (context, child) {
                      // Apply rotation spin
                      final double angle = _isRefreshing 
                          ? _spinController.value * 2 * math.pi 
                          : (_dragOffset / _refreshThreshold) * 2 * math.pi;

                      // Apply bounce translate
                      final double bounceTranslate = _isRefreshing ? _bounceAnimation.value : 0.0;

                      return Transform.translate(
                        offset: Offset(0, bounceTranslate),
                        child: Transform.rotate(
                          angle: angle,
                          child: child,
                        ),
                      );
                    },
                    // The beautiful skeuomorphic vinyl record loader
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF141414), // Vinyl base charcoal
                        border: Border.all(
                          color: AppTheme.goldAccent.withOpacity(0.4),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Concentric vinyl groove rings
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withOpacity(0.08),
                                width: 0.8,
                              ),
                            ),
                          ),
                          Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withOpacity(0.08),
                                width: 0.8,
                              ),
                            ),
                          ),
                          // Gold Center Label
                          Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.goldAccent,
                            ),
                          ),
                          // Center Spindle Hole
                          Container(
                            width: 3,
                            height: 3,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF141414),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
