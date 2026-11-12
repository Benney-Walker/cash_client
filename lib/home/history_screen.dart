import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common/glass_card.dart';
import '../common/wash_header.dart';
import '../theme/app_gradients.dart';

/// Which records the history shows.
///
/// These are the filters from the approved design (Y1). The record types
/// they match will come from the backend once it can list a collector's
/// records.
enum HistoryFilter {
  all('All', 'records'),
  deposits('Deposits', 'deposits'),
  shares('Shares', 'share payments'),
  withdrawals('Withdrawals', 'withdrawal requests');

  const HistoryFilter(this.label, this.plural);

  final String label;

  /// For the empty state: "No share payments yet".
  final String plural;
}

/// The collector's transaction history, design Y1 ("wash header"): the
/// wash across the top with today's count and total on a glass strip, then
/// type filters and the records on the plain page.
///
/// Until the backend can list a collector's records, it shows an empty day.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  HistoryFilter _filter = HistoryFilter.all;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // The wash runs under the status bar, so its icons follow the wash.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: ListView(
          padding: EdgeInsets.zero,
          children: [
            const _HistoryHeader(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final filter in HistoryFilter.values)
                        ChoiceChip(
                          key: Key('history.filter.${filter.name}'),
                          label: Text(filter.label),
                          selected: filter == _filter,
                          onSelected: (_) => setState(() => _filter = filter),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _EmptyHistory(filter: _filter),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The wash with the title and today's count and total.
class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader();

  @override
  Widget build(BuildContext context) {
    final gradients = AppGradients.of(context);
    final textTheme = Theme.of(context).textTheme;
    // Everything on the glass uses panelText; see GlassCard.
    final onGlass = textTheme.bodyMedium?.copyWith(color: gradients.panelText);

    return WashHeader(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              'History',
              style: textTheme.titleLarge?.copyWith(
                color: gradients.panelText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 10),
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            radius: 14,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Today · 0 records',
                    key: const Key('history.todayCount'),
                    style: onGlass,
                  ),
                ),
                Text(
                  'GH₵ 0.00',
                  key: const Key('history.todayTotal'),
                  style: onGlass?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
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

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({required this.filter});

  final HistoryFilter filter;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
        child: Column(
          children: [
            Icon(Icons.history, size: 36, color: scheme.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(
              'No ${filter.plural} yet',
              key: const Key('history.empty'),
              style: textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Your deposits, share payments and withdrawal requests will '
              'show here.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
