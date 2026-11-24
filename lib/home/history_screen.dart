import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../collector/collector_api.dart';
import '../collector/collector_models.dart';
import '../common/glass_card.dart';
import '../common/money.dart';
import '../common/wash_header.dart';
import '../theme/app_gradients.dart';
import '../theme/app_status_colors.dart';
import 'payment_row.dart';
import 'today.dart';

/// Which records the history shows.
///
/// The filters from the approved design (Y1), less Withdrawals: collector
/// withdrawal requests were removed (owner decision 2026-11-15). Deposits
/// are savings deposits and Shares are share purchases, the backend's two
/// collector payment types.
enum HistoryFilter {
  all('All', 'payments'),
  deposits('Deposits', 'deposits'),
  shares('Shares', 'share payments');

  const HistoryFilter(this.label, this.plural);

  final String label;

  /// For the empty state: "No share payments yet".
  final String plural;

  bool matches(CollectorPayment payment) => switch (this) {
        HistoryFilter.all => true,
        HistoryFilter.deposits => payment.type == PaymentType.savings,
        HistoryFilter.shares => payment.type == PaymentType.shares,
      };
}

/// The collector's history, design Y1 ("wash header") with the day
/// switcher Y-A (owner decisions 2026-11-24):
///
/// - The wash across the top with a glass strip: arrows to step between
///   today and the 6 days before it (7 days in all), and that day's count
///   and total.
/// - Type filters, then the day's payments as the server has them
///   (`GET /api/collector/v1/payments?date=`), newest first, failed ones
///   with the server's reason. Payments still on the phone aren't here:
///   home and the Outbox show them (owner decision 2026-11-15, confirmed
///   2026-11-24).
/// - Under them, that day's submission, if there was one
///   (`GET /api/collector/v1/submissions`): waiting or approved, and the
///   cash.
///
/// Days are downloaded when first shown and kept while the app is signed
/// in; pull down to download again. Nothing is saved on the phone, so
/// History is gone once the session ends.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.api,
    this.active = true,
    this.now = DateTime.now,
  });

  final CollectorApi api;

  /// Whether the History tab is showing. It downloads only then, and the
  /// shown day again each time the tab is opened.
  final bool active;

  /// Replaceable in tests.
  final DateTime Function() now;

  /// Today and the 6 days before it (owner decision 2026-11-24).
  static const daysShown = 7;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  HistoryFilter _filter = HistoryFilter.all;
  int _daysBack = 0;

  final _days = <String, _Day>{};
  List<DaySubmission>? _submissions;

  @override
  void initState() {
    super.initState();
    // After the first frame: loading starts with a setState.
    if (widget.active) _afterFrame(_load);
  }

  @override
  void didUpdateWidget(HistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Each time the tab is opened, the shown day is downloaded again.
    if (widget.active && !oldWidget.active) {
      _afterFrame(() => _load(force: true));
    }
  }

  void _afterFrame(Future<void> Function() load) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) load();
    });
  }

  /// The shown day, as a UTC midnight (Accra time is UTC).
  DateTime get _day {
    final now = widget.now().toUtc();
    return DateTime.utc(now.year, now.month, now.day)
        .subtract(Duration(days: _daysBack));
  }

  Future<void> _load({bool force = false}) async {
    final day = _day;
    final key = backendDate(day);
    final known = _days[key];
    if (!force && known != null && (known.summary != null || known.loading)) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _days[key] = _Day(summary: known?.summary, loading: true);
    });

    _Day result;
    try {
      final summary = await widget.api.fetchDaySummary(day: day);
      result = _Day(summary: summary);
    } catch (error) {
      result = _Day(summary: known?.summary, error: error);
    }
    List<DaySubmission>? submissions = _submissions;
    if (force || submissions == null) {
      try {
        submissions = await widget.api.fetchSubmissions();
      } catch (_) {
        // The payments still show; the submission line waits for the next
        // download.
      }
    }
    if (!mounted) return;
    setState(() {
      _days[key] = result;
      _submissions = submissions;
    });
  }

  void _step(int days) {
    final next = _daysBack + days;
    if (next < 0 || next >= HistoryScreen.daysShown) return;
    setState(() => _daysBack = next);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final day = _day;
    final state = _days[backendDate(day)];
    final summary = state?.summary;
    final payments = [
      for (final p in summary?.payments ?? const <CollectorPayment>[])
        if (_filter.matches(p)) p,
    ];
    final submission = _submissionOn(day);

    // The wash runs under the status bar, so its icons follow the wash.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: RefreshIndicator(
          onRefresh: () => _load(force: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            children: [
              _HistoryHeader(
                dayLabel: historyDayLabel(day, _daysBack),
                countLabel: summary == null
                    ? (state?.loading ?? true ? 'Loading…' : '–')
                    : paymentCountLabel(_filteredCount(summary)),
                total: summary == null ? null : _filteredTotal(summary),
                onPrevious: _daysBack < HistoryScreen.daysShown - 1
                    ? () => _step(1)
                    : null,
                onNext: _daysBack > 0 ? () => _step(-1) : null,
              ),
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
                            onSelected: (_) =>
                                setState(() => _filter = filter),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (state?.error != null) ...[
                      _LoadError(
                        error: state!.error!,
                        onRetry: () => _load(force: true),
                      ),
                      const SizedBox(height: 12),
                    ],
                    // Only while a download runs: the tab sits offstage in
                    // an IndexedStack, where a spinner would keep animating.
                    if (summary == null && (state?.loading ?? false))
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (summary != null && payments.isEmpty)
                      _EmptyHistory(
                        filter: _filter,
                        today: _daysBack == 0,
                      )
                    else if (payments.isNotEmpty)
                      _PaymentList(payments: payments, now: widget.now()),
                    if (submission != null) ...[
                      const SizedBox(height: 12),
                      _SubmissionCard(submission: submission),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _filteredCount(CollectorDaySummary summary) => _filter == HistoryFilter.all
      ? summary.count
      : summary.payments.where(_filter.matches).length;

  Cedis _filteredTotal(CollectorDaySummary summary) => switch (_filter) {
        HistoryFilter.all => summary.total,
        HistoryFilter.deposits => summary.savingsTotal,
        HistoryFilter.shares => summary.sharesTotal,
      };

  /// The latest submission made on [day] (Accra time, UTC).
  DaySubmission? _submissionOn(DateTime day) {
    for (final s in _submissions ?? const <DaySubmission>[]) {
      final at = s.submittedAt?.toUtc();
      if (at != null &&
          at.year == day.year &&
          at.month == day.month &&
          at.day == day.day) {
        return s;
      }
    }
    return null;
  }
}

class _Day {
  const _Day({this.summary, this.loading = false, this.error});

  final CollectorDaySummary? summary;
  final bool loading;
  final Object? error;
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "Today · Tue 24 Nov", "Yesterday · Mon 23 Nov" or "Sun 22 Nov".
String historyDayLabel(DateTime day, int daysBack) {
  final date =
      '${_weekdays[day.weekday - 1]} ${day.day} ${_months[day.month - 1]}';
  return switch (daysBack) {
    0 => 'Today · $date',
    1 => 'Yesterday · $date',
    _ => date,
  };
}

/// "16 payments", "1 payment" or "No payments".
String paymentCountLabel(int count) => switch (count) {
      0 => 'No payments',
      1 => '1 payment',
      _ => '$count payments',
    };

/// The wash with the title and, on a glass strip, the day switcher and the
/// day's count and total.
class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader({
    required this.dayLabel,
    required this.countLabel,
    required this.total,
    required this.onPrevious,
    required this.onNext,
  });

  final String dayLabel;
  final String countLabel;
  final Cedis? total;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

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
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
            radius: 14,
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      key: const Key('history.previousDay'),
                      tooltip: 'Previous day',
                      onPressed: onPrevious,
                      color: gradients.panelText,
                      disabledColor: gradients.panelText.withValues(alpha: 0.35),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text(
                        dayLabel,
                        key: const Key('history.day'),
                        textAlign: TextAlign.center,
                        style: onGlass?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      key: const Key('history.nextDay'),
                      tooltip: 'Next day',
                      onPressed: onNext,
                      color: gradients.panelText,
                      disabledColor: gradients.panelText.withValues(alpha: 0.35),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          countLabel,
                          key: const Key('history.count'),
                          style: onGlass,
                        ),
                      ),
                      Text(
                        total?.format() ?? '',
                        key: const Key('history.total'),
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
          ),
        ],
      ),
    );
  }
}

