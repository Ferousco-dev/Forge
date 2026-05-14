import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:go_router/go_router.dart';

import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../../shared/widgets/offline_banner.dart';
import 'route_paths.dart';

// Tab-root membership check. Written as a `switch` (jump table) rather
// than a `Set.contains` walk; this runs on every build of the shell.
bool _isTabRoot(String path) {
  switch (path) {
    case RoutePaths.jobs:
    case RoutePaths.earnings:
    case RoutePaths.loans:
    case RoutePaths.profile:
      return true;
    default:
      return false;
  }
}

const List<_TabSpec> _tabs = <_TabSpec>[
  _TabSpec(
    label: 'Jobs',
    icon: Icons.work_outline_rounded,
    activeIcon: Icons.work_rounded,
    path: RoutePaths.jobs,
  ),
  _TabSpec(
    label: 'Earnings',
    icon: Icons.account_balance_wallet_outlined,
    activeIcon: Icons.account_balance_wallet_rounded,
    path: RoutePaths.earnings,
  ),
  _TabSpec(
    label: 'Loans',
    icon: Icons.trending_up_outlined,
    activeIcon: Icons.trending_up_rounded,
    path: RoutePaths.loans,
  ),
  _TabSpec(
    label: 'Profile',
    icon: Icons.person_outline_rounded,
    activeIcon: Icons.person_rounded,
    path: RoutePaths.profile,
  ),
];

/// Fixed nav-bar height. Matches the original `NavigationBarTheme`
/// height from before this file was refactored. Used to (a) reserve
/// bottom space on tab roots so content isn't covered, and (b)
/// translate the bar by exactly its own height when sliding it
/// off-screen.
const double _kNavBarHeight = 56.0;

/// Shell scaffold for the four bottom-nav tabs.
///
/// Uses [StatefulNavigationShell] so each tab keeps its own
/// `Navigator` state — the worker can drill into a job, switch to
/// Earnings, switch back, and find their position preserved.
///
/// ## Nav-bar visibility
///
/// The bar slides up/down on top of the body based on whether the
/// current route is a tab root (`/jobs`, `/earnings`, `/loans`,
/// `/profile`). Two correctness properties this implementation
/// guarantees that earlier attempts didn't:
///
/// 1. **No body-size jumps.** We use a Stack with the bar OVERLAID,
///    not `Scaffold.bottomNavigationBar`. Swapping that property
///    between null and non-null resizes the body every push/pop,
///    which reflows DraggableScrollableSheet snap positions, the
///    map's camera, and ListView extents — that's what produced the
///    "very buggy" feeling on every navigation.
///
/// 2. **Build-driven, not listener-driven.** Visibility is computed
///    synchronously inside `build()` from
///    `GoRouter.of(context).routerDelegate.currentConfiguration.uri`.
///    GoRouter rebuilds this shell whenever the route changes
///    (including pops back to a tab root), so `build` IS the
///    notification — adding a separate listener double-handles every
///    event and introduced the "stays hidden after pop" bug.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _onTap(int index) {
    navigationShell.goBranch(
      index,
      // Pop to the branch root if the tab is already active. Standard
      // mobile pattern (Twitter, Instagram, etc.).
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    // Synchronous read — no listener. GoRouter rebuilds HomeShell
    // whenever the active route changes (push OR pop), so the value
    // we read here is always the live one.
    final uri = GoRouter.of(context).routerDelegate.currentConfiguration.uri;
    final showNav = _isTabRoot(uri.path);

    // We only intercept back when the active branch's inner navigator
    // has nothing left to pop — i.e. we're sitting on a tab root.
    // Otherwise letting the system pop normally drills back through
    // the tab's stack (detail → list).
    final bool atTabRoot = _isTabRoot(uri.path);

    return PopScope(
      canPop: !atTabRoot,
      onPopInvokedWithResult: (bool didPop, Object? _) async {
        if (didPop) return;
        final bool leave = await _confirmLeaveApp(context) ?? false;
        if (leave) {
          await SystemNavigator.pop();
        }
      },
      child: Scaffold(
      // NO bottomNavigationBar — see the doc comment on this class
      // for why. We overlay the bar in a Stack instead.
      //
      // resizeToAvoidBottomInset: false at the SHELL level — when a
      // keyboard opens on a child screen, we don't want the shell's
      // overlay nav-bar to ride up with the keyboard (looks like a
      // bug). Child screens with forms manage their own keyboard
      // inset via `viewInsetsOf(context).bottom` so they stay
      // keyboard-aware while the shell stays still.
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: <Widget>[
          // 1. Branch content. Padded at the bottom by the nav-bar
          //    height (plus system gesture inset) ONLY when the bar
          //    is visible — so on tab roots the last scroll item
          //    isn't hidden behind the bar, and on detail pages the
          //    full vertical space is available.
          Positioned.fill(
            child: Column(
              children: <Widget>[
                const OfflineBanner(),
                Expanded(
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      padding: MediaQuery.of(context).padding.copyWith(
                        bottom: showNav ? _kNavBarHeight + bottomInset : 0,
                      ),
                    ),
                    child: navigationShell,
                  ),
                ),
              ],
            ),
          ),

          // 2. Bottom nav, overlaid. AnimatedSlide moves it off-screen
          //    when not on a tab root — body never resizes, no reflow
          //    on push/pop. IgnorePointer when hidden so taps fall
          //    through to whatever's behind.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: !showNav,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                offset: showNav ? Offset.zero : const Offset(0, 1),
                child: RepaintBoundary(
                  child: _NavBar(
                    palette: palette,
                    currentIndex: navigationShell.currentIndex,
                    onTap: _onTap,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Future<bool?> _confirmLeaveApp(BuildContext context) {
    final palette = context.palette;
    return showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          backgroundColor: palette.surface,
          title: const Text('Leave app?'),
          content: const Text('Do you want to leave the app?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Yes'),
            ),
          ],
        );
      },
    );
  }
}

