import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/route_paths.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/mock/mock_providers.dart';
import '../../../core/mock/models.dart';
import '../../auth/state/auth_state.dart';
import '../../../shared/widgets/error_state_view.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../../shared/widgets/network_image_with_fallback.dart';
import '../../../shared/widgets/primary_button.dart';

/// Stacked drop-shadow used by every grouped card on this screen.
///
/// Two layers — a tight near-shadow + a diffuse far-shadow — match the
/// Apple/Stripe pattern. In light mode the warm-ink tint at α 0.06 / 0.10
/// gives the card real visible lift off the cream surface; in dark mode
/// `palette.shadow` is pure black painted onto a near-black surface, so
/// the same shadow effectively disappears — no per-theme branching.
List<BoxShadow> _groupShadow(AppColors palette) => <BoxShadow>[
      BoxShadow(
        color: palette.shadow.withValues(alpha: 0.06),
        blurRadius: 4,
        offset: const Offset(0, 1),
      ),
      BoxShadow(
        color: palette.shadow.withValues(alpha: 0.10),
        blurRadius: 28,
        offset: const Offset(0, 12),
      ),
    ];

/// Profile tab — hub linking to every settings/history surface.
///
/// Composition:
///   1. Pinned "Profile" title (matches Earnings/Loans).
///   2. Calm centered hero — avatar + name + primary skill + phone.
///      No card frame; the page is the frame.
///   3. A single grouped stats block (Apple Health-style three-column
///      with vertical hairlines).
///   4. Apple-style grouped settings lists — quiet section captions over
///      rounded containers with internal dividers.
///   5. Destructive log-out tile in its own group.
///   6. Quiet version footer.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  /// Pull-to-refresh — re-fetches `GET /me`. Per the spec, this
  /// endpoint is the canonical source for stats (jobs done, wallet
  /// balance, reliability) and is expected to be hit on every
  /// pull-to-refresh in earnings, profile, and loans.
  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(currentWorkerProvider);
    await ref.read(currentWorkerProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final workerAsync = ref.watch(currentWorkerProvider);

    // Bottom inset is the nav-bar height + system gesture bar — see
    // HomeShell which injects this into MediaQuery.padding.bottom.
    final double bottomPad = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: palette.surface,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
            SliverAppBar(
              pinned: true,
              floating: false,
              elevation: 0,
              scrolledUnderElevation: 0,
              backgroundColor: palette.surface,
              surfaceTintColor: Colors.transparent,
              automaticallyImplyLeading: false,
              titleSpacing: AppSpacing.lg,
              toolbarHeight: 56,
              title: Text(
                'Profile',
                style: AppTextStyles.headlineMedium.copyWith(
                  color: palette.onSurface,
                ),
              ),
            ),
            ...workerAsync.when(
              loading: () => const <Widget>[
                SliverToBoxAdapter(child: _LoadingSkeleton()),
              ],
              error: (Object err, StackTrace _) => <Widget>[
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: ErrorStateView(
                    title: "Couldn't load your profile",
                    // Surface the backend's user-facing message when we
                    // got a real envelope back (e.g. "Session expired —
                    // sign in again."). Network / unknown failures fall
                    // through to a calmer default.
                    message: err is ApiException && !err.isNetwork
                        ? err.message
                        : 'Check your connection and try again.',
                    onRetry: () => ref.invalidate(currentWorkerProvider),
                  ),
                ),
              ],
              data: (Worker w) => <Widget>[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate(<Widget>[
                      _Hero(worker: w),
                      const SizedBox(height: AppSpacing.xl),
                      _StatsGroup(worker: w),
                      const SizedBox(height: AppSpacing.xl),
                      _SettingsGroup(
                        caption: 'Account',
                        rows: <_SettingsRowData>[
                          _SettingsRowData(
                            icon: Icons.dynamic_feed_rounded,
                            label: 'Active jobs',
                            onTap: () =>
                                context.push(RoutePaths.activeJobs),
                          ),
                          _SettingsRowData(
                            icon: Icons.task_alt_rounded,
                            label: 'My applications',
                            onTap: () =>
                                context.push(RoutePaths.profileApplications),
                          ),
                          _SettingsRowData(
                            icon: Icons.bookmark_rounded,
                            label: 'Saved jobs',
                            onTap: () =>
                                context.push(RoutePaths.profileBookmarks),
                          ),
                          _SettingsRowData(
                            icon: Icons.history_rounded,
                            label: 'Work history',
                            onTap: () =>
                                context.push(RoutePaths.profileWorkHistory),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _SettingsGroup(
                        caption: 'Preferences',
                        rows: <_SettingsRowData>[
                          _SettingsRowData(
                            icon: Icons.notifications_rounded,
                            label: 'Notifications',
                            onTap: () =>
                                context.push(RoutePaths.profileNotifications),
                          ),
                          _SettingsRowData(
                            icon: Icons.tune_rounded,
                            label: 'Settings',
                            onTap: () =>
                                context.push(RoutePaths.profileSettings),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _SettingsGroup(
                        caption: 'Support',
                        rows: <_SettingsRowData>[
                          _SettingsRowData(
                            icon: Icons.help_outline_rounded,
                            label: 'Help & support',
                            onTap: () =>
                                context.push(RoutePaths.profileHelp),
                          ),
                          _SettingsRowData(
                            icon: Icons.description_outlined,
                            label: 'Terms of service',
                            onTap: () =>
                                context.push(RoutePaths.profileTerms),
                          ),
                          _SettingsRowData(
                            icon: Icons.privacy_tip_outlined,
                            label: 'Privacy policy',
                            onTap: () =>
                                context.push(RoutePaths.profilePrivacy),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      _LogoutGroup(),
                      const SizedBox(height: AppSpacing.xl),
                      _Footer(worker: w),
                      const SizedBox(height: AppSpacing.lg),
                    ]),
                  ),
                ),
              ],
            ),
            // Pad past the floating bottom nav so the last row isn't
            // covered.
            SliverToBoxAdapter(child: SizedBox(height: bottomPad)),
          ],
        ),
        ),
      ),
    );
  }

}

