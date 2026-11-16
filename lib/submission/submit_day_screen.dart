import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../collector/collector_api.dart';
import '../collector/collector_models.dart';
import '../collector/payment_saved_screen.dart';
import '../common/glass_card.dart';
import '../common/gradient_button.dart';
import '../common/money.dart';
import '../common/wash_header.dart';
import '../outbox/outbox.dart';
import '../outbox/outbox_screen.dart';
import '../sync/payment_sync.dart';
import '../theme/app_gradients.dart';
import '../theme/app_status_colors.dart';
import 'day_closure.dart';

/// Closing the day, design D1 ("Submit screen", owner decision 2026-11-16),
/// against backend PR #14 (decision D35).
///
/// Before submitting it shows today's totals and what still stands in the
/// way: payments on the phone the backend doesn't have yet, refused ones
/// (Submit is blocked until the admin sorts them out, owner decision
/// 2026-11-16), and payments still in their 10 minutes. After submitting,
/// the same screen shows the submission waiting for approval. Approval
/// signs the collector out; the screen checks every 30 seconds so the app
/// notices.
class SubmitDayScreen extends StatefulWidget {
  const SubmitDayScreen({
    super.key,
    required this.api,
    required this.outbox,
    required this.dayClosure,
    required this.syncOutbox,
    this.now,
    this.pollEvery = const Duration(seconds: 30),
  });

  final CollectorApi api;
  final Outbox outbox;
  final DayClosure dayClosure;

  /// Sends anything in the outbox that's ready, before the totals load.
  /// Also behind Try again in the Outbox opened from here.
  final Future<SyncReport> Function() syncOutbox;
  final DateTime Function()? now;
  final Duration pollEvery;

  @override
  State<SubmitDayScreen> createState() => _SubmitDayScreenState();
}

class _SubmitDayScreenState extends State<SubmitDayScreen> {
  CollectorDaySummary? _summary;
  DaySubmission? _submission;
  bool _loading = true;
  String? _loadError;
  bool _submitting = false;
  String? _submitError;
  Timer? _ticker;
  Timer? _poll;

  DateTime _now() => (widget.now ?? DateTime.now)().toUtc();