/// Bottom-nav presentation. Lifted out so the parent's rebuild for
/// route changes doesn't reallocate the nav itself — child of
/// AnimatedSlide is preserved across the offset change.
class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.palette,
    required this.currentIndex,
    required this.onTap,
  });

  final dynamic palette;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    // Wrap the NavigationBar in a `ColoredBox` that paints the bar's
    // background colour all the way to the bottom of the screen,
    // INCLUDING the area underneath the system gesture/home indicator.
    // Without this the home indicator strip on iPhone / the gesture
    // bar on Android shows the previous page's pixels (or a dark
    // letterbox), which is what the screenshot was showing.
    //
    // SafeArea(top: false) then re-applies the bottom inset to the
    // NavigationBar's touch targets so labels and icons don't sit
    // under the home indicator.
    // Custom row instead of Material `NavigationBar` — that widget
    // enforces a ~80px minimum regardless of theme height. This gives
    // us exact control: the bar is _kNavBarHeight tall, period.
    return ColoredBox(
      color: palette.surfaceContainer,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: _kNavBarHeight,
          child: Row(
            children: <Widget>[
              for (int i = 0; i < _tabs.length; i++)
                Expanded(
                  child: _NavItem(
                    spec: _tabs[i],
                    selected: i == currentIndex,
                    palette: palette,
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.spec,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final _TabSpec spec;
  final bool selected;
  final dynamic palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? palette.primary : palette.onSurfaceVariant;
    return InkResponse(
      onTap: onTap,
      containedInkWell: true,
      highlightShape: BoxShape.rectangle,
      child: Tooltip(
        message: spec.label,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              selected ? spec.activeIcon : spec.icon,
              size: 22,
              color: color,
            ),
            const SizedBox(height: 2),
            Text(
              spec.label,
              style: AppTextStyles.labelMedium.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 11,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabSpec {
  const _TabSpec({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.path,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final String path;
}
