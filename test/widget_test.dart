import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:forge/app/router/app_router.dart';
import 'package:forge/app/router/route_paths.dart';
import 'package:forge/app/theme/app_theme.dart';

void main() {
  // Realistic device viewport for full-screen layouts. Default test
  // surface is 800×600 — shorter than any modern phone.
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first;
    view.physicalSize = const Size(390, 844) * 2.0;
    view.devicePixelRatio = 2.0;
  });

  tearDown(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first
        .resetPhysicalSize();
  });

  group('App router', () {
    /// Mounts the app **once** then navigates to every path in [paths].
    /// Re-pumping per iteration leaves orphaned widget trees that
    /// trigger spurious DEFUNCT-ancestor overflow reports from previous
    /// routes; one long-lived tree avoids that.
    Future<void> walkRoutes(WidgetTester tester, List<String> paths) async {
      final router = buildAppRouter();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();

      for (final String path in paths) {
        router.go(path);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          find.byType(Scaffold),
          findsAtLeastNWidgets(1),
          reason: 'Route $path did not render a Scaffold.',
        );
      }
    }

    testWidgets(
      'every static route mounts without error',
      (WidgetTester tester) =>
          walkRoutes(tester, RoutePaths.allStaticPaths),
    );

    testWidgets(
      'every parameterized route mounts with a sample id',
      (WidgetTester tester) =>
          walkRoutes(tester, RoutePaths.sampleParameterizedPaths()),
    );
  });
}
