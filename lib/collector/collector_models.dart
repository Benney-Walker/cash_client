import 'package:flutter/foundation.dart';

import '../common/money.dart';

/// The two kinds of payment a collector takes (backend `CollectorPaymentType`):
/// a deposit into the member's savings account, or a share purchase into
/// their shares account.
enum PaymentType {
  savings('SAVINGS', 'Savings', 'Savings deposit'),
  shares('SHARES', 'Shares', 'Share purchase');

  const PaymentType(this.wireName, this.label, this.description);

  /// As the backend writes it.
  final String wireName;

  /// Short label, for the type picker.
  final String label;

  /// What the payment is, for the confirm and saved screens.
  final String description;

  static PaymentType? fromWire(Object? value) {
    for (final type in values) {
      if (type.wireName == value) return type;
    }
    return null;
  }
}

/// One of a member's accounts a collector can pay into. The backend only
/// sends savings and shares accounts here, so each maps to a [PaymentType].
@immutable
class MemberAccount {
  const MemberAccount({required this.accountNumber, required this.type});

  final String accountNumber;
  final PaymentType type;

  @override
  bool operator ==(Object other) =>
      other is MemberAccount &&
      other.accountNumber == accountNumber &&
      other.type == type;

  @override
  int get hashCode => Object.hash(accountNumber, type);
}

/// A member as a collector may see them: the name and the accounts they can
/// record against, nothing else (owner decision 2026-11-07).
@immutable
class CollectorMember {
  const CollectorMember({required this.name, required this.accounts});

  final String name;
  final List<MemberAccount> accounts;

  MemberAccount? accountFor(PaymentType type) {
    for (final account in accounts) {
      if (account.type == type) return account;
    }
    return null;
  }

  /// Payment types this member has an account for, savings first.
  List<PaymentType> get paymentTypes => [
        for (final type in PaymentType.values)
          if (accountFor(type) != null) type,
      ];

  /// Parses one entry of `GET /api/collector/v1/members`:
  /// `{memberName, accounts: [{accountNumber, accountType}]}`. Accounts of
  /// any other type are skipped. Returns null if the entry is malformed.
  static CollectorMember? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final name = json['memberName'];
    final accounts = json['accounts'];
    if (name is! String || accounts is! List) return null;
    final parsed = <MemberAccount>[];
    for (final entry in accounts) {
      if (entry is! Map<String, dynamic>) continue;
      final number = entry['accountNumber'];
      final type = PaymentType.fromWire(entry['accountType']);
      if (number is String && number.isNotEmpty && type != null) {
        parsed.add(MemberAccount(accountNumber: number, type: type));
      }
    }
    return CollectorMember(name: name, accounts: List.unmodifiable(parsed));
  }
}

/// A payment's state on the backend (`TransactionStatus`). A collector
/// payment is PENDING during its 10-minute correction window, then
/// COMPLETED (balance updated, member texted) or FAILED.
/// How long a new payment stays on the phone before it's sent (owner
/// decision 2026-11-23). During it the collector can correct the amount or
/// the account in the app; it runs from when the payment was recorded, and
/// a correction doesn't restart it (owner decision 2026-11-24). The backend
/// counts no window: it applies a payment as soon as it arrives.
const holdWindow = Duration(minutes: 5);

enum PaymentStatus {
  pending,
  completed,
  failed,
  unknown;

  static PaymentStatus fromWire(Object? value) => switch (value) {
        'PENDING' => pending,
        'COMPLETED' => completed,
        'FAILED' => failed,
        _ => unknown,
      };

  /// As the backend writes it; null for a status the app doesn't know.
  String? get wireName => switch (this) {
        pending => 'PENDING',
        completed => 'COMPLETED',
        failed => 'FAILED',
        unknown => null,
      };
}

/// A payment as the backend returns it (`CollectorPaymentResponse`).
@immutable
class CollectorPayment {
  const CollectorPayment({
    required this.transactionId,
    required this.idempotencyKey,
    required this.type,
    required this.accountNumber,
    required this.memberName,
    required this.amount,
    required this.status,
    this.failureReason,
    this.createdAt,
    this.receivedAt,
  });

  final String transactionId;
  final String idempotencyKey;
  final PaymentType type;
  final String accountNumber;
  final String memberName;
  final Cedis amount;
  final PaymentStatus status;
  final String? failureReason;

  /// The phone's time when the payment was recorded (it decides the
  /// collector's day), read as UTC.
  final DateTime? createdAt;

  /// The server's time when it arrived.
  final DateTime? receivedAt;