  @override
  void initState() {
    super.initState();
    _load();
    // Countdowns for payments still in their 10 minutes.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final summary = _summary;
      if (mounted && summary != null && summary.inWindow(_now()).isNotEmpty) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    // Already true on the first load, which starts from initState.
    if (!_loading || _loadError != null) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      await widget.syncOutbox();
    } catch (_) {
      // The checks below show whatever is still on the phone.
    }
    try {
      final results = await Future.wait<Object?>([
        widget.api.fetchLatestSubmission(),
        widget.api.fetchDaySummary(),
      ]);
      if (!mounted) return;
      final latest = results[0] as DaySubmission?;
      widget.dayClosure.update(latest);
      setState(() {
        _submission = latest != null && latest.isWaiting ? latest : null;
        _summary = results[1] as CollectorDaySummary;
        _loading = false;
      });
      _pollWhileWaiting();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = collectorErrorMessage(
          error,
          networkMessage: "Couldn't reach the server. Submitting needs a "
              'connection. Check it and try again.',
        );
      });
    }
  }

  /// While waiting, ask now and then: once it's approved the backend ends
  /// the session, the request gets a 401 and the app returns to sign-in.
  void _pollWhileWaiting() {
    _poll?.cancel();
    if (_submission == null) return;
    _poll = Timer.periodic(widget.pollEvery, (_) async {
      try {
        final latest = await widget.api.fetchLatestSubmission();
        if (!mounted) return;
        widget.dayClosure.update(latest);
        if (latest == null || !latest.isWaiting) {
          // Approved before the session ended here; reload the totals.
          _poll?.cancel();
          await _load();
        }
      } catch (_) {
        // Offline for now, or the session ended (handled by the app).
      }
    });
  }

  /// Why Submit can't go ahead yet, or null.
  String? _blocker() {
    final refused = widget.outbox.refused.length;
    if (refused > 0) {
      return '${_payments(refused)} on this phone ${refused == 1 ? 'was' : 'were'} '
          'refused by the server. Call your admin to sort '
          '${refused == 1 ? 'it' : 'them'} out before you submit.';
    }
    final waiting = widget.outbox.waiting.length;
    if (waiting > 0) {
      return "${_payments(waiting)} ${waiting == 1 ? "hasn't" : "haven't"} "
          'reached the server yet. They are sent when their 10 minutes are '
          "up and you're online. Submit after that.";
    }
    final inWindow = _summary?.inWindow(_now()) ?? const [];
    if (inWindow.isNotEmpty) {
      return '${_payments(inWindow.length)} ${inWindow.length == 1 ? 'is' : 'are'} '
          'still in ${inWindow.length == 1 ? 'its' : 'their'} 10 minutes. '
          'You can submit at ${clockTime(_lastWindowCloses(inWindow))}.';
    }
    return null;
  }

  static DateTime _lastWindowCloses(List<CollectorPayment> inWindow) =>
      inWindow
          .map((p) => p.correctableUntil!)
          .reduce((a, b) => a.isAfter(b) ? a : b);

  Future<void> _submit() async {
    if (_submitting) return;
    final blocker = _blocker();
    if (blocker != null) {
      setState(() => _submitError = blocker);
      return;
    }
    final total = _summary?.total ?? Cedis.zero;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('submit.confirmDialog'),
        title: const Text("Submit today's collections?"),
        content: Text(
          "You'll hand in ${total.format()} to the office. No more payments "
          "can be recorded until it's approved, and approval signs you out "
          'until tomorrow.',
        ),
        actions: [
          TextButton(
            key: const Key('submit.cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('submit.confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final submission = await widget.api.submitDay();
      if (!mounted) return;
      widget.dayClosure.update(submission);
      setState(() {
        _submitting = false;
        _submission = submission.isWaiting ? submission : null;
      });
      _pollWhileWaiting();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        // The backend's own words, such as when the collector can submit.
        _submitError = collectorErrorMessage(
          error,
          networkMessage: "Couldn't reach the server. Check your connection "
              "and tap Submit collections again. It won't be submitted twice.",
        );
      });
    }
  }

  static String _payments(int n) => n == 1 ? '1 payment' : '$n payments';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: ListenableBuilder(
          listenable: widget.outbox,
          builder: (context, _) => RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: EdgeInsets.zero,
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                _Header(
                  child: _loading && _summary == null && _submission == null
                      ? null
                      : _submission != null
                          ? _WaitingCard(submission: _submission!)
                          : _summary != null
                              ? _TodayCard(summary: _summary!)
                              : null,
                ),
                if (_loading) const LinearProgressIndicator(minHeight: 2),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: _body(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final submission = _submission;
    if (submission != null) return _WaitingDetails(submission: submission);

    final summary = _summary;
    if (summary == null) {
      if (_loadError == null) return const SizedBox.shrink();
      return _LoadError(message: _loadError!, onRetry: _load);
    }

    final outbox = widget.outbox;
    final inWindow = summary.inWindow(_now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _AmountRow(label: 'Savings', amount: summary.savingsTotal),
                const SizedBox(height: 6),
                _AmountRow(label: 'Shares', amount: summary.sharesTotal),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _outboxCheck(outbox),
                const SizedBox(height: 10),
                inWindow.isEmpty
                    ? const _Check.ok(
                        key: Key('submit.windowCheck'),
                        text: 'No payments in their 10 minutes',
                      )
                    : _Check.wait(
                        key: const Key('submit.windowCheck'),
                        text: '${_payments(inWindow.length)} in '
                            '${inWindow.length == 1 ? 'its' : 'their'} 10 '
                            'minutes · '
                            '${formatCountdown(_lastWindowCloses(inWindow).difference(_now()))}',
                      ),
              ],
            ),
          ),
        ),
        if (_submitError != null) ...[
          const SizedBox(height: 12),
          _ErrorBanner(message: _submitError!),
        ],
        const SizedBox(height: 16),
        GradientButton(
          key: const Key('submit.button'),
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    semanticsLabel: 'Submitting',
                  ),
                )
              : const Text('Submit collections'),
        ),
      ],
    );
  }

  Widget _outboxCheck(Outbox outbox) {
    final refused = outbox.refused.length;
    final waiting = outbox.waiting.length;
    if (refused > 0) {
      return _Check.blocked(
        key: const Key('submit.outboxCheck'),
        text: '${_payments(refused)} refused · call your admin',
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => OutboxScreen(
            outbox: outbox,
            onSync: widget.syncOutbox,
          ),
        )),
      );
    }
    if (waiting > 0) {
      return _Check.wait(
        key: const Key('submit.outboxCheck'),
        text: '${_payments(waiting)} still on this phone',
      );
    }
    return const _Check.ok(
      key: Key('submit.outboxCheck'),
      text: 'Nothing waiting on this phone',
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final gradients = AppGradients.of(context);
    final textTheme = Theme.of(context).textTheme;
    return WashHeader(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              BackButton(color: gradients.panelText),
              const SizedBox(width: 4),
              Text(
                'Submit today',
                key: const Key('submit.title'),
                style: textTheme.titleLarge?.copyWith(
                  color: gradients.panelText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (child != null) ...[const SizedBox(height: 12), child!],
        ],
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.summary});

  final CollectorDaySummary summary;

  @override
  Widget build(BuildContext context) {
    final gradients = AppGradients.of(context);
    final textTheme = Theme.of(context).textTheme;
    final label = textTheme.bodySmall?.copyWith(color: gradients.panelText);
    return GlassCard(
      padding: const EdgeInsets.all(14),
      radius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Today's collections", style: label),
          const SizedBox(height: 2),
          Text(
            summary.total.format(),
            key: const Key('submit.total'),
            style: textTheme.headlineMedium?.copyWith(
              color: gradients.panelText,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            summary.count == 1 ? '1 payment' : '${summary.count} payments',
            style: label,
          ),
        ],
      ),
    );
  }
}