// ---------------------------------------------------------------------
// Hero — calm centered identity block. No card. The page is the frame.
// ---------------------------------------------------------------------

class _Hero extends StatelessWidget {
  const _Hero({required this.worker});
  final Worker worker;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      children: <Widget>[
        // Avatar with a subtle primary-tinted ring — gives the photo a
        // halo without tilting into "decorative".
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: palette.primary.withValues(alpha: 0.14),
              width: 1.5,
            ),
          ),
          child: NetworkImageWithFallback(
            imageUrl: worker.photoUrl,
            size: 88,
            fallbackInitial: worker.name,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          worker.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.titleLarge.copyWith(
            color: palette.onSurface,
            fontWeight: FontWeight.w700,
            fontSize: 22,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        _SkillRow(worker: worker),
        const SizedBox(height: AppSpacing.xs + 2),
        Text(
          _formatPhone(worker.phoneNumber),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.bodySmall.copyWith(
            color: palette.onSurfaceVariant,
            letterSpacing: 0.1,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _EditProfileButton(),
      ],
    );
  }

  /// Light formatting for display only — never mutate the underlying
  /// phone number on the model. "+2348012345678" → "+234 801 234 5678".
  static String _formatPhone(String raw) {
    if (raw.length < 7) return raw;
    final trimmed = raw.replaceAll(RegExp(r'\s+'), '');
    if (trimmed.startsWith('+234') && trimmed.length == 14) {
      return '${trimmed.substring(0, 4)} '
          '${trimmed.substring(4, 7)} '
          '${trimmed.substring(7, 10)} '
          '${trimmed.substring(10)}';
    }
    return trimmed;
  }
}

/// Primary-skill chip + a quiet verified pip when reliability has crossed
/// the trust threshold (≥80). Both pieces are read-only — no new data,
/// just composition over what the model already exposes.
class _SkillRow extends StatelessWidget {
  const _SkillRow({required this.worker});
  final Worker worker;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // "Verified" requires actual track record, not just the
    // backend's default-100 reliability for fresh accounts.
    final isVerified =
        worker.jobsCompleted >= 5 && worker.reliabilityScore >= 80;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm + 2,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: palette.surfaceContainer,
              borderRadius: BorderRadius.circular(AppRadius.full),
              border: Border.all(color: palette.outline, width: 1),
            ),
            child: Text(
              worker.primarySkill,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.labelMedium.copyWith(
                color: palette.onSurface,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ),
        if (isVerified) ...<Widget>[
          const SizedBox(width: AppSpacing.xs + 2),
          Tooltip(
            message: 'Verified worker — ≥80% reliability',
            child: Icon(
              Icons.verified_rounded,
              size: 16,
              color: palette.primary,
            ),
          ),
        ],
      ],
    );
  }
}

