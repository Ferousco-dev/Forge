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
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_chip.dart';
import '../../../shared/widgets/currency_text.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/error_state_view.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../jobs/widgets/job_card.dart';

enum _HistoryFilter {
  all('All', null),
  thisMonth('This month', Duration(days: 30)),
  threeMonths('Last 3 months', Duration(days: 90)),
  thisYear('This year', Duration(days: 365));

  const _HistoryFilter(this.label, this.window);
  final String label;
  final Duration? window;
}

/// Completed jobs + lifetime stats. Reuses `JobCard` with the
/// application's status badge so the list visually matches "My
/// applications · History".
class WorkHistoryScreen extends ConsumerStatefulWidget {
  const WorkHistoryScreen({super.key});

  @override
  ConsumerState<WorkHistoryScreen> createState() =>
      _WorkHistoryScreenState();
}

class _WorkHistoryScreenState extends ConsumerState<WorkHistoryScreen> {
  _HistoryFilter _filter = _HistoryFilter.all;

  List<JobApplication> _applyFilter(List<JobApplication> apps) {
    final window = _filter.window;
    if (window == null) return apps;
    final cutoff = DateTime.now().subtract(window);
    return apps
        .where((JobApplication a) =>
            (a.completedAt ?? a.appliedAt).isAfter(cutoff))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final workerAsync = ref.watch(currentWorkerProvider);
    final historyAsync = ref.watch(applicationHistoryProvider);
    // HomeShell injects the bottom-nav height + gesture inset via
    // MediaQuery.padding. Each list's bottom padding picks it up so the
    // last completed-job card clears the floating nav bar.
    final navInset = MediaQuery.paddingOf(context).bottom;
    final listBottomPad = AppSpacing.lg + navInset;

    return Scaffold(
      backgroundColor: palette.surface,
      appBar: AppBar(
        title: const Text('Work history'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            // Total stats card.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                0,
              ),
              child: workerAsync.when(
                loading: () => const LoadingShimmer.box(
                    width: double.infinity, height: 88),
                error: (Object _, StackTrace _) => const SizedBox.shrink(),
                data: (Worker w) => _TotalsCard(worker: w),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Filter chips.
            SizedBox(
              height: 30,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                itemCount: _HistoryFilter.values.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: AppSpacing.xs),
                itemBuilder: (BuildContext context, int i) {
                  final f = _HistoryFilter.values[i];
                  return AppChip(
                    label: f.label,
                    selected: f == _filter,
                    onTap: () => setState(() => _filter = f),
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.sm),

            // List.
            Expanded(
              child: historyAsync.when(
                loading: () => ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    listBottomPad,
                  ),
                  itemCount: 4,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.md),
                  itemBuilder: (_, _) => const JobCardSkeleton(),
                ),
                error: (Object err, StackTrace st) {
                  // Surface the real failure to the console — without
                  // this the banner hides parse errors (e.g. backend
                  // sends a slim DTO the local model can't decode) and
                  // makes them invisible to debug.
                  debugPrint('[work_history] $err\n$st');
                  return ErrorStateView(
                    title: "Couldn't load your work history",
                    message: 'Try again — your record is safe.',
                    onRetry: () =>
                        ref.invalidate(applicationHistoryProvider),
                  );
                },
                data: (List<JobApplication> apps) {
                  final filtered = _applyFilter(apps);
                  if (filtered.isEmpty) {
                    return EmptyStateView(
                      title: _filter == _HistoryFilter.all
                          ? 'No completed jobs yet'
                          : 'Nothing in this range',
                      subtitle: _filter == _HistoryFilter.all
                          ? 'Once you complete jobs, they show up here.'
                          : 'Pick a wider range or browse new jobs.',
                      illustration: Icon(
                        Icons.history_rounded,
                        size: 56,
                        color: palette.onSurfaceVariant
                            .withValues(alpha: 0.7),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.sm,
                      AppSpacing.lg,
                      listBottomPad,
                    ),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.md),
                    itemBuilder: (BuildContext context, int i) {
                      final app = filtered[i];
                      return JobCard(
                        job: app.job,
                        application: app,
                        // Route to the receipt screen, NOT the live job
                        // detail — once a job listing closes, `/jobs/:id`
                        // 404s and the worker hit "Couldn't load this
                        // job" from work history. The receipt reads
                        // /applications/:id which stays valid forever.
                        onTap: () => context.push(
                          RoutePaths.completedJobReceipt(app.id),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.worker});
  final Worker worker;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      borderColor: palette.primary.withValues(alpha: 0.16),
      borderRadius: AppRadius.allLg,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Lifetime',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: palette.onSurfaceVariant,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: <Widget>[
                    Text(
                      '${worker.jobsCompleted}',
                      style: AppTextStyles.headlineSmall.copyWith(
                        color: palette.onSurface,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'jobs',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: palette.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 36,
            color: palette.outlineVariant,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Earned',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: palette.onSurfaceVariant,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: CurrencyText(
                    amount: worker.totalEarned,
                    size: CurrencySize.small,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