  static CollectorPayment? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['transactionId'];
    final key = json['idempotencyKey'];
    final type = PaymentType.fromWire(json['type']);
    final account = json['accountNumber'];
    final name = json['memberName'];
    final amount = Cedis.fromJson(json['amount']);
    if (id is! String ||
        key is! String ||
        type == null ||
        account is! String ||
        name is! String ||
        amount == null) {
      return null;
    }
    final reason = json['failureReason'];
    return CollectorPayment(
      transactionId: id,
      idempotencyKey: key,
      type: type,
      accountNumber: account,
      memberName: name,
      amount: amount,
      status: PaymentStatus.fromWire(json['status']),
      failureReason: reason is String ? reason : null,
      createdAt: _time(json['createdAt']),
      receivedAt: _time(json['receivedAt']),
    );
  }

  static DateTime? _time(Object? value) => parseServerTime(value);

  /// The same shape [fromJson] reads, for keeping on the phone.
  Map<String, Object?> toJson() => {
        'transactionId': transactionId,
        'idempotencyKey': idempotencyKey,
        'type': type.wireName,
        'accountNumber': accountNumber,
        'memberName': memberName,
        'amount': amount.toDecimalString(),
        'status': status.wireName,
        'failureReason': failureReason,
        'createdAt': createdAt?.toUtc().toIso8601String(),
        'receivedAt': receivedAt?.toUtc().toIso8601String(),
      };
}

/// A backend `LocalDateTime` such as `2026-11-15T10:10:00`, as a UTC
/// [DateTime]. The backend's clock is Africa/Accra time, which is UTC all
/// year, so a time without a zone is read as UTC.
DateTime? parseServerTime(Object? value) {
  if (value is! String || value.isEmpty) return null;
  final hasZone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(value);
  return DateTime.tryParse(hasZone ? value : '${value}Z')?.toUtc();
}

/// The collector's payments for a day with totals, from
/// `GET /api/collector/v1/payments` (backend PR #14). Payments are final on
/// arrival (COMPLETED, or FAILED when the account was frozen meanwhile);
/// totals leave out FAILED ones.
@immutable
class CollectorDaySummary {
  const CollectorDaySummary({
    required this.count,
    required this.savingsTotal,
    required this.sharesTotal,
    required this.total,
    required this.payments,
  });

  final int count;
  final Cedis savingsTotal;
  final Cedis sharesTotal;
  final Cedis total;

  /// Newest first.
  final List<CollectorPayment> payments;

  static CollectorDaySummary? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final count = json['count'];
    final savings = Cedis.fromJson(json['savingsTotal']);
    final shares = Cedis.fromJson(json['sharesTotal']);
    final total = Cedis.fromJson(json['total']);
    final rawPayments = json['payments'];
    if (count is! int ||
        savings == null ||
        shares == null ||
        total == null ||
        rawPayments is! List) {
      return null;
    }
    final payments = <CollectorPayment>[];
    for (final entry in rawPayments) {
      final payment = CollectorPayment.fromJson(entry);
      if (payment == null) return null;
      payments.add(payment);
    }
    return CollectorDaySummary(
      count: count,
      savingsTotal: savings,
      sharesTotal: shares,
      total: total,
      payments: List.unmodifiable(payments),
    );
  }

  /// The same shape [fromJson] reads, for keeping on the phone.
  Map<String, Object?> toJson() => {
        'count': count,
        'savingsTotal': savingsTotal.toDecimalString(),
        'sharesTotal': sharesTotal.toDecimalString(),
        'total': total.toDecimalString(),
        'payments': [for (final payment in payments) payment.toJson()],
      };
}

/// The backend's `CollectorSubmissionStatus`. There's no rejection: the
/// approver records the cash counted (owner decision D35, 2026-11-15).
enum SubmissionStatus {
  submitted,
  approved,
  unknown;

  static SubmissionStatus fromWire(Object? value) => switch (value) {
        'SUBMITTED' => submitted,
        'APPROVED' => approved,
        _ => unknown,
      };
}

/// A daily submission, from `/api/collector/v1/submissions`.
@immutable
class DaySubmission {
  const DaySubmission({
    required this.id,
    required this.status,
    required this.paymentCount,
    required this.expectedAmount,
    required this.failedCount,
    required this.failedAmount,
    this.submittedAt,
    this.countedAmount,
    this.approvedAt,
  });

  final String id;
  final SubmissionStatus status;

  /// When the collector submitted, in UTC.
  final DateTime? submittedAt;

  /// Completed payments, whose total is the cash to hand in.
  final int paymentCount;
  final Cedis expectedAmount;

  /// Failed payments, counted separately for the approver.
  final int failedCount;
  final Cedis failedAmount;

  /// The cash the approver counted; null until approved.
  final Cedis? countedAmount;

  /// When it was approved, in UTC; null until then.
  final DateTime? approvedAt;

  bool get isWaiting => status == SubmissionStatus.submitted;

  static DaySubmission? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['submissionId'];
    final paymentCount = json['paymentCount'];
    final expected = Cedis.fromJson(json['expectedAmount']);
    final failedCount = json['failedCount'];
    final failedAmount = Cedis.fromJson(json['failedAmount']) ?? Cedis.zero;
    if (id is! String ||
        paymentCount is! int ||
        expected == null ||
        failedCount is! int) {
      return null;
    }
    return DaySubmission(
      id: id,
      status: SubmissionStatus.fromWire(json['status']),
      submittedAt: parseServerTime(json['submittedAt']),
      paymentCount: paymentCount,
      expectedAmount: expected,
      failedCount: failedCount,
      failedAmount: failedAmount,
      countedAmount: Cedis.fromJson(json['countedAmount']),
      approvedAt: parseServerTime(json['approvedAt']),
    );
  }
}
