import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/route_paths.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/mock/models.dart';
import '../state/preferences_state.dart';
import '../state/settings_state.dart';

/// Fire-and-forget PATCH `/me/preferences`. Local provider state has
/// already updated for instant UI; if the server rejects the change
/// the next page open will re-hydrate from the truth.
void _syncPrefs(WidgetRef ref, NotificationPreferences? notifs,
    PrivacyPreferences? privacy) {
  final repo = ref.read(preferencesRepositoryProvider);
  // Map mobile-side preference shapes into the wire shape.
  final notifToggles = notifs == null
      ? null
      : NotificationToggles(
          newJobAlerts: notifs.newJobAlerts,
          applicationUpdates: notifs.applicationUpdates,
          paymentConfirmations: notifs.paymentConfirmations,
          loanReminders: notifs.loanReminders,
        );
  final privacyToggles = privacy == null
      ? null
      : PrivacyToggles(
          allowLocationTrackingDuringWork:
              privacy.allowLocationTrackingDuringWork,
        );
  unawaited(repo.patch(
    notifications: notifToggles,
    privacy: privacyToggles,
  ));
}

void unawaited(Future<dynamic> _) {}

/// Settings — notification toggles, preferences (language + theme),
/// privacy controls, account actions.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.surface,
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          // Bottom padding accounts for the floating nav bar that
          // HomeShell injects into MediaQuery.padding.bottom (0 on
          // routes where the nav is hidden, nav-height otherwise).
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.sm + MediaQuery.paddingOf(context).bottom,
          ),
          children: <Widget>[
            const _SectionLabel('Notifications'),
            _NotificationsSection(),
            const SizedBox(height: AppSpacing.lg),

            const _SectionLabel('Preferences'),
            _PreferencesSection(),
            const SizedBox(height: AppSpacing.lg),

            const _SectionLabel('Privacy'),
            _PrivacySection(),
            const SizedBox(height: AppSpacing.lg),

            const _SectionLabel('Account'),
            _AccountSection(),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Text(
        text.toUpperCase(),
        style: AppTextStyles.labelSmall.copyWith(
          color: palette.onSurfaceVariant,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.label,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.tint,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tone = tint ?? palette.onSurface;
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
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: (tint ?? palette.primary).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 18, color: tone),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: tone,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (subtitle != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: palette.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: AppSpacing.sm),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Notifications section
// ---------------------------------------------------------------------

class _NotificationsSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(notificationPrefsProvider);
    final notifier = ref.read(notificationPrefsProvider.notifier);
    final palette = context.palette;
    return Column(
      children: <Widget>[
        _SettingTile(
          icon: Icons.work_rounded,
          label: 'New job alerts',
          trailing: Switch.adaptive(
            value: prefs.newJobAlerts,
            activeThumbColor: palette.primary,
            onChanged: (bool v) {
              final next = prefs.copyWith(newJobAlerts: v);
              notifier.state = next;
              _syncPrefs(ref, next, null);
            },
          ),
        ),
        _SettingTile(
          icon: Icons.task_alt_rounded,
          label: 'Application updates',
          trailing: Switch.adaptive(
            value: prefs.applicationUpdates,
            activeThumbColor: palette.primary,
            onChanged: (bool v) {
              final next = prefs.copyWith(applicationUpdates: v);
              notifier.state = next;
              _syncPrefs(ref, next, null);
            },
          ),
        ),
        _SettingTile(
          icon: Icons.account_balance_wallet_rounded,
          label: 'Payment confirmations',
          trailing: Switch.adaptive(
            value: prefs.paymentConfirmations,
            activeThumbColor: palette.primary,
            onChanged: (bool v) {
              final next = prefs.copyWith(paymentConfirmations: v);
              notifier.state = next;
              _syncPrefs(ref, next, null);
            },
          ),
        ),
        _SettingTile(
          icon: Icons.trending_up_rounded,
          label: 'Loan reminders',
          trailing: Switch.adaptive(
            value: prefs.loanReminders,
            activeThumbColor: palette.primary,
            onChanged: (bool v) {
              final next = prefs.copyWith(loanReminders: v);
              notifier.state = next;
              _syncPrefs(ref, next, null);
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// Preferences section — language + theme
// ---------------------------------------------------------------------

class _PreferencesSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: const <Widget>[
        _ThemeSelectorTile(),
      ],
    );
  }
}

class _ThemeSelectorTile extends ConsumerWidget {
  const _ThemeSelectorTile();

  static const Map<ThemeMode, String> _labels = <ThemeMode, String>{
    ThemeMode.light: 'Light',
    ThemeMode.dark: 'Dark',
    ThemeMode.system: 'System',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final mode = ref.watch(themeModeProvider);
    return _SettingTile(
      icon: Icons.brightness_6_rounded,
      label: 'Theme',
      subtitle: _labels[mode],
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () async {
        final selected = await showModalBottomSheet<ThemeMode>(
          context: context,
          backgroundColor: palette.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppRadius.xl),
            ),
          ),
          builder: (BuildContext sheet) => SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: palette.outline,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  for (final ThemeMode option in ThemeMode.values)
                    RadioListTile<ThemeMode>(
                      value: option,
                      // ignore: deprecated_member_use
                      groupValue: mode,
                      // ignore: deprecated_member_use
                      onChanged: (ThemeMode? v) {
                        if (v != null) Navigator.of(sheet).pop(v);
                      },
                      title: Text(
                        _labels[option] ?? '',
                        style: AppTextStyles.bodyLarge.copyWith(
                          color: palette.onSurface,
                        ),
                      ),
                      activeColor: palette.primary,
                    ),
                ],
              ),
            ),
          ),
        );
        if (selected != null) {
          ref.read(themeModeProvider.notifier).state = selected;
        }
      },
    );
  }
}

