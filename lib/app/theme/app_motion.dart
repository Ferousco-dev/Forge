import 'package:flutter/animation.dart';

/// Motion design tokens. Centralizing these lets us re-tune the feel of the
/// entire app from one file once we have user feedback.
///
/// Curves bias toward decelerating ease-out — the language of premium
/// product. No spring, no overshoot, no bounce; those read as childish.
class AppMotion {
  const AppMotion._();

  // Durations
  static const Duration instant = Duration(milliseconds: 80);
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration medium = Duration(milliseconds: 280);
  static const Duration slow = Duration(milliseconds: 480);
  static const Duration deliberate = Duration(milliseconds: 720);

  // Splash-specific. Dwell is the minimum time we hold the splash even
  // if auth + bootstrap finish faster — shorter feels snappier, longer
  // gives the brand mark room to breathe. 600ms is just long enough to
  // register the mark; auth resolution usually dominates anyway.
  static const Duration splashEntrance = Duration(milliseconds: 480);
  static const Duration splashMinDwell = Duration(milliseconds: 600);
  static const Duration splashExit = Duration(milliseconds: 280);
  static const Duration ambientBreath = Duration(milliseconds: 5500);

  // Curves
  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
  static const Curve emphasized = Cubic(0.2, 0.0, 0.0, 1.0);
  static const Curve gentle = Curves.easeOutSine;
  static const Curve breathe = Curves.easeInOutSine;
}
