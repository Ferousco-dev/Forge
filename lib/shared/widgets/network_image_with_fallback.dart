import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app/theme/app_radius.dart';
import '../../app/theme/app_theme.dart';

/// Network image with graceful fallbacks at every load state.
///
/// - **Loading**: shows a soft surface placeholder with no spinner (a
///   spinner on a small avatar reads as broken).
/// - **Error**: shows the first letter of [fallbackInitial] in
///   primary-tinted text on the placeholder (typical avatar fallback).
/// - **Success**: fades the image in over 180ms.
///
/// Designed for avatars and small thumbnails. For large hero images,
/// build a richer placeholder instead.
class NetworkImageWithFallback extends StatelessWidget {
  const NetworkImageWithFallback({
    super.key,
    required this.imageUrl,
    required this.size,
    this.fallbackInitial,
    this.shape = BoxShape.circle,
    this.borderRadius,
    this.fit = BoxFit.cover,
  })  : assert(
          shape == BoxShape.circle || borderRadius != null,
          'Provide a borderRadius for non-circular shapes',
        );

  final String? imageUrl;
  final double size;
  final String? fallbackInitial;
  final BoxShape shape;
  final BorderRadius? borderRadius;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final placeholder = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.surfaceContainerHigh,
        shape: shape,
        borderRadius: shape == BoxShape.rectangle ? borderRadius : null,
      ),
      child: fallbackInitial == null || fallbackInitial!.isEmpty
          ? Icon(
              Icons.person_rounded,
              size: size * 0.5,
              color: palette.onSurfaceVariant.withValues(alpha: 0.7),
            )
          : Text(
              fallbackInitial!.substring(0, 1).toUpperCase(),
              style: TextStyle(
                fontSize: size * 0.42,
                fontWeight: FontWeight.w600,
                color: palette.primary,
                height: 1.0,
              ),
            ),
    );

    if (imageUrl == null || imageUrl!.isEmpty) return placeholder;

    // Decode hint: pixel-perfect for retina, no more. Avoids decoding
    // a 4000×4000 selfie into a 40×40 avatar slot — that was the
    // single biggest cause of jank on screens with multiple avatars.
    final mediaRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    final int cachePx = (size * mediaRatio).round();

    final image = SizedBox(
      width: size,
      height: size,
      child: CachedNetworkImage(
        imageUrl: imageUrl!,
        fit: fit,
        memCacheWidth: cachePx,
        memCacheHeight: cachePx,
        maxWidthDiskCache: cachePx,
        maxHeightDiskCache: cachePx,
        fadeInDuration: const Duration(milliseconds: 180),
        placeholder: (BuildContext _, String _) => placeholder,
        errorWidget: (BuildContext _, String _, Object _) => placeholder,
      ),
    );

    // ClipOval / ClipRRect are GPU-accelerated; ClipPath with a custom
    // clipper forces a software path. Same visual, cheaper paint.
    if (shape == BoxShape.circle) {
      return ClipOval(child: image);
    }
    return ClipRRect(
      borderRadius:
          borderRadius ?? const BorderRadius.all(AppRadius.radiusMd),
      child: image,
    );
  }
}
