import 'package:flutter/material.dart';

/// Mixin that makes widgets aware of their viewport visibility.
/// Use for animations/timers that should pause when not visible.
///
/// Example:
/// ```dart
/// class MyAnimatedWidget extends StatefulWidget {
///   @override
///   State<MyAnimatedWidget> createState() => _MyAnimatedWidgetState();
/// }
///
/// class _MyAnimatedWidgetState extends State<MyAnimatedWidget>
///     with ViewportAwareMixin {
///   late AnimationController _controller;
///
///   @override
///   void initState() {
///     super.initState();
///     _controller = AnimationController(vsync: this);
///     subscribeToVisibility();
///   }
///
///   @override
///   void onVisibilityChanged(bool isVisible) {
///     if (isVisible) {
///       _controller.forward();
///     } else {
///       _controller.stop();
///     }
///   }
///
///   @override
///   void dispose() {
///     unsubscribeFromVisibility();
///     _controller.dispose();
///     super.dispose();
///   }
/// }
/// ```
mixin ViewportAwareMixin on State {
  bool _isVisible = true;
  late WidgetsBinding _binding;

  /// Called when visibility changes. Override to react.
  void onVisibilityChanged(bool isVisible) {}

  /// Start monitoring visibility. Call in initState().
  void subscribeToVisibility() {
    _binding = WidgetsBinding.instance;
    _binding.addObserver(this as WidgetsBindingObserver);
  }

  /// Stop monitoring. Call in dispose().
  void unsubscribeFromVisibility() {
    _binding.removeObserver(this as WidgetsBindingObserver);
  }

  /// Whether this widget is currently visible.
  bool get isViewportVisible => _isVisible;
}

/// Utility: wraps a child that should pause animations when off-screen.
/// Useful for expensive animations in long lists.
class ViewportAwareBuilder extends StatefulWidget {
  const ViewportAwareBuilder({
    super.key,
    required this.builder,
    required this.child,
  });

  final Widget Function(BuildContext, bool isVisible) builder;
  final Widget child;

  @override
  State<ViewportAwareBuilder> createState() => _ViewportAwareBuilderState();
}

class _ViewportAwareBuilderState extends State<ViewportAwareBuilder>
    with WidgetsBindingObserver {
  bool _isVisible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (!_isVisible) {
          setState(() => _isVisible = true);
        }
      case AppLifecycleState.paused:
        if (_isVisible) {
          setState(() => _isVisible = false);
        }
      default:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _isVisible);
  }
}