class _WaitingCard extends StatelessWidget {
  const _WaitingCard({required this.submission});

  final DaySubmission submission;

  @override
  Widget build(BuildContext context) {
    final gradients = AppGradients.of(context);
    final status = AppStatusColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final label = textTheme.bodySmall?.copyWith(color: gradients.panelText);
    final submittedAt = submission.submittedAt;
    return GlassCard(
      padding: const EdgeInsets.all(14),
      radius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: status.warningContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.hourglass_top, size: 16, color: status.warning),
                  const SizedBox(width: 6),
                  Text(
                    'Waiting for approval',
                    key: const Key('submit.waiting'),
                    style: TextStyle(
                      color: status.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text('Cash to hand in', style: label),
          Text(
            submission.expectedAmount.format(),
            key: const Key('submit.expected'),
            style: textTheme.headlineMedium?.copyWith(
              color: gradients.panelText,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (submittedAt != null)
            Text('Submitted ${clockTime(submittedAt)}', style: label),
        ],
      ),
    );
  }
}

class _WaitingDetails extends StatelessWidget {
  const _WaitingDetails({required this.submission});

  final DaySubmission submission;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _CountRow(label: 'Payments', value: '${submission.paymentCount}'),
                if (submission.failedCount > 0) ...[
                  const SizedBox(height: 6),
                  _CountRow(
                    label: 'Failed (not in the cash total)',
                    value: '${submission.failedCount} · '
                        '${submission.failedAmount.format()}',
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Hand the cash to your agent or an administrator. No more payments '
          "can be recorded until it's approved. Approval signs you out until "
          'tomorrow.',
          key: const Key('submit.waitingText'),
          style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({required this.label, required this.amount});

  final String label;
  final Cedis amount;

  @override
  Widget build(BuildContext context) =>
      _CountRow(label: label, value: amount.format());
}

class _CountRow extends StatelessWidget {
  const _CountRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(child: Text(label, style: textTheme.bodyMedium)),
        Text(
          value,
          style: textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// One line in the checks card. Statuses use an icon and words, never
/// colour alone.
class _Check extends StatelessWidget {
  const _Check.ok({super.key, required this.text})
      : _kind = _CheckKind.ok,
        onTap = null;
  const _Check.wait({super.key, required this.text})
      : _kind = _CheckKind.wait,
        onTap = null;
  const _Check.blocked({super.key, required this.text, this.onTap})
      : _kind = _CheckKind.blocked;

  final String text;
  final VoidCallback? onTap;
  final _CheckKind _kind;

  @override
  Widget build(BuildContext context) {
    final status = AppStatusColors.of(context);
    final (icon, color) = switch (_kind) {
      _CheckKind.ok => (Icons.check_circle_outline, status.success),
      _CheckKind.wait => (Icons.schedule, status.warning),
      _CheckKind.blocked => (Icons.block, status.danger),
    };
    final row = Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _kind == _CheckKind.ok ? null : color,
                  fontWeight:
                      _kind == _CheckKind.ok ? null : FontWeight.w600,
                ),
          ),
        ),
        if (onTap != null) Icon(Icons.chevron_right, color: color),
      ],
    );
    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: row,
      ),
    );
  }
}

enum _CheckKind { ok, wait, blocked }

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final status = AppStatusColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: status.dangerContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: status.danger, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                key: const Key('submit.error'),
                style: TextStyle(color: status.danger),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ErrorBanner(message: message),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('submit.retry'),
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      ],
    );
  }
}