// ---------------------------------------------------------------------
// Privacy section
// ---------------------------------------------------------------------

class _PrivacySection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(privacyPrefsProvider);
    final palette = context.palette;
    return Column(
      children: <Widget>[
        _SettingTile(
          icon: Icons.location_on_rounded,
          label: 'Location during work',
          subtitle:
              'Lets us verify your arrival and that you stayed on site.',
          trailing: Switch.adaptive(
            value: prefs.allowLocationTrackingDuringWork,
            activeThumbColor: palette.primary,
            onChanged: (bool v) {
              final next = prefs.copyWith(
                allowLocationTrackingDuringWork: v,
              );
              ref.read(privacyPrefsProvider.notifier).state = next;
              _syncPrefs(ref, null, next);
            },
          ),
        ),
        _SettingTile(
          icon: Icons.shield_rounded,
          label: 'Manage your data',
          subtitle: 'Download or request deletion of your records.',
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.push(RoutePaths.profileManageData),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// Account section
// ---------------------------------------------------------------------

class _AccountSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      children: <Widget>[
        _SettingTile(
          icon: Icons.phone_iphone_rounded,
          label: 'Change phone number',
          subtitle: 'Requires re-verification by SMS.',
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(
                behavior: SnackBarBehavior.floating,
                margin: EdgeInsets.all(AppSpacing.base),
                content: Text(
                  'Phone change ships with the auth backend integration.',
                ),
              ));
          },
        ),
        _SettingTile(
          icon: Icons.delete_outline_rounded,
          label: 'Delete account',
          tint: palette.error,
          onTap: () => _confirmDelete(context),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final palette = context.palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: palette.surface,
        title: Text(
          'Delete your account?',
          style: AppTextStyles.titleLarge.copyWith(
            color: palette.onSurface,
          ),
        ),
        content: Text(
          "This permanently removes your work record, transaction history, "
          "and credit profile from Forge. You can't undo it.",
          style: AppTextStyles.bodyMedium.copyWith(
            color: palette.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(color: palette.onSurfaceVariant),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Delete',
              style: TextStyle(color: palette.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(AppSpacing.base),
        backgroundColor: palette.surfaceContainerHigh,
        content: Text(
          'Account deletion is queued (backend integration pending).',
          style: TextStyle(color: palette.onSurface),
        ),
      ));
  }
}
