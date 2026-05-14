import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/route_paths.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/mock/mock_providers.dart';
import '../../../core/mock/models.dart';
import '../state/notifications_state.dart';
import '../../../shared/widgets/app_text_button.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/error_state_view.dart';
import '../../../shared/widgets/loading_shimmer.dart';

/// Notifications inbox.
///
/// Brief: list grouped by date (Today / Yesterday / This Week / Earlier),
/// each item shows kind-driven icon + title + body + relative time + an
/// unread dot. "Mark all read" link in the app bar. Empty state when
/// list is empty.
///
/// Read state is local — backend integration replaces the in-memory
/// `_readIds` set with a server mutation.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  /// Notification ids the user has marked read in this session.
  final Set<String> _readIds = <String>{};

  /// Optimistic mark-all-read. Marks every id locally, fires the
  /// server mutation, and re-fetches the page on completion so the
  /// `unread_count` badge stays in sync.
  Future<void> _markAllRead(List<AppNotification> all) async {
    setState(() {
      _readIds.addAll(all.map((AppNotification n) => n.id));
    });
    try {
      await ref.read(notificationsRepositoryProvider).markAllRead();
    } finally {
      if (mounted) ref.invalidate(notificationsPageProvider);
    }
  }

  /// Optimistic single-item read.
  Future<void> _markOneRead(AppNotification n) async {
    if (!n.unread || _readIds.contains(n.id)) return;
    setState(() => _readIds.add(n.id));
    try {
      await ref.read(notificationsRepositoryProvider).markRead(n.id);
    } catch (_) {
      // Swallow — the next page-fetch is the source of truth.
    }
  }

  /// Fire-and-forget the read mark, then route via the carried
  /// deeplink. Mirrors the `forge://...` → GoRouter translation in
  /// `app.dart`, which handles the FCM tap path. Without this, in-app
  /// taps just dimmed the row and went nowhere — the bug screenshots
  /// of "Forge / Your work is being verified" not opening the pending-
  /// review screen.
  void _onItemTap(AppNotification n) {
    _markOneRead(n);
    final target = _resolveDeeplink(n.deeplink);
    if (target != null) context.push(target);
  }

  /// Translate a `forge://…` deeplink into a GoRouter path. Returns
  /// null when the link is missing, malformed, or maps to a route the
  /// app doesn't expose. Kept in sync with the table at
  /// `endpoint_resources/24_push_notifications.md`.
  static String? _resolveDeeplink(String? deeplink) {
    if (deeplink == null || deeplink.isEmpty) return null;
    final uri = Uri.tryParse(deeplink);
    if (uri == null || uri.scheme != 'forge') return null;
    final segments = uri.pathSegments;
    switch (uri.host) {
      case 'jobs':
        if (segments.isEmpty) return null;
        if (segments.length == 1) return '/jobs/${segments[0]}';
        return '/jobs/${segments[0]}/${segments[1]}';
      case 'transactions':
        if (segments.isEmpty) return null;
        return '/earnings/transactions/${segments[0]}';
      case 'loans':
        if (segments.isEmpty) return null;
        return '/loans/${segments[0]}';
      case 'notifications':
        return RoutePaths.profileNotifications;
      default:
        return null;
    }
  }

  bool _isUnread(AppNotification n) => n.unread && !_readIds.contains(n.id);

  Map<String, List<AppNotification>> _group(List<AppNotification> all) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final thisWeek = today.subtract(const Duration(days: 7));

    final groups = <String, List<AppNotification>>{
      'Today': <AppNotification>[],
      'Yesterday': <AppNotification>[],
      'This week': <AppNotification>[],
      'Earlier': <AppNotification>[],
    };

    for (final AppNotification n in all) {
      final ts = n.timestamp;
      if (!ts.isBefore(today)) {
        groups['Today']!.add(n);
      } else if (!ts.isBefore(yesterday)) {
        groups['Yesterday']!.add(n);
      } else if (!ts.isBefore(thisWeek)) {
        groups['This week']!.add(n);
      } else {
        groups['Earlier']!.add(n);
      }
    }

    groups.removeWhere(
      (String _, List<AppNotification> v) => v.isEmpty,
    );
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final asyncList = ref.watch(notificationsProvider);

    return Scaffold(
      backgroundColor: palette.surface,
      appBar: AppBar(
        title: const Text('Notifications'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: <Widget>[
          asyncList.maybeWhen(
            data: (List<AppNotification> all) {
              final unread = all.any(_isUnread);
              return Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: AppTextButton(
                  label: 'Mark all read',
                  onPressed: unread ? () => _markAllRead(all) : null,
                  dense: true,
                ),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: asyncList.when(
          loading: () => ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: 6,
            separatorBuilder: (_, _) =>
                const SizedBox(height: AppSpacing.md),
            itemBuilder: (_, _) => const _NotificationSkeleton(),
          ),
          error: (Object _, StackTrace _) => ErrorStateView(
            title: "Couldn't load notifications",
            message: 'Try again — your alerts are safe.',
            onRetry: () => ref.invalidate(notificationsProvider),
          ),
          data: (List<AppNotification> all) {
            if (all.isEmpty) {
              return EmptyStateView(
                title: 'No notifications yet',
                subtitle:
                    "We'll let you know when new jobs appear, when "
                    'employers respond, and when you get paid.',
                illustration: Icon(
                  Icons.notifications_off_outlined,
                  size: 56,
                  color: palette.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              );
            }
            final groups = _group(all);
            // Flatten into a single list of row "specs" so
            // ListView.builder can lazy-render offscreen rows. The
            // previous Column-of-everything built every row up-front.
            final List<_Row> rows = <_Row>[];
            for (final MapEntry<String, List<AppNotification>> entry
                in groups.entries) {
              rows.add(_Row.header(entry.key));
              for (final AppNotification n in entry.value) {
                rows.add(_Row.item(n));
              }
              rows.add(const _Row.gap());
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              itemCount: rows.length,
              itemBuilder: (BuildContext _, int i) {
                final _Row row = rows[i];
                switch (row.kind) {
                  case _RowKind.header:
                    return _GroupLabel(label: row.label!);
                  case _RowKind.item:
                    final AppNotification n = row.notification!;
                    return _NotificationItem(
                      notification: n,
                      unread: _isUnread(n),
                      onTap: () => _onItemTap(n),
                    );
                  case _RowKind.gap:
                    return const SizedBox(height: AppSpacing.lg);
                }
              },
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Row spec for lazy ListView.builder
// ---------------------------------------------------------------------

enum _RowKind { header, item, gap }

class _Row {
  const _Row._(this.kind, {this.label, this.notification});
  const _Row.header(String label) : this._(_RowKind.header, label: label);
  const _Row.item(AppNotification n)
      : this._(_RowKind.item, notification: n);
  const _Row.gap() : this._(_RowKind.gap);

  final _RowKind kind;
  final String? label;
  final AppNotification? notification;
}

// ---------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------

class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Text(
        label.toUpperCase(),
        style: AppTextStyles.labelSmall.copyWith(
          color: palette.onSurfaceVariant,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _NotificationItem extends StatelessWidget {
  const _NotificationItem({
    required this.notification,
    required this.unread,
    required this.onTap,
  });

  final AppNotification notification;
  final bool unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tint = _tintFor(notification.kind, palette);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  _iconFor(notification.kind),
                  size: 20,
                  color: tint,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            notification.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.titleSmall.copyWith(
                              color: palette.onSurface,
                              fontWeight: unread
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (unread) ...<Widget>[
                          const SizedBox(width: AppSpacing.sm),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: palette.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      notification.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      _formatRelative(notification.timestamp),
                      style: AppTextStyles.labelSmall.copyWith(
                        color: palette.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(NotificationKind kind) {
    switch (kind) {
      case NotificationKind.newJob:
        return Icons.work_rounded;
      case NotificationKind.applicationUpdate:
        return Icons.task_alt_rounded;
      case NotificationKind.payment:
        return Icons.account_balance_wallet_rounded;
      case NotificationKind.loan:
        return Icons.trending_up_rounded;
      case NotificationKind.system:
        return Icons.campaign_rounded;
    }
  }

  static Color _tintFor(NotificationKind kind, dynamic palette) {
    switch (kind) {
      case NotificationKind.newJob:
        return palette.info as Color;
      case NotificationKind.applicationUpdate:
        return palette.primary as Color;
      case NotificationKind.payment:
        return palette.success as Color;
      case NotificationKind.loan:
        return palette.warning as Color;
      case NotificationKind.system:
        return palette.onSurfaceVariant as Color;
    }
  }

  static String _formatRelative(DateTime when) {
    final delta = DateTime.now().difference(when);
    if (delta.inDays >= 7) return '${delta.inDays ~/ 7}w ago';
    if (delta.inDays >= 1) return '${delta.inDays}d ago';
    if (delta.inHours >= 1) return '${delta.inHours}h ago';
    if (delta.inMinutes >= 1) return '${delta.inMinutes}m ago';
    return 'Just now';
  }
}

class _NotificationSkeleton extends StatelessWidget {
  const _NotificationSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          LoadingShimmer.circle(size: 40),
          SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                LoadingShimmer.line(width: 200, height: 14),
                SizedBox(height: 6),
                LoadingShimmer.line(width: 260, height: 11),
                SizedBox(height: 4),
                LoadingShimmer.line(width: 60, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