class _EditProfileButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.surfaceContainer,
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.full),
        onTap: () => context.push(RoutePaths.profileEdit),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm + 2,
          ),
          child: Text(
            'Edit profile',
            style: AppTextStyles.labelLarge.copyWith(
              color: palette.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Stats group — single grouped block, three columns separated by thin
// vertical hairlines (Apple Health / iOS Wallet tile style).
// ---------------------------------------------------------------------

class _StatsGroup extends StatelessWidget {
  const _StatsGroup({required this.worker});
  final Worker worker;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: palette.outline, width: 1),
        boxShadow: _groupShadow(palette),
      ),
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.base,
        horizontal: AppSpacing.sm,
      ),
      child: IntrinsicHeight(
        child: Row(
          children: <Widget>[
            Expanded(
              // "100% reliability" is misleading for a worker who hasn't
              // done a single job yet — there's nothing to be reliable
              // about. Show an em-dash until at least one job has been
              // completed, at which point the percentage means something.
              child: worker.jobsCompleted == 0
                  ? const _StatCell(label: 'Reliability', value: '—')
                  : _StatCell(
                      label: 'Reliability',
                      value: '${worker.reliabilityScore}',
                      unit: '%',
                    ),
            ),
            _StatDivider(),
            Expanded(
              child: _StatCell(
                label: 'Jobs done',
                value: '${worker.jobsCompleted}',
              ),
            ),
            _StatDivider(),
            Expanded(
              child: _StatCell(
                label: 'Rating',
                value: worker.averageRating.toStringAsFixed(1),
                trailingIcon: Icons.star_rounded,
                trailingTint: palette.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      color: palette.outline,
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.label,
    required this.value,
    this.unit,
    this.trailingIcon,
    this.trailingTint,
  });

  final String label;
  final String value;
  final String? unit;
  final IconData? trailingIcon;
  final Color? trailingTint;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.headlineSmall.copyWith(
                    color: palette.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 22,
                    letterSpacing: -0.4,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ),
              if (unit != null)
                Padding(
                  padding: const EdgeInsets.only(left: 1, bottom: 3),
                  child: Text(
                    unit!,
                    style: AppTextStyles.labelMedium.copyWith(
                      color: palette.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (trailingIcon != null) ...<Widget>[
                const SizedBox(width: 2),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Icon(
                    trailingIcon,
                    size: 16,
                    color: trailingTint ?? palette.secondary,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelSmall.copyWith(
              color: palette.onSurfaceVariant,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Settings group — Apple-style: small caps caption + rounded container
// with rows separated by hairlines. One container reads as one unit.
// ---------------------------------------------------------------------

class _SettingsRowData {
  const _SettingsRowData({
    required this.icon,
    required this.label,
    required this.onTap,
    this.tint,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? tint;
  final Widget? trailing;
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.caption, required this.rows});

  final String caption;
  final List<_SettingsRowData> rows;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.sm,
            bottom: AppSpacing.sm,
          ),
          child: Text(
            caption.toUpperCase(),
            style: AppTextStyles.labelSmall.copyWith(
              color: palette.onSurfaceVariant,
              letterSpacing: 1.0,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: palette.surfaceContainer,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: palette.outline, width: 1),
            boxShadow: _groupShadow(palette),
          ),
          child: ClipRRect(
            // Inner clip so InkWell ripples don't bleed past the
            // rounded corners. The shadow sits on the outer Container.
            borderRadius: BorderRadius.circular(AppRadius.xl),
            child: Column(
              children: <Widget>[
                for (int i = 0; i < rows.length; i++) ...<Widget>[
                  if (i > 0)
                    Padding(
                      // Indent the divider to align with the row label
                      // (skipping the leading icon block) — Apple
                      // Settings convention.
                      padding: const EdgeInsets.only(
                        left: AppSpacing.base + 36 + AppSpacing.md,
                      ),
                      child: Divider(
                        height: 1,
                        thickness: 1,
                        color: palette.outlineVariant,
                      ),
                    ),
                  _SettingsRow(data: rows[i]),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.data});
  final _SettingsRowData data;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isDestructive = data.tint != null;
    final iconTint =
        isDestructive ? data.tint! : palette.onSurface;
    final labelTint =
        isDestructive ? data.tint! : palette.onSurface;
    final iconBg = isDestructive
        ? data.tint!.withValues(alpha: 0.10)
        : palette.surfaceContainerHigh;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: data.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base,
            vertical: AppSpacing.md + 2,
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(AppRadius.sm + 2),
                ),
                alignment: Alignment.center,
                child: Icon(data.icon, size: 18, color: iconTint),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  data.label,
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: labelTint,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.05,
                  ),
                ),
              ),
              data.trailing ??
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 22,
                    color: palette.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Logout — own group, gentle red tint, confirms before action.
// ---------------------------------------------------------------------

class _LogoutGroup extends ConsumerWidget {
  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final palette = context.palette;
    final shouldLogout = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: palette.surface,
      // Dim the page behind the sheet a touch more than Material's
      // default for stronger focus on a destructive action.
      barrierColor: palette.shadow.withValues(alpha: 0.45),
      isScrollControlled: false,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (BuildContext sheet) => const _LogoutSheet(),
    );

    if (shouldLogout != true || !context.mounted) return;

    // Best-effort `DELETE /me/devices/:device_id` BEFORE we drop the
    // access token — once `logout()` clears it, the device row can't
    // be removed. Failure is swallowed inside the service; the
    // server's own NotRegistered pruning is the canonical cleanup.
    await ref.read(notificationsServiceProvider).unregister();

    // Best-effort server logout — invalidates the refresh token on the
    // backend's blocklist. Always proceeds to the local clear, which
    // is the source of truth for the next cold start.
    await ref.read(authRepositoryProvider).logout();

    // Drop any cached worker-scoped data so the next signed-in session
    // starts clean. Providers downstream of these (jobs, transactions,
    // loans, notifications) invalidate transitively, and the splash
    // gate re-resolves the now-empty session on next launch.
    ref
      ..invalidate(authSessionProvider)
      ..invalidate(currentWorkerProvider)
      ..invalidate(transactionsProvider)
      ..invalidate(activeLoanProvider);

    if (!context.mounted) return;
    // Replace the entire navigation stack with login. `go` (not `push`)
    // is critical here — `push` would leave the authenticated tabs in
    // history, so a back-press would land the user back inside the app.
    context.go(RoutePaths.login);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: palette.outline, width: 1),
        boxShadow: _groupShadow(palette),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: _SettingsRow(
          data: _SettingsRowData(
            icon: Icons.logout_rounded,
            label: 'Log out',
            onTap: () => _confirm(context, ref),
            tint: palette.error,
            trailing: const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Logout sheet — premium bottom-sheet confirmation. Replaces the default
// AlertDialog with an Apple Action Sheet-style flow: drag handle, large
// destructive glyph, reassuring copy, full-width destructive primary
// button, ghost cancel below.
// ---------------------------------------------------------------------

class _LogoutSheet extends StatelessWidget {
  const _LogoutSheet();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Drag handle — matches the theme-selector sheet so the two
            // sheets feel like the same component family.
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: palette.outline,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Destructive glyph in a soft red circle. Larger than the
            // settings-row icon so it carries the moment.
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: palette.error.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.logout_rounded,
                size: 24,
                color: palette.error,
              ),
            ),
            const SizedBox(height: AppSpacing.base),

            Text(
              'Log out of Forge?',
              textAlign: TextAlign.center,
              style: AppTextStyles.titleLarge.copyWith(
                color: palette.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: AppSpacing.xs + 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Text(
                "We'll keep your work record, earnings, and credit profile "
                'safe. Sign back in any time with your phone number.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: palette.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            // Destructive primary — error-tinted PrimaryButton so the
            // press feedback (scale + opacity) and sizing match the
            // rest of the app's CTAs.
            PrimaryButton(
              label: 'Log out',
              fillColor: palette.error,
              foregroundColor: palette.onError,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: AppSpacing.sm),

            // Ghost cancel — sized to match the primary so the two
            // actions read as a balanced pair.
            SizedBox(
              width: double.infinity,
              height: 56,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                ),
                child: Text(
                  'Cancel',
                  style: AppTextStyles.titleSmall.copyWith(
                    color: palette.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Footer — quiet member-since line + version.
// ---------------------------------------------------------------------

class _Footer extends StatelessWidget {
  const _Footer({required this.worker});
  final Worker worker;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final since = _memberSince(worker.joinedAt);
    return Center(
      child: Column(
        children: <Widget>[
          Text(
            'Member since $since',
            style: AppTextStyles.labelSmall.copyWith(
              color: palette.onSurfaceVariant,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Forge · v1.0.0',
            style: AppTextStyles.labelSmall.copyWith(
              color: palette.onSurfaceVariant.withValues(alpha: 0.7),
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }

  static String _memberSince(DateTime when) {
    const months = <String>[
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[when.month - 1]} ${when.year}';
  }
}

// ---------------------------------------------------------------------
// Loading skeleton — mirrors the new layout's vertical rhythm so the
// page doesn't jump on data arrival.
// ---------------------------------------------------------------------

class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        children: <Widget>[
          // Hero
          LoadingShimmer.circle(size: 88),
          SizedBox(height: AppSpacing.md),
          LoadingShimmer.line(width: 160, height: 22),
          SizedBox(height: AppSpacing.xs + 2),
          LoadingShimmer.line(width: 120, height: 14),
          SizedBox(height: AppSpacing.xs + 2),
          LoadingShimmer.line(width: 180, height: 12),
          SizedBox(height: AppSpacing.lg),
          LoadingShimmer.box(width: 160, height: 40),
          SizedBox(height: AppSpacing.xl),

          // Stats group
          LoadingShimmer.box(width: double.infinity, height: 80),
          SizedBox(height: AppSpacing.xl),

          // Settings groups
          LoadingShimmer.box(width: double.infinity, height: 168),
          SizedBox(height: AppSpacing.lg),
          LoadingShimmer.box(width: double.infinity, height: 112),
        ],
      ),
    );
  }
}

