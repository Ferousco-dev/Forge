import 'package:flutter/material.dart';

import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../shared/widgets/app_card.dart';

/// Help & support — search bar, FAQ, contact options, WhatsApp footer.
class HelpSupportScreen extends StatefulWidget {
  const HelpSupportScreen({super.key});

  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen> {
  static const List<({String question, String answer})> _faq = [
    (
      question: 'How do I get matched with a job?',
      answer:
          "After you complete onboarding, jobs near your work radius "
          'show up on the Jobs tab — ranked by distance and pay. Tap '
          'Apply on any job and the employer will respond shortly.'
    ),
    (
      question: 'When do I get paid?',
      answer:
          'When you submit a clock-out photo and your work is verified, '
          "the employer's payment lands in your wallet instantly via "
          'Squad. You can withdraw to your linked bank from the '
          'Earnings tab.'
    ),
    (
      question: 'How is my credit score calculated?',
      answer:
          'Your score reflects your work record — jobs completed, '
          'on-time arrival, total earned, and time on Forge. Each '
          "completed job nudges it up; missed work brings it down."
    ),
    (
      question: 'What if I get to the job site and the employer cancels?',
      answer:
          'Tap Report issue on the job detail screen. Our support team '
          'investigates within 24 hours and may compensate you for '
          'travel time depending on the situation.'
    ),
    (
      question: 'Can I work without sharing my location?',
      answer:
          "Most jobs require location verification at clock-in to "
          "protect both you and the employer. You can toggle "
          'background tracking off in Settings; foreground tracking '
          'during a job is required.'
    ),
    (
      question: 'How do I change my linked bank account?',
      answer:
          'Open Earnings → Withdraw → Change. Linking a new account '
          'requires the bank name and a 10-digit account number; the '
          'name resolves automatically.'
    ),
  ];

  String _query = '';

  List<({String question, String answer})> get _filtered {
    if (_query.trim().isEmpty) return _faq;
    final q = _query.toLowerCase();
    return _faq
        .where((({String question, String answer}) item) =>
            item.question.toLowerCase().contains(q) ||
            item.answer.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final double keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    // HomeShell injects the bottom-nav height + gesture inset into
    // MediaQuery.padding when the nav is showing. Add it explicitly to
    // the ListView's bottom padding so the last WhatsApp card clears
    // the floating nav bar instead of sitting underneath it.
    final double navInset = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: palette.surface,
      // Don't let the body resize when the search field gets focused —
      // keeps the HomeShell bottom nav still and lets the ListView's
      // own auto-scroll bring the focused field into view.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('Help & support'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.sm + keyboardInset + navInset,
          ),
          children: <Widget>[
            _SearchBar(
              onChanged: (String v) => setState(() => _query = v),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Common questions',
              style: AppTextStyles.titleLarge.copyWith(
                color: palette.onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_filtered.isEmpty)
              _EmptyResult(query: _query)
            else
              for (final ({String question, String answer}) item
                  in _filtered)
                _FaqItem(question: item.question, answer: item.answer),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Contact us',
              style: AppTextStyles.titleLarge.copyWith(
                color: palette.onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _ContactRow(
              icon: Icons.chat_bubble_outline_rounded,
              label: 'Chat with support',
              subtitle: 'Replies within a few minutes during work hours',
              onTap: () => _stub(context, 'In-app chat'),
            ),
            _ContactRow(
              icon: Icons.call_rounded,
              label: 'Call us',
              subtitle: '+234 700 4673 432',
              onTap: () => _stub(context, 'Phone link'),
            ),
            _ContactRow(
              icon: Icons.mail_outline_rounded,
              label: 'Email us',
              subtitle: 'support@forge.app',
              onTap: () => _stub(context, 'Email link'),
            ),
            const SizedBox(height: AppSpacing.lg),
            _WhatsAppCard(onTap: () => _stub(context, 'WhatsApp link')),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  void _stub(BuildContext context, String channel) {
    final palette = context.palette;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(AppSpacing.base),
        backgroundColor: palette.surfaceContainerHigh,
        content: Text(
          '$channel wires up at backend integration.',
          style: TextStyle(color: palette.onSurface),
        ),
      ));
  }
}

// ---------------------------------------------------------------------
// Search bar
// ---------------------------------------------------------------------

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.onChanged});
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: palette.outline),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        children: <Widget>[
          Icon(Icons.search_rounded,
              size: 20, color: palette.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextField(
              onChanged: onChanged,
              cursorColor: palette.primary,
              cursorWidth: 1.6,
              style: AppTextStyles.bodyMedium.copyWith(
                color: palette.onSurface,
              ),
              decoration: InputDecoration(
                hintText: 'Search help articles',
                hintStyle: AppTextStyles.bodyMedium.copyWith(
                  color: palette.onSurfaceVariant,
                ),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 14),
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// FAQ
// ---------------------------------------------------------------------

class _FaqItem extends StatefulWidget {
  const _FaqItem({required this.question, required this.answer});
  final String question;
  final String answer;

  @override
  State<_FaqItem> createState() => _FaqItemState();
}

class _FaqItemState extends State<_FaqItem> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.xl),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.base),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        widget.question,
                        style: AppTextStyles.titleSmall.copyWith(
                          color: palette.onSurface,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: palette.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 200),
              crossFadeState: _expanded
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              firstChild: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.base,
                  0,
                  AppSpacing.base,
                  AppSpacing.base,
                ),
                child: Column(
                  children: <Widget>[
                    Divider(height: 1, color: palette.outlineVariant),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      widget.answer,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: palette.onSurfaceVariant,
                        height: 1.55,
                      ),
                    ),
                  ],
                ),
              ),
              secondChild: const SizedBox(width: double.infinity, height: 0),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyResult extends StatelessWidget {
  const _EmptyResult({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Center(
        child: Text(
          'No articles match "$query".',
          style: AppTextStyles.bodyMedium.copyWith(
            color: palette.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Contact rows
// ---------------------------------------------------------------------

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
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
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: palette.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 18, color: palette.primary),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        label,
                        style: AppTextStyles.titleSmall.copyWith(
                          color: palette.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: palette.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: palette.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WhatsAppCard extends StatelessWidget {
  const _WhatsAppCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // WhatsApp's brand green — kept literal because brand alignment
    // with the platform is the point of this row.
    const Color whatsappGreen = Color(0xFF25D366);
    return Material(
      color: whatsappGreen.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: <Widget>[
              const Icon(
                Icons.chat_rounded,
                size: 20,
                color: whatsappGreen,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'WhatsApp support',
                      style: AppTextStyles.titleSmall.copyWith(
                        color: palette.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Open a chat — same Forge team.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.open_in_new_rounded,
                size: 18,
                color: whatsappGreen,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
