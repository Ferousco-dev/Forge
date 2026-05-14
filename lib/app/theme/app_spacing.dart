import 'package:flutter/widgets.dart';

/// 4-pt spacing scale per the design brief.
///
/// `base` (16pt) is the workhorse unit — most container padding, list-row
/// gutter, and section spacing snaps to it. The names are a deliberate
/// migration from the old `xs/sm/md/lg/xl/xxl/xxxl/huge` scale: cleaner,
/// fewer steps, easier to reason about in review.
///
/// Use the `gap*` `SizedBox` constants when adding vertical or horizontal
/// gaps inside `Column`/`Row` so the spacing is `const`-evaluated and the
/// widget tree stays readable.
class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double base = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  static const SizedBox gapXs = SizedBox(height: xs, width: xs);
  static const SizedBox gapSm = SizedBox(height: sm, width: sm);
  static const SizedBox gapMd = SizedBox(height: md, width: md);
  static const SizedBox gapBase = SizedBox(height: base, width: base);
  static const SizedBox gapLg = SizedBox(height: lg, width: lg);
  static const SizedBox gapXl = SizedBox(height: xl, width: xl);
  static const SizedBox gapXxl = SizedBox(height: xxl, width: xxl);
}