class _PaymentList extends StatelessWidget {
  const _PaymentList({required this.payments, required this.now});

  final List<CollectorPayment> payments;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < payments.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 60),
            PaymentRow(
              key: Key('history.payment.$i'),
              payment: RecentPayment.fromServer(payments[i]),
              now: now,
              showFailureReason: true,
            ),
          ],
        ],
      ),
    );
  }
}

/// The day's submission: waiting with the cash to hand in, or approved
/// with the cash counted.
class _SubmissionCard extends StatelessWidget {
  const _SubmissionCard({required this.submission});

  final DaySubmission submission;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final status = AppStatusColors.of(context);
    final approved = submission.status == SubmissionStatus.approved;
    final submittedAt = submission.submittedAt;
    final approvedAt = submission.approvedAt;
    final (IconData icon, String state, Color fg, Color bg) = approved
        ? (
            Icons.check_circle_outline,
            approvedAt == null
                ? 'Approved'
                : 'Approved ${clockTime(approvedAt)}',
            status.success,
            status.successContainer,
          )
        : (
            Icons.schedule,
            'Waiting for approval',
            status.warning,
            status.warningContainer,
          );
    final cash = approved
        ? 'Counted ${(submission.countedAmount ?? submission.expectedAmount).format()}'
        : '${submission.expectedAmount.format()} to hand in';
    final failed = submission.failedCount == 0
        ? ''
        : ' · ${submission.failedCount} failed';

    return Card(
      key: const Key('history.submission'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.send_outlined, color: scheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    submittedAt == null
                        ? 'Submitted'
                        : 'Submitted ${clockTime(submittedAt)}',
                    style: textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 4),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: 14, color: fg),
                          const SizedBox(width: 4),
                          Text(
                            state,
                            style: textTheme.labelMedium?.copyWith(
                              color: fg,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$cash · ${paymentCountLabel(submission.paymentCount)}'
                    '$failed',
                    style: textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final status = AppStatusColors.of(context);
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: status.dangerContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              Icon(Icons.cloud_off_outlined, color: status.danger, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  collectorErrorMessage(
                    error,
                    networkMessage:
                        "Couldn't load this day. Check your connection.",
                  ),
                  key: const Key('history.error'),
                  style: TextStyle(color: status.danger),
                ),
              ),
              TextButton(
                key: const Key('history.retry'),
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({required this.filter, required this.today});

  final HistoryFilter filter;
  final bool today;

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
              today ? 'No ${filter.plural} yet' : 'No ${filter.plural} this day',
              key: const Key('history.empty'),
              style: textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              today
                  ? 'Payments the server has show here. Ones still on this '
                      'phone are on home and in the Outbox.'
                  : 'Nothing was recorded on this day.',
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
