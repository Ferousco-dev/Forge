import 'package:flutter/material.dart';

/// Helper for rendering large lists efficiently.
///
/// Best practices:
/// - Use [RepaintBoundary] on list items to isolate repaints.
/// - Use const constructors to prevent rebuilds.
/// - Implement [addRepaintBoundaries] in SliverList for expensive items.
/// - Use [ListView.separated] with constant separators.
class EfficientListRending {
  const EfficientListRending._();

  /// Wraps each list item in a RepaintBoundary for isolated rendering.
  /// Use this for expensive widgets in long lists.
  static Widget itemWithBoundary({required Widget child}) {
    return RepaintBoundary(child: child);
  }

  /// Create an efficient separator that doesn't rebuild.
  static const Widget defaultSeparator = SizedBox(height: 12);

  /// Helper to create a fixed-height list item (no layout thrashing).
  static SliverChildListDelegate fixedHeightItems({
    required List<Widget> items,
    required double height,
    bool addRepaintBoundaries = true,
  }) {
    return SliverChildListDelegate(
      items.map((w) => SizedBox(height: height, child: w)).toList(),
      addRepaintBoundaries: addRepaintBoundaries,
    );
  }
}
