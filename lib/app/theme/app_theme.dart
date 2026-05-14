import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_radius.dart';
import 'app_text_styles.dart';

/// `ThemeData` factory. Light + dark share the same shape and only
/// diverge in token values.
class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(AppColors.light);
  static ThemeData dark() => _build(AppColors.dark);

  static ThemeData _build(AppColors palette) {
    final scheme = palette.toColorScheme();
    final textTheme = AppTextStyles.buildTextTheme(
      palette.onSurface,
      palette.onSurfaceVariant,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: palette.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.surface,
      canvasColor: palette.surface,
      textTheme: textTheme,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.surface,
        foregroundColor: palette.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: textTheme.titleLarge,
        systemOverlayStyle: palette.brightness == Brightness.light
            ? SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: palette.surface,
                systemNavigationBarIconBrightness: Brightness.dark,
              )
            : SystemUiOverlayStyle.light.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: palette.surface,
                systemNavigationBarIconBrightness: Brightness.light,
              ),
      ),
      cardTheme: CardThemeData(
        color: palette.surfaceContainer,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadius.allLg,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: palette.outline,
        space: 1,
        thickness: 1,
      ),
      extensions: <ThemeExtension<dynamic>>[
        AppColorsTheme(palette),
      ],
    );
  }
}

/// Sugar so widgets can write `context.palette.primary` instead of
/// digging through theme extensions.
extension AppThemeContext on BuildContext {
  AppColors get palette =>
      Theme.of(this).extension<AppColorsTheme>()!.colors;
}
