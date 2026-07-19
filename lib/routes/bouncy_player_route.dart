import 'package:flutter/material.dart';

class BouncyPlayerRoute extends PageRouteBuilder {
  final Widget child;

  BouncyPlayerRoute({required this.child})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => child,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            // Using a spring-back curve (easeOutBack) for the bounce effect
            final curve = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutBack,
              reverseCurve: Curves.easeIn,
            );

            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.0, 1.0), // Start from bottom of screen
                end: Offset.zero,
              ).animate(curve),
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 650),
          reverseTransitionDuration: const Duration(milliseconds: 400),
          opaque: false,
          barrierDismissible: true,
          barrierColor: Colors.black.withOpacity(0.5),
        );
}
