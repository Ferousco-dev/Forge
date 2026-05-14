import 'package:flutter/widgets.dart';

/// Corner radius scale per the design brief. Soft, never sharp.
///
/// Use `full` for pill-shaped buttons, avatar borders, fully-rounded
/// chips. `xl` is the right call for hero cards and bottom sheets.
class AppRadius {
  const AppRadius._();

  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double full = 999;

  static const Radius radiusSm = Radius.circular(sm);
  static const Radius radiusMd = Radius.circular(md);
  static const Radius radiusLg = Radius.circular(lg);
  static const Radius radiusXl = Radius.circular(xl);

  static const BorderRadius allSm = BorderRadius.all(radiusSm);
  static const BorderRadius allMd = BorderRadius.all(radiusMd);
  static const BorderRadius allLg = BorderRadius.all(radiusLg);
  static const BorderRadius allXl = BorderRadius.all(radiusXl);
}
